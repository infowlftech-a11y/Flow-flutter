// FLOW 4 — the rider shows a QR ticket, the trainer scans it, the session runs.
//
// booking_repository_test.dart already has the stale-ticket matrix: which
// statuses bounce, whose ticket it is, wrong day. What it does not cover is
// the flow around it.
//
// The credential is produced in one file and validated in another:
//
//   produce   TicketScreen.payloadFor        (lib/features/sessions/)
//   validate  _QrScannerScreenState._onDetect (lib/features/command_center/)
//
// Nothing connected them. `payloadFor`'s own comment says the payload is
// "unchanged" from §12.2 — which is exactly the kind of agreement that holds
// until someone renames a key on one side, and then check-in stops working
// with no test going red. The first group below is that connection.
//
// The scanner's own parsing is a private method inside a widget that builds a
// live camera, so it is exercised here through its *contract* rather than
// directly; the gap is recorded in COVERAGE.md rather than papered over.
import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flow/core/utils/date_x.dart';
import 'package:flow/data/firestore_paths.dart';
import 'package:flow/data/models/booking.dart';
import 'package:flow/data/models/catalogue.dart';
import 'package:flow/data/repositories/booking_repository.dart';
import 'package:flow/data/repositories/notification_repository.dart';
import 'package:flow/features/sessions/ticket_screen.dart';

