// The staff console, rendered as staff, with something in every queue.
//
// screen_overlap_test.dart has an "admin console" case, and it has never
// seen the console. It pumps `AdminScreen` as a trainer, and the first thing
// that screen does is check `sessionProvider.isStaff` and return a "Staff
// only" gate — so the assertion has always run against an icon, a sentence
// and a Go back button. Six tabs of dense staff UI went in with no layout
// coverage at all, which is how the applicant card came to print
// `IKO IKO-4471PQ` on every row without a test noticing.
//
// This file is separate rather than a fix to that case so the existing suite
// stays untouched. The overlap detector's limits are documented in
// test/support/overlap.dart; what it can prove is that no text is painted
// over other text, at both ends of the text-scale clamp and on the narrowest
// phone the app claims to support.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flow/data/firestore_paths.dart';
import 'package:flow/data/models/app_user.dart';
import 'package:flow/features/admin/admin_screen.dart';

import 'support/overlap.dart';
import 'support/screen_harness.dart';

/// A real staff account. `AdminScreen` gates on `isStaff`, which is role
/// `admin` or `support` — a `business` account is not staff, whatever else
/// it can do.
const staff = AppUser(
  uid: 'u_admin',
  name: 'Nadia Fouad',
  email: 'nadia@flow.app',
  role: UserRole.admin,
  status: AccountStatus.active,
);

/// The seed plus one item in each of the six queues, because an empty tab is
/// the easy case: nothing to collide with.
Future<FakeFirebaseFirestore> staffDb() async {
  final db = await seededDb();

  await db.collection(Col.users).doc(staff.uid).set({
    'name': staff.name,
    'email': staff.email,
    'role': 'admin',
    'status': 'active',
  });

  // An applicant with everything filled in — the long name, the long bio and
  // the credential are what push this card.
  await db.collection(Col.users).doc('u_applicant').set({
    'name': 'Mostafa El-Sharkawy',
    'email': 'mostafa.elsharkawy@example.com',
    'role': 'business',
    'status': 'pending',
    'location': 'Ras Sudr',
    'bio': 'IKO Level 2. Teaching since 2019, mostly beginners and freestyle.',
    'ikoId': 'IKO-4471PQ',
    'hourlyRate': 55,
    'languages': ['Arabic', 'English', 'German'],
  });

  await db.collection(Col.users).doc('u_suspended').set({
    'name': 'Karim Adel',
    'email': 'karim@example.com',
    'role': 'kiter',
    'status': 'blocked',
    'blockedUntil': '2099-09-01',
    'statusBeforeBlock': 'active',
  });

  await db.collection(Col.reports).doc('rp1').set({
    'reporterId': rider.uid,
    'reporterName': rider.name,
    'reportedUserId': 'u_suspended',
    'reportedUserName': 'Karim Adel',
    'reason': 'Unsafe behaviour on the water',
    'details': 'Rode straight through the beginner zone twice in one session.',
    'status': 'pending',
  });

  await db.collection(Col.appeals).doc('ap1').set({
    'userId': 'u_suspended',
    'userName': 'Karim Adel',
    'reason': 'I was outside the marked zone and happy to explain.',
    'status': 'pending',
    'messages': <Map<String, dynamic>>[],
  });

  await db.collection(Col.tickets).doc('t1').set({
    'userId': rider.uid,
    'userName': rider.name,
    'subject': 'Refund for a cancelled session',
    'status': 'open',
  });

  await db.collection(Col.leaveReasons).doc('l1').set({
    'userId': 'u_gone',
    'userName': 'Former Rider',
    'userEmail': 'gone@example.com',
    'reason': 'Moving away from the coast — thanks for everything.',
  });

  return db;
}

/// Tab label prefix → a string only that tab's content can produce.
///
/// The marker is not decoration. A tap that misses, or a tab that never
/// builds, would leave APPROVALS on screen and every case below would pass
/// while testing the same tab six times — which is the exact way the case in
/// screen_overlap_test.dart has been passing.
const _tabs = <String, String>{
  'Approvals': 'Mostafa El-Sharkawy',
  'Tickets': 'Refund for a cancelled session',
  'Reports': 'Unsafe behaviour on the water',
  'Appeals': 'I was outside the marked zone and happy to explain.',
  'Suspended': 'Karim Adel',
  'Feedback': 'Moving away from the coast — thanks for everything.',
  // The directory and sessions views are proved open by their search hints —
  // the only strings on those tabs that no seeded data could also produce.
  // P3 (ordered) taught the directory search the member IDs, and the hint
  // says so — this string tracks it.
  'Users': 'Search name, email or ID…',
  'Sessions': 'Search rider or trainer…',
};

