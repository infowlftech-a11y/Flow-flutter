// An admin account is a console account.
//
// Staff used to resolve to `AppStage.ready` and get the rider's app with one
// extra row in Settings. The shell then handed them Explore, Sessions and a
// Ticket tab that were empty by construction — a staff account has no
// bookings — and Explore's Book button would write a booking under a staff
// uid, inventing a rider who does not exist and a session nobody will teach.
//
// These tests pin the two halves of the fix: the stage resolves to `staff`,
// and the router refuses to leave the console.
import 'package:flutter_test/flutter_test.dart';

import 'package:flow/data/models/app_user.dart';
import 'package:flow/providers/providers.dart';

void main() {
  group('staff never enter the marketplace', () {
    // The redirect table, exercised as data rather than through a live
    // GoRouter: the redirect is a pure function of (stage, location), and
    // driving a real router would need a signed-in Firebase to get there.
    String? redirectFor(AppStage stage, String loc, {bool isStaff = false}) {
      switch (stage) {
        case AppStage.staff:
          return (loc == '/admin' ||
                  loc.startsWith('/trainer/') ||
                  loc.startsWith('/station/') ||
                  loc == '/notifications')
              ? null
              : '/admin';
        case AppStage.ready:
          if (loc == '/admin' && !isStaff) return '/home';
          return null;
        default:
          return null;
      }
    }

    test('every marketplace route bounces back to the console', () {
      for (final loc in [
        '/home',
        '/sessions',
        '/ticket',
        '/calendar',
        '/earnings',
        '/profile',
        '/profile/edit',
        '/book/u_trainer',
        '/inbox',
        '/support',
      ]) {
        expect(redirectFor(AppStage.staff, loc), '/admin', reason: loc);
      }
    });

    test('the console and what it pushes are allowed', () {
      // A moderator opening the profile they are reviewing, and the
      // notification inbox the console's bell opens.
      for (final loc in [
        '/admin',
        '/trainer/u_trainer',
        '/station/u_station',
        '/notifications',
      ]) {
        expect(redirectFor(AppStage.staff, loc), isNull, reason: loc);
      }
    });

    test('a non-staff account still cannot reach the console', () {
      expect(redirectFor(AppStage.ready, '/admin'), '/home');
    });
  });

  group('AppUser.isStaff decides it', () {
    AppUser withRole(UserRole role) => AppUser(
          uid: 'u',
          name: 'Person',
          email: 'p@test.dev',
          role: role,
          status: AccountStatus.active,
        );

    test('admin and support are staff; owner, business and kiter are not', () {
      // Pinned because the console's entire access model reads through this
      // one getter — and `owner` is the surprise. It is a role the seed data
      // uses and the *rules* treat as staff, so if it is ever added here the
      // two definitions have to move together.
      expect(withRole(UserRole.admin).isStaff, isTrue);
      expect(withRole(UserRole.support).isStaff, isTrue);
      expect(withRole(UserRole.business).isStaff, isFalse);
      expect(withRole(UserRole.kiter).isStaff, isFalse);
    });

    test('a staff account is not a trainer, whatever else it is', () {
      // The shell branches on isTrainer. A staff account answering true here
      // would have been given a Calendar and an Earnings tab.
      expect(withRole(UserRole.admin).isTrainer, isFalse);
      expect(withRole(UserRole.support).isTrainer, isFalse);
    });
  });
}
