/// Pure, testable form rules for the auth screen (blueprint §9.1).
///
/// The user-facing strings are the ones the blueprint specifies — only where
/// they appear changed (inline under the field instead of one shared banner).
library;

/// Which field an error belongs under. `null` anywhere means "not a field
/// problem" — it belongs in the form-level banner.
enum AuthField { name, email, password }

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

  static String? name(String? raw) =>
      (raw ?? '').trim().isEmpty ? 'Tell us your name' : null;

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
