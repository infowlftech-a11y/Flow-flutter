// P10: a ref printed in the console is a door, not a string to copy.
//
// The chain under test is the support call as staff actually work it:
// ticket → the booking it is about → the rider on that booking → their
// recent sessions. Before P10 every arrow in that chain was a manual
// copy-paste into another tab's search box.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flow/core/utils/refs.dart';
import 'package:flow/data/firestore_paths.dart';
import 'package:flow/data/models/app_user.dart';
import 'package:flow/features/admin/admin_screen.dart';

import 'support/screen_harness.dart';

const _staff = AppUser(
  uid: 'u_admin',
  name: 'Nadia Fouad',
  email: 'nadia@flow.app',
  role: UserRole.admin,
  status: AccountStatus.active,
);

Future<FakeFirebaseFirestore> _db() async {
  final db = await seededDb();
  await db.collection(Col.users).doc(_staff.uid).set({
    'name': _staff.name,
    'email': _staff.email,
    'role': 'admin',
    'status': 'active',
  });
  await db.collection(Col.bookings).doc('bx1').set({
    'date': '2099-08-29',
    'status': 'confirmed',
    'instructorId': 'u_trainer',
    'instructorName': 'Anna Bergström',
    'kiterId': rider.uid,
    'studentName': rider.name,
    'startTime': '10:00',
    'endTime': '12:00',
    'totalPrice': 190,
  });
  await db.collection(Col.tickets).doc('t9').set({
    'userId': rider.uid,
    'userName': rider.name,
    'subject': 'Trainer never showed up',
    'status': 'open',
    'topic': 'Booking problem',
    'sessionId': 'bx1',
    'sessionRef': sessionRef('bx1', '2099-08-29'),
  });
  return db;
}

Future<void> _pumps(WidgetTester tester, [int n = 6]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

void main() {
  testWidgets('ticket ref → booking → rider → their sessions', (tester) async {
    // Tall like ticket_topic_test: sheets stack and lazy lists below the
    // fold have no elements to tap on a phone height. Geometry belongs to
    // the layout test and the captures; this pins the wiring.
    await pumpScreen(
      tester,
      const AdminScreen(),
      db: await _db(),
      as: _staff,
      size: const Size(500, 1600),
    );
    await _pumps(tester);

    await tester.ensureVisible(find.textContaining('Tickets'));
    await tester.tap(find.textContaining('Tickets'));
    await _pumps(tester);

    // The card shows both doors: the opener's member ref and the session.
    final ref = sessionRef('bx1', '2099-08-29');
    expect(find.text(ref), findsOneWidget);
    expect(find.text(memberRef(rider.uid, coach: false)), findsOneWidget);

    await tester.tap(find.text(ref));
    await _pumps(tester);
    expect(
      find.text('SESSION ID'),
      findsOneWidget,
      reason: 'the session ref must open the booking sheet in place',
    );

    await tester.tap(find.text('VIEW RIDER'));
    await _pumps(tester);
    expect(
      find.text('RECENT SESSIONS'),
      findsOneWidget,
      reason:
          'the booking names its rider, and the rider names their '
          'sessions — the loop closes without a search box',
    );
  });
}
