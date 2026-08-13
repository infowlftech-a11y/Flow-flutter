import '../../data/models/app_user.dart';

/// Where a provider's public profile lives, by role — or null for accounts
/// that have none (riders, staff).
///
/// P11 made every coach name in the app a door, which put this switch in
/// three places at once (chat header, booking card, session sheet). One
/// switch, or the day a safari operator gets a dedicated screen two of the
/// three forget.
String? providerProfilePath(AppUser u) {
  if (u.isStation || u.isSafariOperator) return '/station/${u.uid}';
  if (u.isTrainer) return '/trainer/${u.uid}';
  return null;
}
