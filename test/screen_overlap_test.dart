// Every screen, rendered for real, checked for text painted over text.
//
// This suite exists because a user found a defect that 494 passing tests
// walked straight past: on the station profile, the TabBar painted through
// the location and STATION chips underneath it. Nothing was overflowing —
// `SliverAppBar.flexibleSpace` fills the whole app bar *including* the area
// its `bottom` occupies, so anything the flexible space positions against its
// own bottom edge is placed behind the tabs. That is a legal layout and no
// assertion in Flutter fires on it.
//
// The check runs on both themes and at 1.0x and 1.3x text, because a
// collision is usually a near-miss that only closes when something grows.
// See test/support/overlap.dart for what the detector can and cannot see.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flow/data/models/catalogue.dart';
import 'package:flow/features/admin/admin_screen.dart';
import 'package:flow/features/auth/reset_password_screen.dart';
import 'package:flow/features/auth/sign_up_screen.dart';
import 'package:flow/features/auth/welcome_screen.dart';
import 'package:flow/features/booking/booking_screen.dart';
import 'package:flow/features/chat/chat_screen.dart';
import 'package:flow/features/gates/blocked_screen.dart';
import 'package:flow/features/gates/pending_screen.dart';
import 'package:flow/features/gates/rejected_screen.dart';
import 'package:flow/features/gates/setup_required_screen.dart';
import 'package:flow/features/onboarding/kiter_form_screen.dart';
import 'package:flow/features/onboarding/role_select_screen.dart';
import 'package:flow/features/onboarding/trainer_form_screen.dart';
import 'package:flow/features/profile/edit_profile_screen.dart';
import 'package:flow/features/support/support_screen.dart';
import 'package:flow/features/chat/inbox_screen.dart';
import 'package:flow/features/command_center/calendar_screen.dart';
import 'package:flow/features/command_center/command_center_screen.dart';
import 'package:flow/features/command_center/earnings_screen.dart';
import 'package:flow/features/explore/explore_screen.dart';
import 'package:flow/features/explore/station_profile_screen.dart';
import 'package:flow/features/explore/trainer_profile_screen.dart';
import 'package:flow/features/notifications/notifications_screen.dart';
import 'package:flow/features/profile/profile_screen.dart';
import 'package:flow/features/sessions/sessions_screen.dart';
import 'package:flow/features/sessions/ticket_screen.dart';

import 'support/overlap.dart';
import 'support/screen_harness.dart';

void main() {
  /// One screen at both ends of the text-scale clamp. This ran both themes as
  /// well until dark mode was removed.
  void screenTest(
    String name,
    Widget Function() build, {
    AppUserRole role = AppUserRole.rider,
    bool populated = true,
  }) {
    for (final scale in [1.0, 1.3]) {
      final label = '$name — @${scale}x';
      testWidgets(label, (tester) async {
        final db = await seededDb(withStationDetail: populated);
        await pumpScreen(
          tester,
          build(),
          db: db,
          as: role == AppUserRole.trainer ? trainer : rider,
          textScale: scale,
        );
        expectNoTextOverlaps(tester, where: label);
      });
    }
  }

  group('station profile', () {
    // The screen the overlap was reported on.
    screenTest('station', () => const StationProfileScreen(stationId: 'u_station'));

    // Empty tabs — exactly the state in the report, where the counts read (0)
    // and nothing pushes the header taller.
    screenTest('station, nothing listed',
        () => const StationProfileScreen(stationId: 'u_station'),
        populated: false);

    // A safari operator whose name wraps to two lines: the header grows, the
    // app bar does not.
    screenTest('safari operator, long name',
        () => const StationProfileScreen(stationId: 'u_station_wide'));
  });

  group('rider screens', () {
    screenTest('trainer profile',
        () => const TrainerProfileScreen(trainerId: 'u_trainer'));
    screenTest('explore', () => const ExploreScreen());
    screenTest('sessions', () => const SessionsScreen());
    screenTest('ticket', () => const TicketScreen());
    screenTest('notifications', () => const NotificationsScreen());
    screenTest('inbox', () => const InboxScreen());
    screenTest('profile', () => const ProfileScreen());
    screenTest(
      'booking',
      () => const BookingScreen(
        target: BookingTarget(
          providerId: 'u_trainer',
          title: 'Anna Bergström',
          rate: 95,
          subtitle: 'Soma Bay',
        ),
      ),
    );
  });

  group('trainer screens', () {
    screenTest('command center', () => const CommandCenterScreen(),
        role: AppUserRole.trainer);
    screenTest('calendar', () => const CalendarScreen(),
        role: AppUserRole.trainer);
    screenTest('earnings', () => const EarningsScreen(),
        role: AppUserRole.trainer);
    screenTest('admin console', () => const AdminScreen(),
        role: AppUserRole.trainer);
  });

  // The correction form a declined trainer reaches from the rejected gate.
  // Same four steps as the application, prefilled — and every field is one
  // character longer than it was, because it arrives with real content in it
  // rather than a placeholder.
  group('re-application', () {
    screenTest('trainer form, prefilled',
        () => const TrainerFormScreen(reapply: true));
  });

  group('conversations', () {
    screenTest('support', () => const SupportScreen());
    screenTest(
      'chat',
      () => const ChatScreen(
        partnerId: 'u_trainer',
        partnerName: 'Anna Bergström',
      ),
    );
  });

  // The screens a user meets before they are anybody — and the ones they meet
  // when something has gone wrong. All four render long explanatory copy in a
  // narrow column, which is where wrapping turns into collision.
  group('gates and onboarding', () {
    screenTest('welcome', () => const WelcomeScreen());
    screenTest('sign up', () => const SignUpScreen());
    screenTest('reset password', () => const ResetPasswordScreen());
    screenTest('role select', () => const RoleSelectScreen());
    screenTest('rider form', () => const KiterFormScreen());
    screenTest('trainer form', () => const TrainerFormScreen());
    screenTest('awaiting approval', () => const PendingScreen());
    screenTest('rejected', () => const RejectedScreen());
    screenTest('blocked', () => const BlockedScreen());
    screenTest('setup required', () => const SetupRequiredScreen());
    screenTest('edit profile', () => const EditProfileScreen());
  });

  // A 320px phone is the narrowest this app claims to support, and it is
  // where every "it fits on mine" layout stops fitting. Only the densest
  // screens are worth the extra passes.
  group('at 320px', () {
    for (final entry in <String, Widget Function()>{
      'station': () => const StationProfileScreen(stationId: 'u_station'),
      'trainer profile': () =>
          const TrainerProfileScreen(trainerId: 'u_trainer'),
      'sessions': () => const SessionsScreen(),
      'explore': () => const ExploreScreen(),
      'command center': () => const CommandCenterScreen(),
    }.entries) {
      testWidgets('${entry.key} — 320px @1.3x', (tester) async {
        final db = await seededDb();
        await pumpScreen(
          tester,
          entry.value(),
          db: db,
          as: entry.key == 'command center' ? trainer : rider,
          size: const Size(320, 640),
          textScale: 1.3,
        );
        expectNoTextOverlaps(tester, where: '${entry.key} @320px');
      });
    }
  });
}

enum AppUserRole { rider, trainer }

