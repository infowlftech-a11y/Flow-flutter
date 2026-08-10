// BookingRepository against an in-memory Firestore. This is the app's money
// and calendar logic — the invariants below are each documented in the
// repository as a bug that actually happened or a fraud path that had to be
// closed, which makes them exactly the lines a refactor must not lose:
//
//   * a cancelled booking's hours do not block the calendar;
//   * an uncapped safari (capacity 0) never reports itself full;
//   * a double cancel cannot drive the seat count negative;
//   * settling twice is idempotent, refunds keep the paid timestamp;
//   * a stale QR ticket cannot resurrect, rewind, or pre-start a session.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flow/core/utils/date_x.dart';
import 'package:flow/data/firestore_paths.dart';
import 'package:flow/data/models/booking.dart';
import 'package:flow/data/models/catalogue.dart';
import 'package:flow/data/models/social.dart';
import 'package:flow/data/repositories/booking_repository.dart';
import 'package:flow/data/repositories/notification_repository.dart';

void main() {
  late FakeFirebaseFirestore db;
  late BookingRepository repo;
  late NotificationRepository notifications;

  setUp(() {
    db = FakeFirebaseFirestore();
    notifications = NotificationRepository(db);
    repo = BookingRepository(db, notifications);
  });

  // A date far enough out that no lead-time rule can touch it.
  const day = '2099-06-15';

  BookingTarget target({double rate = 50}) => BookingTarget(
      providerId: 'trainer1', title: 'Anna', rate: rate);

  Future<String> create({List<String> hours = const ['10:00', '11:00']}) =>
      repo.createBooking(
        target: target(),
        riderUid: 'rider1',
        riderName: 'Seif',
        riderLevel: 'Independent',
        date: day,
        slots: [for (final h in hours) Slot.tryParse(h)!],
        gearNeeded: false,
      );

  group('createBooking', () {
    test('writes the canonical shape, pending, with payment owed', () async {
      final id = await create();
      final doc = (await db.collection(Col.bookings).doc(id).get()).data()!;
      expect(doc['status'], 'pending',
          reason: 'every rider booking starts pending — no instant booking');
      expect(doc['selectedTimes'], ['10:00', '11:00']);
      expect(doc['durationHours'], 2);
      expect(doc['totalPrice'], 100);
      expect(doc['paymentStatus'], 'unpaid');
      expect(doc['amountDue'], 100,
          reason: 'the amount is captured at booking time, not derived later');
      final b = Booking.fromDoc(id, doc);
      expect(b.timeRange, '10:00–12:00');
    });

    test('notifies the trainer', () async {
      final id = await create();
      final inbox = await notifications.watchFor('trainer1').first;
      expect(inbox, hasLength(1));
      expect(inbox.single.kind, NotificationKind.bookingRequest);
      expect(inbox.single.bookingId, id);
    });

    test('no slots is a programming error, not a Firestore write', () async {
      expect(() => create(hours: const []), throwsArgumentError);
      expect((await db.collection(Col.bookings).get()).docs, isEmpty);
    });

    test('a live booking blocks its hours — naming the clash', () async {
      await create(hours: const ['10:00', '11:00']);
      expect(
        () => create(hours: const ['11:00', '12:00']),
        throwsA(isA<SlotTakenFailure>()
            .having((f) => f.slots, 'slots', ['11:00'])),
      );
    });

    test('a cancelled booking releases its hours', () async {
      final id = await create(hours: const ['10:00']);
      await db
          .collection(Col.bookings)
          .doc(id)
          .update({'status': 'cancelled'});
      await expectLater(create(hours: const ['10:00']), completes);
    });

    test('an hour inside today’s lead time is LeadTimeFailure', () async {
      // The repo has no clock injection (frozen), so the slot is derived
      // from the same rule it consults. Between 00:00 and 06:59 local the
      // rule genuinely marks nothing — skip rather than fake it.
      final gone = BookingMath.pastSlots(todayYmd());
      if (gone.isEmpty) {
        markTestSkipped('before 07:00 local no grid hour is inside lead time');
        return;
      }
      expect(
        () => repo.createBooking(
          target: target(),
          riderUid: 'r',
          riderName: 'S',
          riderLevel: 'x',
          date: todayYmd(),
          slots: [gone.first],
          gearNeeded: false,
        ),
        throwsA(isA<LeadTimeFailure>()),
      );
    });
  });

  group('safari seats', () {
    SafariTrip trip({int capacity = 2, int booked = 0}) => SafariTrip(
        id: 'trip1',
        hostId: 'host1',
        title: 'Sunset downwinder',
        startDate: day,
        price: 95,
        capacity: capacity,
        bookedSeats: booked);

    Future<void> seedTrip({int capacity = 2, int booked = 0}) =>
        db.collection(Col.safariTrips).doc('trip1').set({
          'capacity': capacity,
          'bookedSeats': booked,
          'status': 'open',
        });

    test('reserving counts the seat and books it as owed', () async {
      await seedTrip();
      await repo.reserveSafariSeat(
          trip: trip(), hostName: 'Red Sea Co.', riderUid: 'r1', riderName: 'S');
      final t = (await db.collection(Col.safariTrips).doc('trip1').get()).data()!;
      expect(t['bookedSeats'], 1);
      expect(t['status'], 'open');
      final b = (await db.collection(Col.bookings).get()).docs.single.data();
      expect(b['type'], 'safari');
      expect(b['paymentStatus'], 'unpaid',
          reason: 'a reserved seat is owed, not paid — the v2.6 lie');
    });

    test('the last seat flips the trip to full; the next rider bounces',
        () async {
      await seedTrip(capacity: 2, booked: 1);
      await repo.reserveSafariSeat(
          trip: trip(), hostName: 'H', riderUid: 'r1', riderName: 'S');
      final t = (await db.collection(Col.safariTrips).doc('trip1').get()).data()!;
      expect(t['status'], 'full');
      expect(
        () => repo.reserveSafariSeat(
            trip: trip(), hostName: 'H', riderUid: 'r2', riderName: 'T'),
        throwsA(isA<SlotTakenFailure>()),
      );
    });

    test('an uncapped trip never reports full', () async {
      await seedTrip(capacity: 0);
      await repo.reserveSafariSeat(
          trip: trip(capacity: 0), hostName: 'H', riderUid: 'r1', riderName: 'S');
      final t = (await db.collection(Col.safariTrips).doc('trip1').get()).data()!;
      expect(t['status'], 'open',
          reason: 'capacity 0 means uncapped — 1 >= 0 must not read as full');
    });

    test('capacity stored as a string still guards the seat', () async {
      await db.collection(Col.safariTrips).doc('trip1').set({
        'capacity': '1', // the web client's legacy typing
        'bookedSeats': 1,
      });
      expect(
        () => repo.reserveSafariSeat(
            trip: trip(capacity: 1), hostName: 'H', riderUid: 'r', riderName: 'S'),
        throwsA(isA<SlotTakenFailure>()),
        reason: 'tolerant readers inside the transaction, not raw casts',
      );
    });
  });

  group('cancelByRider on a safari', () {
    Booking safariBooking(String id) => Booking(
        id: id,
        date: day,
        status: BookingStatus.confirmed,
        instructorId: 'host1',
        instructorName: 'H',
        kiterId: 'r1',
        studentName: 'S',
        type: 'safari',
        tripId: 'trip1');

    test('releases the seat and reopens the trip', () async {
      await db
          .collection(Col.safariTrips)
          .doc('trip1')
          .set({'capacity': 2, 'bookedSeats': 2, 'status': 'full'});
      await db.collection(Col.bookings).doc('b1').set({'status': 'confirmed'});
      await repo.cancelByRider(safariBooking('b1'));
      final t = (await db.collection(Col.safariTrips).doc('trip1').get()).data()!;
      expect(t['bookedSeats'], 1);
      expect(t['status'], 'open');
    });

    test('a double cancel floors the count at zero', () async {
      await db
          .collection(Col.safariTrips)
          .doc('trip1')
          .set({'capacity': 2, 'bookedSeats': 1, 'status': 'open'});
      await db.collection(Col.bookings).doc('b1').set({'status': 'confirmed'});
      await repo.cancelByRider(safariBooking('b1'));
      await repo.cancelByRider(safariBooking('b1')); // retry that already landed
      final t = (await db.collection(Col.safariTrips).doc('trip1').get()).data()!;
      expect(t['bookedSeats'], 0,
          reason: 'a negative count over-reports free seats forever');
    });
  });

  group('settlement', () {
    Future<void> seedBooking(String id,
            {String trainer = 'trainer1', String payment = 'unpaid'}) =>
        db.collection(Col.bookings).doc(id).set({
          'instructorId': trainer,
          'status': 'completed',
          'paymentStatus': payment,
        });

    test('markPaid settles, and settling twice is not an error', () async {
      await seedBooking('b1');
      await repo.markPaid('b1', trainerId: 'trainer1');
      final first =
          (await db.collection(Col.bookings).doc('b1').get()).data()!;
      expect(first['paymentStatus'], 'paid');
      final firstPaidAt = first['paidAt'];
      await repo.markPaid('b1', trainerId: 'trainer1');
      final second =
          (await db.collection(Col.bookings).doc('b1').get()).data()!;
      expect(second['paidAt'], firstPaidAt,
          reason: 'a double tap must not overwrite when the money arrived');
    });

    test('only the owning trainer can settle or refund', () async {
      await seedBooking('b1');
      expect(() => repo.markPaid('b1', trainerId: 'intruder'),
          throwsA(isA<PaymentFailure>()));
      expect(() => repo.markRefunded('b1', trainerId: 'intruder'),
          throwsA(isA<PaymentFailure>()));
    });

    test('a refunded session refuses payment until reopened', () async {
      await seedBooking('b1', payment: 'refunded');
      expect(() => repo.markPaid('b1', trainerId: 'trainer1'),
          throwsA(isA<PaymentFailure>()));
    });

    test('a refund keeps the paid timestamp — two events, one ledger',
        () async {
      await seedBooking('b1', payment: 'paid');
      await db
          .collection(Col.bookings)
          .doc('b1')
          .update({'paidAt': DateTime(2026, 1, 1)});
      await repo.markRefunded('b1', trainerId: 'trainer1');
      final doc = (await db.collection(Col.bookings).doc('b1').get()).data()!;
      expect(doc['paymentStatus'], 'refunded');
      expect(doc['paidAt'], isNotNull);
    });

    test('a vanished booking is a named failure, not a crash', () async {
      expect(() => repo.markPaid('ghost', trainerId: 't'),
          throwsA(isA<PaymentFailure>()));
    });
  });

  group('checkIn — the stale-ticket matrix', () {
    Future<void> seed(String status, {String date = '2099-06-15'}) =>
        db.collection(Col.bookings).doc('b1').set({
          'instructorId': 'trainer1',
          'kiterId': 'r1',
          'status': status,
          'date': date,
        });

    test('a confirmed booking for today starts', () async {
      await seed('confirmed', date: todayYmd());
      await repo.checkIn('b1', trainerId: 'trainer1');
      final doc = (await db.collection(Col.bookings).doc('b1').get()).data()!;
      expect(doc['status'], 'in_progress');
      expect(doc['checkedIn'], true);
    });

    test('someone else’s ticket bounces before any state is read', () async {
      await seed('confirmed', date: todayYmd());
      expect(() => repo.checkIn('b1', trainerId: 'other'),
          throwsA(isA<CheckInFailure>()));
    });

    test('every non-confirmed status bounces with its own reason', () async {
      for (final status in ['pending', 'cancelled', 'rejected', 'completed']) {
        await seed(status, date: todayYmd());
        await expectLater(
          repo.checkIn('b1', trainerId: 'trainer1'),
          throwsA(isA<CheckInFailure>()),
          reason: 'a stale screenshot must not $status → in_progress',
        );
      }
      // And already running is its own message, not a silent success.
      await seed('in_progress', date: todayYmd());
      await expectLater(repo.checkIn('b1', trainerId: 'trainer1'),
          throwsA(isA<CheckInFailure>()));
    });

    test('a ticket for another day bounces even when confirmed', () async {
      await seed('confirmed', date: '2099-06-15');
      await expectLater(
        repo.checkIn('b1', trainerId: 'trainer1'),
        throwsA(isA<CheckInFailure>()),
        reason: 'a future booking started today holds its hours forever',
      );
    });
  });

  group('setStatus notifications', () {
    Booking booking({String kiterId = 'r1', String? type}) => Booking(
        id: 'b1',
        date: day,
        status: BookingStatus.pending,
        instructorId: 'trainer1',
        instructorName: 'T',
        kiterId: kiterId,
        studentName: 'S',
        type: type);

    setUp(() =>
        db.collection(Col.bookings).doc('b1').set({'status': 'pending'}));

    test('approval notifies the rider with the right kind', () async {
      await repo.setStatus(booking(), BookingStatus.confirmed);
      final inbox = await notifications.watchFor('r1').first;
      expect(inbox.single.kind, NotificationKind.bookingConfirmed);
    });

    test('a decline reason is carried into the message', () async {
      await repo.setStatus(booking(), BookingStatus.rejected,
          declineReason: 'Wind too strong');
      final inbox = await notifications.watchFor('r1').first;
      expect(inbox.single.message, contains('Wind too strong'));
    });

    test('walk-ins never notify — there is no account behind them', () async {
      await repo.setStatus(
          booking(kiterId: 'manual_entry'), BookingStatus.completed);
      expect(await notifications.watchFor('manual_entry').first, isEmpty);
    });
  });

  test('hide is per side', () async {
    await db.collection(Col.bookings).doc('b1').set({'status': 'completed'});
    await repo.hide('b1', asInstructor: true);
    var doc = (await db.collection(Col.bookings).doc('b1').get()).data()!;
    expect(doc['hiddenByInstructor'], true);
    expect(doc.containsKey('hiddenByGuest'), isFalse);
    await repo.hide('b1', asInstructor: false);
    doc = (await db.collection(Col.bookings).doc('b1').get()).data()!;
    expect(doc['hiddenByGuest'], true);
  });
}
