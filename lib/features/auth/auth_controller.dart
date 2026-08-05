import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/auth_repository.dart';
import '../../providers/providers.dart';
import 'auth_validators.dart';

/// A one-tap way out of the wrong door.
///
/// Firebase cannot reliably tell us up front whether an email is registered:
/// `fetchSignInMethodsForEmail` returns an empty list once Email Enumeration
/// Protection is on, which it is by default. Branching the UI on it would be
/// unreliable, and disabling the protection to make it work would trade a
/// real security property for a cosmetic one.
///
/// So the flow finds out the honest way — by trying — and turns the resulting
/// error into an offer instead of a dead end.
enum AuthRecovery {
  none,

  /// Sign-up hit an email that already has an account → offer sign-in.
  accountExists,

  /// Sign-in found no account for that email → offer sign-up.
  noAccount,
}

/// Everything an auth form needs to render, in one immutable value.
///
/// Errors are split by destination: [fieldErrors] render inline under the
/// field that caused them, [banner] is for problems that belong to the whole
/// form (no connection, rate limited, service down).
class AuthState {
  const AuthState({
    this.busy = false,
    this.banner,
    this.fieldErrors = const {},
    this.notice,
    this.recovery = AuthRecovery.none,
  });

  final bool busy;
  final String? banner;
  final Map<AuthField, String> fieldErrors;

  /// Transient success message (e.g. "reset link sent").
  final String? notice;

  /// Set when the user is on the wrong screen for the email they typed.
  final AuthRecovery recovery;

  bool get hasErrors => banner != null || fieldErrors.isNotEmpty;

  AuthState copyWith({
    bool? busy,
    String? banner,
    Map<AuthField, String>? fieldErrors,
    String? notice,
    AuthRecovery? recovery,
    bool clearBanner = false,
    bool clearNotice = false,
  }) =>
      AuthState(
        busy: busy ?? this.busy,
        banner: clearBanner ? null : (banner ?? this.banner),
        fieldErrors: fieldErrors ?? this.fieldErrors,
        notice: clearNotice ? null : (notice ?? this.notice),
        recovery: recovery ?? this.recovery,
      );
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);

/// The email last typed on any auth screen.
///
/// Carried across Sign in ⇄ Create account ⇄ Reset so switching screens never
/// costs the user their typing — the single most common complaint about
/// splitting auth into separate routes.
final authEmailProvider =
    NotifierProvider<AuthEmail, String>(AuthEmail.new);

class AuthEmail extends Notifier<String> {
  @override
  String build() => '';

  void set(String value) {
    final next = value.trim();
    if (next != state) state = next;
  }
}

