// The gate, as a truth table.
//
// `gateRedirect` decides, per session stage, which paths a user may be on and
// where they bounce otherwise. It is the whole of the app's route-level
// authorization — a wrong `null` here exposes a screen a stage is meant to
// withhold, and a wrong bounce locks a user out of a lifeline. Neither shows
// up as an exception; both are silent. So every stage gets its allow-list and
// at least one denial pinned here.
//
// It exists as a pure function precisely so this file can exist: the same
// decision the router runs, with no navigator, context or emulator in the way.
import 'package:flutter_test/flutter_test.dart';

import 'package:flow/providers/providers.dart';
import 'package:flow/router.dart';

// Convenience: the isTrainer flag only matters at AppStage.ready, so default
// it and override in the one group that cares.
String? at(AppStage stage, String loc, {bool isTrainer = false}) =>
    gateRedirect(stage, loc, isTrainer: isTrainer);

void main() {
  group('loading holds everything on the splash', () {
    test('/ is allowed', () => expect(at(AppStage.loading, '/'), isNull));
    test('anything else bounces to /', () {
      expect(at(AppStage.loading, '/home'), '/');
      expect(at(AppStage.loading, '/auth'), '/');
    });
  });

  group('signedOut owns the whole /auth subtree', () {
    test('the front door and its three children are allowed', () {
      expect(at(AppStage.signedOut, '/auth'), isNull);
      expect(at(AppStage.signedOut, '/auth/sign-in'), isNull);
      expect(at(AppStage.signedOut, '/auth/sign-up'), isNull);
      expect(at(AppStage.signedOut, '/auth/reset'), isNull);
    });
    test('anything else bounces to /auth', () {
      expect(at(AppStage.signedOut, '/home'), '/auth');
      expect(at(AppStage.signedOut, '/support'), '/auth');
    });
  });

  group('chooseRole is pinned to onboarding', () {
    test('the onboarding subtree is allowed', () {
      expect(at(AppStage.chooseRole, '/onboarding/role'), isNull);
      expect(at(AppStage.chooseRole, '/onboarding/rider'), isNull);
      expect(at(AppStage.chooseRole, '/onboarding/trainer'), isNull);
    });
    test('anything else bounces to role select', () {
      expect(at(AppStage.chooseRole, '/home'), '/onboarding/role');
    });
  });

  group('awaitingApproval and blocked are single-screen', () {
    test('pending', () {
      expect(at(AppStage.awaitingApproval, '/pending'), isNull);
      expect(at(AppStage.awaitingApproval, '/home'), '/pending');
      expect(at(AppStage.awaitingApproval, '/support'), '/pending');
    });
    test('blocked', () {
      expect(at(AppStage.blocked, '/blocked'), isNull);
      expect(at(AppStage.blocked, '/home'), '/blocked');
      expect(at(AppStage.blocked, '/support'), '/blocked');
    });
  });

  group('rejected keeps the lifelines open', () {
    test('the declined screen, support, and the reapply form are allowed', () {
      expect(at(AppStage.rejected, '/rejected'), isNull);
      expect(at(AppStage.rejected, '/support'), isNull);
      expect(at(AppStage.rejected, '/onboarding/trainer/reapply'), isNull);
    });

    // BUG-025 — the P12 regression. The ticket thread became its own pushed
    // route (`/support/ticket/:id`), and the exact-match allow-list bounced a
    // declined trainer off their own ticket the moment they opened it: they
    // could file a ticket and never read the reply.
    test('a pushed ticket thread under /support is allowed', () {
      expect(at(AppStage.rejected, '/support/ticket/abc123'), isNull);
    });

    test('everything else still bounces to /rejected', () {
      expect(at(AppStage.rejected, '/home'), '/rejected');
      expect(at(AppStage.rejected, '/admin'), '/rejected');
      expect(at(AppStage.rejected, '/trainer/x'), '/rejected');
      // Not fooled by a lookalike prefix that is not the support subtree.
      expect(at(AppStage.rejected, '/supportish'), '/rejected');
    });
  });

  group('staff live in the console and the screens it pushes', () {
    test('the console and what it opens are allowed', () {
      expect(at(AppStage.staff, '/admin'), isNull);
      expect(at(AppStage.staff, '/trainer/uid1'), isNull);
      expect(at(AppStage.staff, '/station/uid2'), isNull);
      expect(at(AppStage.staff, '/notifications'), isNull);
    });
    test('the rider app is off-limits — bounced to the console', () {
      expect(at(AppStage.staff, '/home'), '/admin');
      expect(at(AppStage.staff, '/sessions'), '/admin');
      expect(at(AppStage.staff, '/book/x'), '/admin');
    });
  });

  group('ready is the full app, with two exclusions', () {
    test('a normal screen is allowed', () {
      expect(at(AppStage.ready, '/home'), isNull);
      expect(at(AppStage.ready, '/support'), isNull);
      expect(at(AppStage.ready, '/support/ticket/abc'), isNull);
      expect(at(AppStage.ready, '/trainer/x'), isNull);
    });
    test('pre-auth and gate screens send a ready user home', () {
      for (final loc in [
        '/', '/auth', '/auth/sign-in', '/pending', '/blocked', '/rejected',
        '/onboarding/role',
      ]) {
        expect(at(AppStage.ready, loc), '/home', reason: loc);
      }
    });
    test('the console is closed to non-staff', () {
      expect(at(AppStage.ready, '/admin'), '/home');
    });
    test('a trainer is kept out of the Sessions branch, a rider is not', () {
      expect(at(AppStage.ready, '/sessions', isTrainer: true), '/home');
      expect(at(AppStage.ready, '/sessions', isTrainer: false), isNull);
    });
  });
}
