import '../../core/constants.dart';

/// Field rules shared by rider onboarding, trainer onboarding and profile
/// editing (§9.2).
///
/// Centralised because the same field was previously validated differently
/// depending on which screen you reached it from: onboarding demanded a
/// non-empty name while Edit profile accepted whitespace, and neither
/// bounded the free-text fields at all — so a 4,000-character bio could be
/// saved and would then blow out every card that rendered it.
///
/// Every rule returns `null` when the value is acceptable and a short,
/// specific message otherwise. Messages say what to do, not what went wrong.
abstract final class OnboardingValidators {
  static const minNameLength = 2;
  static const maxNameLength = 60;
  static const maxBioLength = 240;
  static const minAge = 8;
  static const maxAge = 99;
  static const maxPhoneLength = 20;

  /// Requires at least one letter, so "..." or "12" cannot pass as a name.
  static final _hasLetter = RegExp(r'[A-Za-zÀ-ɏ؀-ۿ]');

  /// Digits, spaces and the usual dialling punctuation.
  static final _phoneShape = RegExp(r'^[0-9+()\-\s]+$');

  static String? name(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return 'Your name is required';
    if (value.length < minNameLength) return 'That looks too short';
    if (value.length > maxNameLength) {
      return 'Keep it under $maxNameLength characters';
    }
    if (!_hasLetter.hasMatch(value)) return 'Use letters, not just symbols';
    return null;
  }

  static String? age(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return 'Required';
    final age = int.tryParse(value);
    if (age == null) return 'Numbers only';
    if (age < minAge || age > maxAge) return '$minAge–$maxAge';
    return null;
  }

  /// Optional — an empty bio is fine, an essay is not.
  static String? bio(String raw) {
    final value = raw.trim();
    if (value.length > maxBioLength) {
      final over = value.length - maxBioLength;
      return '$over character${over == 1 ? '' : 's'} too long';
    }
    return null;
  }

  /// Optional. Deliberately shape-only: this app serves riders from dozens of
  /// countries, and any stricter pattern would reject somebody's real number.
  static String? phone(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    if (!_phoneShape.hasMatch(value)) {
      return 'Digits, spaces and + ( ) - only';
    }
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 6) return 'That looks too short';
    if (value.length > maxPhoneLength) return 'That looks too long';
    return null;
  }

  /// Trainer hourly rate.
  ///
  /// No platform band — trainers price themselves (§13). The bounds that
  /// remain catch a mistyped field, not a policy: zero is an unfinished form
  /// rather than a free lesson, and [FlowConst.maxSaneHourlyRate] is a
  /// slipped keypad.
  static String? rate(String raw, {int max = FlowConst.maxSaneHourlyRate}) {
    final value = raw.trim();
    if (value.isEmpty) return 'Required';
    final rate = int.tryParse(value);
    if (rate == null) return 'Numbers only';
    if (rate <= 0) return 'Set your hourly rate';
    if (rate > max) return 'That looks like a typo';
    return null;
  }

  /// Trainer years of experience — optional, but must be plausible.
  static String? years(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    final years = int.tryParse(value);
    if (years == null) return 'Numbers only';
    if (years < 0 || years > 60) return '0–60';
    return null;
  }
}