void main() {
  group('the console renders for staff at all', () {
    testWidgets('a staff account gets the console, not the gate', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const AdminScreen(),
        db: await staffDb(),
        as: staff,
      );

      expect(find.text('Admin console'), findsOneWidget);
      expect(
        find.text('Staff only'),
        findsNothing,
        reason: 'if this fails the rest of the file proves nothing',
      );
    });

    testWidgets('a trainer gets the gate', (tester) async {
      // Pinned because it is the state screen_overlap_test.dart has been
      // testing by accident, and it should stay a deliberate choice.
      await pumpScreen(
        tester,
        const AdminScreen(),
        db: await staffDb(),
        as: trainer,
      );

      expect(find.text('Staff only'), findsOneWidget);
    });
  });

  group('no text collides in any tab', () {
    for (final scale in [1.0, 1.3]) {
      for (final entry in _tabs.entries) {
        testWidgets('${entry.key} — @${scale}x', (tester) async {
          await pumpScreen(
            tester,
            const AdminScreen(),
            db: await staffDb(),
            as: staff,
            textScale: scale,
          );

          await _openTab(tester, entry.key, marker: entry.value);
          expectNoTextOverlaps(tester, where: '${entry.key} @${scale}x');
        });
      }
    }
  });

  group('system back asks to sign out instead of exiting', () {
    // The console is the staff root: there is nothing under it to pop to, so
    // the system back gesture used to fall through and close the app cold.
    // The PopScope catches it and offers the same sign-out the app bar does.
    testWidgets('back at the console opens the sign-out confirm', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const AdminScreen(),
        db: await staffDb(),
        as: staff,
      );

      final handled = await tester.binding.handlePopRoute();
      expect(
        handled,
        isTrue,
        reason:
            'the pop fell through to the system — that is the app '
            'closing on the back gesture',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Sign out?'), findsOneWidget);
      // Declining must be possible — back must never be a forced sign-out.
      expect(find.text('Stay'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
    });
  });

  group('the ticket thread sheet survives the keyboard', () {
    // The bug this pins: showFlowSheet already pads the sheet by the
    // keyboard inset, and the ticket sheet's builder added the same inset
    // again. With the keyboard up that was ~2x the keyboard in blank
    // padding — the thread, the reply field and the buttons were squeezed
    // out of the sheet entirely, and the reporter's description was
    // "everything turns white and disappears".
    testWidgets('the reply field stays visible above the keyboard', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const AdminScreen(),
        db: await staffDb(),
        as: staff,
      );
      await _openTab(tester, 'Tickets', marker: _tabs['Tickets']!);

      await tester.tap(
        find.textContaining('Refund for a cancelled session').first,
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
      expect(
        find.byType(TextField),
        findsOneWidget,
        reason: 'the thread sheet did not open',
      );

      // Keyboard up: 300 logical px of viewInsets at DPR 1.0.
      tester.view.viewInsets = const FakeViewPadding(
        left: 0,
        top: 0,
        right: 0,
        bottom: 300,
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }

      // The field and the send button sit above the keyboard. With the
      // double inset the field's rect ended up beyond the keyboard edge;
      // the RenderFlex overflow the squeeze causes would fail the test on
      // its own as well.
      final field = tester.getRect(find.byType(TextField));
      expect(
        field.bottom,
        lessThanOrEqualTo(780 - 300 + 0.1),
        reason: 'the reply field is under the keyboard',
      );
      expect(find.text('Send reply'), findsOneWidget);
      expect(
        find.text('Close ticket'),
        findsOneWidget,
        reason: 'the close action names what it closes',
      );
    });
  });

  group('at 320px', () {
    // The narrowest supported phone at the largest text — where the
    // applicant card's two button rows and the pill wrap have least room.
    // USERS joins the list because its cards stack two pills against a
    // name+email column, which is the same shape that broke elsewhere.
    for (final tab in ['Approvals', 'Reports', 'Suspended', 'Users']) {
      testWidgets('$tab — 320px @1.3x', (tester) async {
        await pumpScreen(
          tester,
          const AdminScreen(),
          db: await staffDb(),
          as: staff,
          size: const Size(320, 640),
          textScale: 1.3,
        );

        await _openTab(tester, tab, marker: _tabs[tab]!);
        expectNoTextOverlaps(tester, where: '$tab @320px');
      });
    }
  });
}

/// Taps the tab whose label starts with [prefix], then proves it opened by
/// finding [marker] — a string only that tab's content can produce.
///
/// `pumpAndSettle` is never used in this harness — the skeletons animate
/// forever, so it hangs rather than fails.
Future<void> _openTab(
  WidgetTester tester,
  String prefix, {
  required String marker,
}) async {
  final tab = find.byWidgetPredicate(
    (w) => w is Text && (w.data ?? '').startsWith(prefix),
  );
  expect(tab, findsWidgets, reason: 'no tab labelled $prefix');

  // The TabBar scrolls: a tab past the right edge cannot be tapped until it
  // is dragged into view, and tapping off-screen warns instead of failing.
  await tester.ensureVisible(tab.first);
  await tester.pump();
  await tester.tap(tab.first, warnIfMissed: false);
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }

  expect(
    find.textContaining(marker, findRichText: true),
    findsWidgets,
    reason:
        '$prefix did not open — every assertion after this would have '
        'run against whichever tab was already showing',
  );
}
