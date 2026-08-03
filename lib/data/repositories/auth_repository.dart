import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// An auth error that already carries a human-readable message (§10.3).
///
/// [code] is the raw underlying code, kept so the UI layer can decide *where*
/// the message belongs (under a specific field vs. the form banner) without
/// the repository needing to know anything about the form.
///
/// [isConfigError] marks failures that no user action can fix — an invalid
/// API key, a disabled sign-in provider, an unregistered app. These are build
/// problems wearing a runtime costume, and telling the user to "try again"
/// is a lie.
class AuthFailure implements Exception {
  const AuthFailure(this.message, {this.code, this.isConfigError = false});

  final String message;
  final String? code;
  final bool isConfigError;

  @override
  String toString() => message;
}

class AuthRepository {
  AuthRepository(this._auth);
  final FirebaseAuth _auth;

  Stream<User?> authState() => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  Future<void> signIn(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(
          email: email.trim(), password: password);
    } catch (error) {
      throw translate(error);
    }
  }

  /// Sign-up sets the Firebase displayName from the name field.
  ///
  /// Silent fallback (§3.1): an already-registered email attempts a sign-in
  /// with the same credentials instead of erroring — someone re-registering
  /// with their real password just gets logged in. If the password does *not*
  /// match, the fallback's "incorrect email or password" would be baffling
  /// mid-registration, so it is re-thrown with wording that fits the flow.
  Future<void> signUp(String name, String email, String password) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
          email: email.trim(), password: password);
      await cred.user?.updateDisplayName(name.trim());
    } catch (error) {
      final failure = translate(error);
      if (failure.code == 'email-already-in-use') {
        try {
          await signIn(email, password);
          return;
        } on AuthFailure catch (signInFailure) {
          if (_isCredentialMismatch(signInFailure.code)) {
            throw const AuthFailure(
              'An account with this email already exists. '
              'Log in instead, or use "Forgot password?" to reset it.',
              code: 'email-already-in-use',
            );
          }
          rethrow;
        }
      }
      throw failure;
    }
  }

  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } catch (error) {
      throw translate(error);
    }
  }

  Future<void> signOut() => _auth.signOut();

  /// Deletes the auth user. The caller deletes the Firestore profile first.
  Future<void> deleteAccount() async {
    try {
      await _auth.currentUser?.delete();
    } catch (error) {
      throw translate(error);
    }
  }

  static bool _isCredentialMismatch(String? code) =>
      code == 'wrong-password' ||
      code == 'invalid-credential' ||
      code == 'user-not-found';

  /// Turns anything thrown by the Firebase SDK into an [AuthFailure].
  ///
  /// Catching only `FirebaseAuthException` was the flaw that let an invalid
  /// API key reach the UI as an untranslated exception: config problems
  /// surface as plain `FirebaseException`s or raw `PlatformException`s from
  /// the platform channel, depending on where they are detected. Everything
  /// funnels through here so no error can reach a user unlabelled.
  @visibleForTesting
  static AuthFailure translate(Object error) {
    if (error is AuthFailure) return error;

    final String? code;
    final String? detail;
    if (error is FirebaseAuthException) {
      code = error.code;
      detail = error.message;
    } else if (error is FirebaseException) {
      code = error.code;
      detail = error.message;
    } else if (error is PlatformException) {
      code = error.code;
      detail = error.message;
    } else {
      code = null;
      detail = error.toString();
    }

    final normalized = _normalize(code, detail);
    if (_configCodes.contains(normalized)) {
      return AuthFailure(message(normalized),
          code: normalized, isConfigError: true);
    }
    return AuthFailure(message(normalized, rawDetail: detail),
        code: normalized);
  }

  /// Firebase reports the same underlying problem under several spellings
  /// across platforms — Android mangles the server message into the code
  /// field verbatim, punctuation and all.
  static String _normalize(String? code, String? detail) {
    final raw = (code ?? '').toLowerCase();
    final text = '$raw ${(detail ?? '').toLowerCase()}';

    if (text.contains('api key not valid') ||
        text.contains('api_key_invalid') ||
        raw.startsWith('api-key-not-valid') ||
        raw == 'invalid-api-key') {
      return 'invalid-api-key';
    }
    if (text.contains('configuration_not_found') ||
        raw == 'configuration-not-found') {
      return 'configuration-not-found';
    }
    if (raw == 'app-not-authorized') return 'app-not-authorized';
    return raw.isEmpty ? 'unknown' : raw;
  }

  /// Failures that mean "this build is misconfigured", not "try again".
  static const _configCodes = {
    'invalid-api-key',
    'configuration-not-found',
    'app-not-authorized',
    'operation-not-allowed',
  };

  static bool isConfigCode(String? code) => _configCodes.contains(code);

  /// Auth error code → human words (§10.3).
  ///
  /// [rawDetail] is appended in debug builds when a code is unrecognised, so
  /// the next unmapped error is diagnosable in seconds instead of hiding
  /// behind the generic fallback — which is precisely how an invalid API key
  /// masqueraded as a transient server error.
  static String message(String code, {String? rawDetail}) {
    final known = switch (code) {
      'user-not-found' ||
      'wrong-password' ||
      'invalid-credential' =>
        'Incorrect email or password.',
      'invalid-email' => "That email address doesn't look right.",
      'email-already-in-use' => 'An account with this email already exists.',
      'weak-password' => 'Password should be at least 6 characters.',
      'user-disabled' => 'This account has been disabled.',
      'too-many-requests' =>
        'Too many attempts. Please wait a moment and try again.',
      'network-request-failed' =>
        'No connection. Check your internet and try again.',
      'requires-recent-login' =>
        'For your security, sign out and sign back in before deleting your account.',
      'missing-password' => 'Enter your password.',
      'invalid-login-credentials' => 'Incorrect email or password.',
      'account-exists-with-different-credential' =>
        'This email is already registered with a different sign-in method.',
      'expired-action-code' || 'invalid-action-code' =>
        'That link has expired. Request a new one.',
      'internal-error' =>
        "Our sign-in service hiccuped. Please try again in a moment.",
      // ── Configuration, not user error. Say so plainly. ─────────────────
      'invalid-api-key' =>
        "Sign-in isn't available because this build is missing its Firebase "
            'API key. This is a configuration problem, not something you did.',
      'configuration-not-found' =>
        "Sign-in isn't configured for this app yet. Email/password sign-in "
            'needs to be enabled in the Firebase console.',
      'app-not-authorized' =>
        "This build isn't authorised to reach the FLOW backend. Its signing "
            'certificate needs registering in the Firebase console.',
      'operation-not-allowed' =>
        'Email sign-in is currently disabled for this app. Please contact support.',
      _ => null,
    };
    if (known != null) return known;

    const generic = 'Something went wrong. Please try again.';
    if (kDebugMode && (rawDetail ?? '').isNotEmpty) {
      return '$generic\n[debug] $code: $rawDetail';
    }
    return generic;
  }
}