/// Owns the submit lifecycle so the widgets only render.
///
/// The contract that fixes the original bug: **a successful credential call
/// can never be reported as a failure.** The network call sits alone in its
/// own try; every post-success side effect (autofill commit, haptics) runs
/// afterwards behind its own guard and can only ever be swallowed.
class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthState();

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  /// Called when moving between auth screens — a rejection from the previous
  /// screen must not sit over a fresh form.
  void reset() => state = const AuthState();

  /// Called as the user edits: the error they are actively fixing disappears,
  /// and so does the form-level banner and any recovery offer — all three
  /// describe an attempt whose inputs have since changed.
  void clearFieldError(AuthField field) {
    final hasField = state.fieldErrors.containsKey(field);
    if (!hasField &&
        state.banner == null &&
        state.notice == null &&
        state.recovery == AuthRecovery.none) {
      return;
    }
    state = state.copyWith(
      fieldErrors: hasField
          ? ({...state.fieldErrors}..remove(field))
          : state.fieldErrors,
      recovery: AuthRecovery.none,
      clearBanner: true,
      clearNotice: true,
    );
  }

  void clearFeedback() {
    if (state.banner == null &&
        state.notice == null &&
        state.recovery == AuthRecovery.none) {
      return;
    }
    state = state.copyWith(
        recovery: AuthRecovery.none, clearBanner: true, clearNotice: true);
  }

  /// Returns true when the credentials were accepted. The router reacts to
  /// the auth stream, so there is nothing to navigate here.
  Future<bool> signIn({required String email, required String password}) =>
      _run(() => _repo.signIn(email, password));

  Future<bool> signUp({required String email, required String password}) =>
      _run(() => _repo.signUp(email, password));

  Future<bool> _run(Future<void> Function() call) async {
    // Re-entrancy guard: an IME can deliver `onSubmitted` more than once, and
    // the button stays visually live while busy.
    if (state.busy) return false;
    state = state.copyWith(
      busy: true,
      fieldErrors: const {},
      recovery: AuthRecovery.none,
      clearBanner: true,
      clearNotice: true,
    );

    try {
      await call();
    } on AuthFailure catch (failure) {
      _fail(failure);
      return false;
    } catch (_) {
      _fail(const AuthFailure('Something went wrong. Please try again.'));
      return false;
    }

    // ── Past this line the account exists / the session is live. ──────────
    // Nothing below may surface as an auth error.
    _commitAutofill();
    if (ref.mounted) state = state.copyWith(busy: false);
    return true;
  }

  /// Hands the credentials to the platform password manager (§3.1).
  ///
  /// This is a platform-channel call on a session the IME may already have
  /// torn down; it fails harmlessly and must never be mistaken for a failed
  /// registration — which is exactly the bug this replaces.
  void _commitAutofill() {
    try {
      TextInput.finishAutofillContext();
    } catch (_) {
      // The credentials are saved or they aren't; either way the user is in.
    }
  }

  /// Sends a reset link and **always reports the same thing**.
  ///
  /// Deliberately does not distinguish "sent" from "no such account": doing
  /// so turns this form into an oracle for which emails are registered, which
  /// is the exact enumeration leak Firebase's own protection exists to close.
  /// The only errors surfaced are ones the user can act on — a malformed
  /// address, or the network being down.
  Future<bool> sendPasswordReset(String email) async {
    if (state.busy) return false;
    if (!AuthValidators.emailLooksValid(email)) {
      state = state.copyWith(
        fieldErrors: {AuthField.email: "That email doesn't look right"},
        clearBanner: true,
        clearNotice: true,
      );
      return false;
    }

    state = state.copyWith(
        busy: true, fieldErrors: const {}, clearBanner: true, clearNotice: true);
    try {
      await _repo.sendPasswordReset(email);
    } on AuthFailure catch (failure) {
      // 'user-not-found' is deliberately swallowed — see the doc comment.
      // Everything else (offline, rate limited, misconfigured) is real and
      // the user needs to know the mail is not coming.
      if (failure.code != 'user-not-found') {
        _fail(failure);
        return false;
      }
    } catch (_) {
      _fail(const AuthFailure('Something went wrong. Please try again.'));
      return false;
    }
    if (ref.mounted) state = state.copyWith(busy: false);
    return true;
  }

  void _fail(AuthFailure failure) {
    if (!ref.mounted) return;
    // A misconfigured build is never one field's fault — keep it in the
    // banner where it reads as a system problem, not user error.
    final field = failure.isConfigError ? null : fieldFor(failure.code);
    state = state.copyWith(
      busy: false,
      recovery: recoveryFor(failure.code),
      fieldErrors: field == null ? const {} : {field: failure.message},
      banner: field == null ? failure.message : null,
      clearBanner: field != null,
    );
  }

  /// Which wrong-door offer, if any, this failure justifies.
  static AuthRecovery recoveryFor(String? code) => switch (code) {
        'email-already-in-use' => AuthRecovery.accountExists,
        'user-not-found' => AuthRecovery.noAccount,
        _ => AuthRecovery.none,
      };

  /// Where a server error belongs. Anything not tied to one input — no
  /// connection, rate limiting, a disabled account — stays in the banner.
  static AuthField? fieldFor(String? code) => switch (code) {
        'invalid-email' => AuthField.email,
        'email-already-in-use' => AuthField.email,
        'user-not-found' => AuthField.email,
        'weak-password' => AuthField.password,
        'missing-password' => AuthField.password,
        'wrong-password' => AuthField.password,
        'invalid-credential' => AuthField.password,
        'invalid-login-credentials' => AuthField.password,
        _ => null,
      };
}
