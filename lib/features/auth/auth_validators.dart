/// Pure, testable form rules for the auth screen (blueprint §9.1).
///
/// The user-facing strings are the ones the blueprint specifies — only where
/// they appear changed (inline under the field instead of one shared banner).
library;

/// Which field a *server* error belongs under. `null` anywhere means "not a
/// field problem" — it belongs in the form-level banner.
///
/// There is no member for the confirmation field: matching is settled on the
/// device before anything is sent, so Firebase can never have an opinion
/// about it.
enum AuthField { email, password }

/// Deliberately pragmatic, not RFC 5322: requires a local part, a domain, and
/// at least one dot-separated label after it. The old check was
/// `contains('@') && contains('.')`, which happily accepted `"@."`.
final _emailPattern = RegExp(
  r"^[\w.!#$%&'*+/=?^`{|}~-]+"
  r'@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?'
  r'(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$',
);

abstract final class AuthValidators {
  /// Minimum Firebase accepts. Sign-up enforces it client-side so the user
  /// finds out before a round trip.
  static const minPasswordLength = 6;

  static bool emailLooksValid(String raw) =>
      _emailPattern.hasMatch(raw.trim());

  static String? email(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return 'Enter your email';
    if (!emailLooksValid(value)) return "That email doesn't look right";
    return null;
  }

  /// Log-in only checks presence — an existing account may predate any rule
  /// we enforce today, and the server is the authority on whether it matches.
  static String? password(String? raw, {required bool signUp}) {
    final value = raw ?? '';
    if (value.isEmpty) return 'Enter your password';
    if (signUp && value.length < minPasswordLength) {
      return 'Use at least $minPasswordLength characters';
    }
    return null;
  }

  /// The confirmation field on registration.
  ///
  /// Compares the raw strings — no trimming on either side. A password may
  /// legitimately begin or end with a space, and quietly trimming one of the
  /// two would either mask a real mismatch or invent one. Whatever Firebase
  /// receives is what gets compared here.
  ///
  /// Stays silent while [password] is itself invalid: telling someone their
  /// confirmation doesn't match a password that is too short is two errors for
  /// one mistake, and they'd have to fix this field again afterwards anyway.
  static String? confirmPassword(String? raw, String password) {
    final value = raw ?? '';
    if (value.isEmpty) return 'Re-enter your password';
    if (password.length < minPasswordLength) return null;
    if (value != password) return "Passwords don't match";
    return null;
  }
}

/// Sign-up password feedback. Advisory only — it never blocks submission
/// beyond the 6-character floor, it just tells the user where they stand.
enum PasswordStrength {
  weak('Weak', 0.33),
  fair('Fair', 0.66),
  strong('Strong', 1.0);

  const PasswordStrength(this.label, this.fraction);
  final String label;
  final double fraction;

  /// Length carries the most weight; variety (case, digits, symbols) breaks
  /// the tie. Under the minimum is always weak.
  static PasswordStrength of(String password) {
    if (password.length < AuthValidators.minPasswordLength) return weak;

    var variety = 0;
    if (password.contains(RegExp('[a-z]'))) variety++;
    if (password.contains(RegExp('[A-Z]'))) variety++;
    if (password.contains(RegExp('[0-9]'))) variety++;
    if (password.contains(RegExp('[^A-Za-z0-9]'))) variety++;

    if (password.length >= 12 && variety >= 3) return strong;
    if (password.length >= 10 || variety >= 3) return fair;
    return weak;
  }
}