void main() {
  late FakeFirebaseFirestore db;
  late BookingRepository repo;
  late NotificationRepository notifications;

  setUp(() {
    db = FakeFirebaseFirestore();
    notifications = NotificationRepository(db);
    repo = BookingRepository(db, notifications);
  });

  const trainer = 'trainer1';
  const rider = 'rider1';

  // Check-in only ever runs on *today's* booking, which puts these tests in
  // direct conflict with the same-day lead time (§8.2): createBooking refuses
  // any hour at or before now.hour + 1, so a fixture built through it passes
  // in the morning and fails after lunch. The rest of the suite dodges this
  // by booking in 2099; check-in cannot.
  //
  // So the fixture writes the booking document directly, in the shape
  // createBooking produces. Lead time is §8.2's business and is tested there;
  // depending on it here would only buy a clock-dependent suite.
  final today = todayYmd();
  var seq = 0;

  Future<String> seedBooking({
    BookingStatus status = BookingStatus.confirmed,
    String hour = '10:00',
    String date = '',
    String instructorId = trainer,
  }) async {
    final id = 'b${seq++}';
    final start = Slot.tryParse(hour)!;
    await db.collection(Col.bookings).doc(id).set({
      'id': id,
      'instructorId': instructorId,
      'instructorName': 'Anna',
      'kiterId': rider,
      'studentName': 'Seif',
      'studentLevel': 'Independent',
      'listingTitle': 'Anna',
      'date': date.isEmpty ? today : date,
      'startTime': start.value,
      'endTime': start.plusHours(1).value,
      'selectedTimes': [start.value],
      'durationHours': 1,
      'totalPrice': 50,
      'type': 'lesson',
      'status': status.wire,
    });
    return id;
  }

  Future<Booking> booking(String id) async =>
      (await repo.watchRiderBookings(rider).first).firstWhere((b) => b.id == id);

  Future<String> confirmed({String hour = '10:00'}) =>
      seedBooking(hour: hour);

  group('the ticket the rider shows is the one the scanner accepts', () {
    // Mirrors _onDetect's three conditions exactly. If the producing side
    // ever drifts, this fails here rather than on a beach.
    test('payloadFor decodes to a map', () async {
      final id = await seedBooking(hour: '15:00', status: BookingStatus.pending);
      final decoded = jsonDecode(TicketScreen.payloadFor(await booking(id)));

      expect(decoded, isA<Map<String, dynamic>>(),
          reason: 'the scanner rejects anything that is not a JSON object');
    });

    test('it carries bookingId and trainerId, both as strings', () async {
      final id = await seedBooking(hour: '15:00', status: BookingStatus.pending);
      final p = jsonDecode(TicketScreen.payloadFor(await booking(id)))
          as Map<String, dynamic>;

      expect(p['bookingId'], isA<String>());
      expect(p['trainerId'], isA<String>());
    });

    test('the ids are the booking and its trainer, not something else',
        () async {
      final id = await seedBooking(hour: '15:00', status: BookingStatus.pending);
      final p = jsonDecode(TicketScreen.payloadFor(await booking(id)))
          as Map<String, dynamic>;

      expect(p['bookingId'], id);
      expect(p['trainerId'], trainer,
          reason: 'the scanner compares this against its own uid to reject '
              "another trainer's ticket before any state is read");
    });

    test('it carries nothing else — no rider name, no price', () async {
      final id = await seedBooking(hour: '15:00', status: BookingStatus.pending);
      final p = jsonDecode(TicketScreen.payloadFor(await booking(id)))
          as Map<String, dynamic>;

      expect(p.keys.toSet(), {'bookingId', 'trainerId'},
          reason: 'a QR shown on a beach should not carry more than the '
              'lookup needs');
    });

    test('a booking with no id still produces parseable JSON', () async {
      // EMPTY. Better an empty lookup that bounces than a crash on the
      // ticket screen.
      final b = Booking.fromDoc('', {'instructorId': trainer, 'date': today});
      final p = jsonDecode(TicketScreen.payloadFor(b)) as Map<String, dynamic>;

      expect(p['bookingId'], '');
      expect(p['trainerId'], trainer);
    });
  });

  group('the scan runs the session, and both sides see it', () {
    test('confirmed today -> in progress on both lists', () async {
      final id = await confirmed(hour: '15:00');
      await repo.checkIn(id, trainerId: trainer);

      expect((await booking(id)).status, BookingStatus.inProgress,
          reason: "rider's ticket flips to started (§10.10)");
      final t = (await repo.watchTrainerBookings(trainer).first)
          .firstWhere((b) => b.id == id);
      expect(t.status, BookingStatus.inProgress);
    });

    test('it records the check-in, not just the status (§6.3)', () async {
      final id = await confirmed(hour: '15:00');
      await repo.checkIn(id, trainerId: trainer);

      final doc = (await db.collection(Col.bookings).doc(id).get()).data()!;
      expect(doc['checkedIn'], isTrue);
      expect(doc['startedAt'], isNotNull);
    });

    test('the running session moves to the active bucket (§8.7)', () async {
      final id = await confirmed(hour: '15:00');
      await repo.checkIn(id, trainerId: trainer);

      expect((await booking(id)).bucket(), BookingBucket.active);
      expect((await booking(id)).subLabel, 'In progress');
    });

    test('scanning the same ticket twice bounces the second time', () async {
      // IDEMPOTENCY. The scanner suppresses duplicate reads, but a second
      // scan after the banner clears must not restart a running session.
      final id = await confirmed(hour: '15:00');
      await repo.checkIn(id, trainerId: trainer);

      await expectLater(
        repo.checkIn(id, trainerId: trainer),
        throwsA(isA<CheckInFailure>().having(
            (e) => e.message, 'message', contains('already running'))),
      );
    });

    test('a second scan does not move startedAt', () async {
      final id = await confirmed(hour: '15:00');
      await repo.checkIn(id, trainerId: trainer);
      final first =
          (await db.collection(Col.bookings).doc(id).get()).data()!['startedAt'];

      await repo.checkIn(id, trainerId: trainer).catchError((_) {});

      final second =
          (await db.collection(Col.bookings).doc(id).get()).data()!['startedAt'];
      expect(second, first, reason: 'the session started once');
    });
  });

  group('finishing the session', () {
    test('in progress -> completed on both lists, rider asked to rate',
        () async {
      final id = await confirmed(hour: '15:00');
      await repo.checkIn(id, trainerId: trainer);
      await repo.setStatus(await booking(id), BookingStatus.completed);

      expect((await booking(id)).status, BookingStatus.completed);
      expect((await booking(id)).bucket(), BookingBucket.history);

      final n = await notifications.watchFor(rider).first;
      expect(n.any((x) => x.title == 'Session complete 🎉'), isTrue);
    });

    test('the completed hour is released back to the calendar', () async {
      final id = await confirmed(hour: '15:00');
      await repo.checkIn(id, trainerId: trainer);
      await repo.setStatus(await booking(id), BookingStatus.completed);

      // `_assertSlotsFree` keys on status.isLive, so that is what actually
      // frees the hour. Re-booking it here would go through createBooking and
      // reintroduce the lead-time clock dependency this file avoids; §8.5's
      // release is proven end-to-end in flow_collision_test on a 2099 date.
      expect((await booking(id)).status.isLive, isFalse);
    });

    test('a session can be finished without ever being scanned', () async {
      // The trainer can complete straight from confirmed — the QR is a
      // convenience, not a required step in the state machine.
      final id = await confirmed(hour: '15:00');
      await repo.setStatus(await booking(id), BookingStatus.completed);

      expect((await booking(id)).status, BookingStatus.completed);
      final doc = (await db.collection(Col.bookings).doc(id).get()).data()!;
      expect(doc.containsKey('checkedIn'), isFalse,
          reason: 'nothing claims they turned up');
    });
  });

  group('adversarial — the ticket outlives its booking', () {
    test('a ticket for a booking that was deleted bounces by name', () async {
      final id = await confirmed(hour: '15:00');
      await db.collection(Col.bookings).doc(id).delete();

      await expectLater(
        repo.checkIn(id, trainerId: trainer),
        throwsA(isA<CheckInFailure>().having(
            (e) => e.message, 'message', contains('no longer exists'))),
      );
    });

    test('a ticket cancelled between issue and scan bounces, and the hour '
        'stays free', () async {
      final id = await confirmed(hour: '15:00');
      await repo.cancelByRider(await booking(id));

      await expectLater(
        repo.checkIn(id, trainerId: trainer),
        throwsA(isA<CheckInFailure>().having(
            (e) => e.message, 'message', contains('cancelled'))),
      );
      expect((await booking(id)).status.isLive, isFalse,
          reason: 'the hour goes back on the calendar rather than being held '
              'by a ticket nobody can use');
    });

    test('the payload of a cancelled booking is still well-formed', () async {
      // §10.7: a bounced scan shows an inline warning and keeps the camera
      // open. That only works if the payload parses — the *reason* it bounces
      // has to come from checkIn, not from a parse failure.
      final id = await confirmed(hour: '15:00');
      await repo.cancelByRider(await booking(id));

      final p = jsonDecode(TicketScreen.payloadFor(await booking(id)))
          as Map<String, dynamic>;
      expect(p['bookingId'], id);
      expect(p['trainerId'], trainer);
    });

    test('nothing is written when a scan bounces', () async {
      final id = await confirmed(hour: '15:00');
      final before =
          (await db.collection(Col.bookings).doc(id).get()).data()!;

      await repo.checkIn(id, trainerId: 'someone-else').catchError((_) {});

      final after = (await db.collection(Col.bookings).doc(id).get()).data()!;
      expect(after, before,
          reason: 'a refused check-in must leave the document untouched');
    });
  });
}
