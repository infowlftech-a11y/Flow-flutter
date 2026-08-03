import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/auth_repository.dart';
import '../../providers/providers.dart';
import 'auth_validators.dart';

enum AuthMode { logIn, signUp }

/// Everything the auth form needs to render, in one immutable value.
///
/// Errors are split by destination: [fieldErrors] render inline under the
/// field that caused them, [banner] is for problems that belong to the whole
/// form (no connection, rate limited, service down).
class AuthState {
  const AuthState({
    this.mode = AuthMode.logIn,
    this.busy = false,
    this.banner,
    this.fieldErrors = const {},
    this.notice,
  });

  final AuthMode mode;
  final bool busy;
  final String? banner;
  final Map<AuthField, String> fieldErrors;

  /// Transient success message (e.g. "reset link sent").
  final String? notice;

  bool get isSignUp => mode == AuthMode.signUp;
  bool get hasErrors => banner != null || fieldErrors.isNotEmpty;

  AuthState copyWith({
    AuthMode? mode,
    bool? busy,
    String? banner,
    Map<AuthField, String>? fieldErrors,
    String? notice,
    bool clearBanner = false,
    bool clearNotice = false,
  }) =>
      AuthState(
        mode: mode ?? this.mode,
        busy: busy ?? this.busy,
        banner: clearBanner ? null : (banner ?? this.banner),
        fieldErrors: fieldErrors ?? this.fieldErrors,
        notice: clearNotice ? null : (notice ?? this.notice),
      );
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);

/// Owns the submit lifecycle so the widget only renders.
///
/// The contract that fixes the original bug: **a successful credential call
/// can never be reported as a failure.** The network call sits alone in its
/// own try; every post-success side effect (autofill commit, haptics) runs
/// afterwards behind its own guard and can only ever be swallowed.
class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthState();

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  void setMode(AuthMode mode) {
    if (mode == state.mode) return;
    // Switching modes clears stale errors — a login failure shouldn't sit
    // under a registration form.
    state = AuthState(mode: mode);
  }

  /// Called as the user edits: the error they are actively fixing disappears,
  /// and so does the form-level banner — a rejection from the previous
  /// attempt shouldn't linger over inputs that have since changed.
  void clearFieldError(AuthField field) {
    final hasField = state.fieldErrors.containsKey(field);
    if (!hasField && state.banner == null && state.notice == null) return;
    state = state.copyWith(
      fieldErrors: hasField
          ? ({...state.fieldErrors}..remove(field))
          : state.fieldErrors,
      clearBanner: true,
      clearNotice: true,
    );
  }

  void clearFeedback() {
    if (state.banner == null && state.notice == null) return;
    state = state.copyWith(clearBanner: true, clearNotice: true);
  }

  /// Returns true when the credentials were accepted. The router reacts to
  /// the auth stream, so there is nothing to navigate here.
  Future<bool> submit({
    required String name,
    required String email,
    required String password,
  }) async {
    // Re-entrancy guard: an IME can deliver `onSubmitted` more than once, and
    // the button stays visually live while busy.
    if (state.busy) return false;
    state = state.copyWith(
        busy: true, fieldErrors: const {}, clearBanner: true, clearNotice: true);

    try {
      if (state.isSignUp) {
        await _repo.signUp(name, email, password);
      } else {
        await _repo.signIn(email, password);
      }
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

  Future<bool> sendPasswordReset(String email) async {
    if (state.busy) return false;
    if (!AuthValidators.emailLooksValid(email)) {
      state = state.copyWith(
        fieldErrors: {AuthField.email: 'Enter your email first, then tap reset.'},
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
      _fail(failure);
      return false;
    } catch (_) {
      _fail(const AuthFailure('Something went wrong. Please try again.'));
      return false;
    }
    if (ref.mounted) {
      state = state.copyWith(
          busy: false, notice: 'Reset link sent to ${email.trim()}');
    }
    return true;
  }

  void _fail(AuthFailure failure) {
    if (!ref.mounted) return;
    // A misconfigured build is never one field's fault — keep it in the
    // banner where it reads as a system problem, not user error.
    final field = failure.isConfigError ? null : fieldFor(failure.code);
    state = state.copyWith(
      busy: false,
      fieldErrors: field == null ? const {} : {field: failure.message},
      banner: field == null ? failure.message : null,
      clearBanner: field != null,
    );
  }

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
