// FLOW 3 — two riders want the same hour, and the travel buffer.
//
// §8.6 makes a claim this suite had never checked: hourly bookings are
// *checked, not locked*, so two riders confirming the same hour in the same
// instant both land as pending and the trainer declines one. That is a
// deliberate trade — Firestore transactions cannot read a query, so a true
// lock would need a per-slot document. Untested, it is just a comment.
//
// §8.3 carries an explicit warning: `bufferedEndTime` is *written* to the
// booking but availability only ever subtracts `occupiedSlots`, so the travel
// buffer is stored, not enforced. The blueprint says to preserve or fix that
// deliberately and never by accident, which is only possible if a test holds
// it still.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flow/core/utils/date_x.dart';
import 'package:flow/data/firestore_paths.dart';
import 'package:flow/data/models/booking.dart';
import 'package:flow/data/models/catalogue.dart';
import 'package:flow/data/repositories/booking_repository.dart';
import 'package:flow/data/repositories/notification_repository.dart';

void main() {
  late FakeFirebaseFirestore db;
  late BookingRepository repo;

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = BookingRepository(db, NotificationRepository(db));
  });

  const day = '2099-06-15';
  const trainer = 'trainer1';

  Future<String> book(
    List<String> hours, {
    String rider = 'rider1',
    String provider = trainer,
    String date = day,
  }) =>
      repo.createBooking(
        target: BookingTarget(providerId: provider, title: 'Anna', rate: 50),
        riderUid: rider,
        riderName: rider,
        riderLevel: 'Independent',
        date: date,
        slots: [for (final h in hours) Slot.tryParse(h)!],
        gearNeeded: false,
      );

  Future<List<Booking>> dayBookings() =>
      repo.watchDayBookings(trainer, day).first;

  group('§8.6 — checked, not locked', () {
    test('two riders confirming the same hour at once BOTH land as pending',
        () async {
      // The documented consequence of not locking. Both writes pass their
      // own clash check because neither has landed when the other queries.
      final ids = await Future.wait([
        book(['10:00'], rider: 'riderA'),
        book(['10:00'], rider: 'riderB'),
      ]);

      expect(ids, hasLength(2));
      expect(ids.toSet(), hasLength(2), reason: 'two distinct documents');

      final booked = await dayBookings();
      expect(booked, hasLength(2));
      expect(booked.every((b) => b.status == BookingStatus.pending), isTrue,
          reason: 'neither is confirmed — the trainer resolves the conflict');
    });

    test('the trainer is left holding both requests for the same hour',
        () async {
      await Future.wait([
        book(['10:00'], rider: 'riderA'),
        book(['10:00'], rider: 'riderB'),
      ]);

      final requests = await repo.watchTrainerBookings(trainer).first;
      final tenOClock = requests
          .where((b) => b.occupiedSlots.any((s) => s.value == '10:00'))
          .toList();
      expect(tenOClock, hasLength(2),
          reason: 'both are visible so the trainer can decline one (§8.6)');
    });

    test('declining one leaves the other holding the hour', () async {
      await Future.wait([
        book(['10:00'], rider: 'riderA'),
        book(['10:00'], rider: 'riderB'),
      ]);
      final both = await dayBookings();
      await repo.setStatus(both.first, BookingStatus.rejected);
      await repo.setStatus(both.last, BookingStatus.confirmed);

      // A third rider now bounces off the surviving confirmed booking.
      await expectLater(
          book(['10:00'], rider: 'riderC'), throwsA(isA<SlotTakenFailure>()));
    });

    test('once a booking has landed, the next rider is refused', () async {
      await book(['10:00'], rider: 'riderA');
      await expectLater(
        book(['10:00'], rider: 'riderB'),
        throwsA(isA<SlotTakenFailure>()),
      );
    });

    test('the refusal names the hours that clashed', () async {
      await book(['10:00', '11:00'], rider: 'riderA');
      try {
        await book(['11:00', '12:00'], rider: 'riderB');
        fail('expected SlotTakenFailure');
      } on SlotTakenFailure catch (e) {
        expect(e.slots, ['11:00'],
            reason: 'only the overlapping hour, so the UI can clear just it');
      }
    });
  });

  group('overlap geometry', () {
    setUp(() => book(['10:00', '11:00', '12:00'], rider: 'riderA'));

    test('an identical range clashes', () async {
      await expectLater(book(['10:00', '11:00', '12:00'], rider: 'riderB'),
          throwsA(isA<SlotTakenFailure>()));
    });

    test('a range contained inside it clashes', () async {
      await expectLater(
          book(['11:00'], rider: 'riderB'), throwsA(isA<SlotTakenFailure>()));
    });

    test('a range straddling its start clashes', () async {
      await expectLater(book(['09:00', '10:00'], rider: 'riderB'),
          throwsA(isA<SlotTakenFailure>()));
    });

    test('a range straddling its end clashes', () async {
      await expectLater(book(['12:00', '13:00'], rider: 'riderB'),
          throwsA(isA<SlotTakenFailure>()));
    });

    test('the hour immediately before is free — adjacency is not overlap',
        () async {
      await expectLater(book(['09:00'], rider: 'riderB'), completes);
    });

    test('the hour immediately after is free', () async {
      await expectLater(book(['13:00'], rider: 'riderB'), completes);
    });

    test('the same hour on another day is free', () async {
      await expectLater(
          book(['10:00'], rider: 'riderB', date: '2099-06-16'), completes);
    });

    test('the same hour with another trainer is free', () async {
      await expectLater(
          book(['10:00'], rider: 'riderB', provider: 'trainer2'), completes);
    });
  });

  group('which statuses hold an hour (§8.5)', () {
    Future<void> holdsAfter(BookingStatus s, {required bool held}) async {
      final id = await book(['10:00'], rider: 'riderA');
      final b = (await dayBookings()).firstWhere((x) => x.id == id);
      await repo.setStatus(b, s);

      final matcher = held ? throwsA(isA<SlotTakenFailure>()) : returnsNormally;
      await expectLater(
          () async => book(['10:00'], rider: 'riderB'), matcher);
    }

    test('pending holds it — an unanswered request is not a free hour',
        () async {
      final id = await book(['10:00'], rider: 'riderA');
      expect(id, isNotEmpty);
      await expectLater(
          book(['10:00'], rider: 'riderB'), throwsA(isA<SlotTakenFailure>()));
    });

    test('confirmed holds it', () => holdsAfter(BookingStatus.confirmed, held: true));
    test('inProgress holds it', () => holdsAfter(BookingStatus.inProgress, held: true));
    test('cancelled releases it', () => holdsAfter(BookingStatus.cancelled, held: false));
    test('rejected releases it', () => holdsAfter(BookingStatus.rejected, held: false));
    test('completed releases it', () => holdsAfter(BookingStatus.completed, held: false));
  });

  group('§8.3 — the travel buffer is stored, not enforced', () {
    test('bufferedEndTime is written an hour past the end', () async {
      final id = await book(['10:00']);
      final doc = (await db.collection(Col.bookings).doc(id).get()).data()!;

      expect(doc['endTime'], '11:00');
      expect(doc['bufferedEndTime'], '12:00');
    });

    test('but the buffered hour is still bookable by the next rider',
        () async {
      // The blueprint's explicit warning, pinned. `_assertSlotsFree` subtracts
      // occupiedSlots, which stops at endTime — so a trainer can be booked
      // back-to-back with no travel time despite the buffer being recorded.
      await book(['10:00'], rider: 'riderA');

      await expectLater(book(['11:00'], rider: 'riderB'), completes,
          reason: 'if this ever starts throwing, the buffer became enforced '
              '— a deliberate change, never an accidental one (§8.3)');
    });

    test('a custom buffer is recorded but changes nothing about the clash',
        () async {
      await repo.createBooking(
        target: const BookingTarget(
            providerId: trainer, title: 'Anna', rate: 50),
        riderUid: 'riderA', riderName: 'A', riderLevel: 'Independent',
        date: day, slots: [const Slot('10:00')], gearNeeded: false,
        bufferMinutes: 180,
      );

      final doc = (await dayBookings()).single;
      expect(doc.occupiedSlots.map((s) => s.value), ['10:00']);
      await expectLater(book(['11:00'], rider: 'riderB'), completes);
    });
  });

  group('boundaries of the bookable day (§8.1)', () {
    test('08:00, the first slot, books', () async {
      await expectLater(book(['08:00']), completes);
    });

    test('17:00, the last slot, books and ends at 18:00', () async {
      final id = await book(['17:00']);
      final doc = (await db.collection(Col.bookings).doc(id).get()).data()!;
      expect(doc['endTime'], '18:00');
    });

    test('a booking crossing midnight is refused before any write', () async {
      await expectLater(
        repo.createBooking(
          target: const BookingTarget(
              providerId: trainer, title: 'Anna', rate: 50),
          riderUid: 'riderA', riderName: 'A', riderLevel: 'Independent',
          date: day,
          slots: [for (var h = 20; h < 24; h++) Slot.fromHour(h)],
          gearNeeded: false,
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect((await db.collection(Col.bookings).get()).docs, isEmpty,
          reason: 'a rejected booking must leave nothing behind');
    });

    test('no slots at all is a programming error, not a write', () async {
      await expectLater(book(const []), throwsA(isA<ArgumentError>()));
      expect((await db.collection(Col.bookings).get()).docs, isEmpty);
    });

    test('hours given out of order are normalised before the window is cut',
        () async {
      final id = await book(['12:00', '10:00', '11:00']);
      final doc = (await db.collection(Col.bookings).doc(id).get()).data()!;

      expect(doc['startTime'], '10:00');
      expect(doc['endTime'], '13:00');
      expect(doc['durationHours'], 3);
    });

    test('a non-contiguous selection is refused, and writes nothing',
        () async {
      // 10:00 and 15:00 with nothing between. This used to be accepted and
      // windowed as 10:00-12:00 — a booking whose range disagreed with the
      // hours it claimed, pinned here as current behaviour while BUG-015 was
      // open. §8.4 now holds at the write as well as in the grid, and the
      // occupied availability doc depends on it: that doc is one
      // [start, end) range and cannot represent a gap.
      await expectLater(
          book(['10:00', '15:00']), throwsA(isA<ArgumentError>()));
      expect((await db.collection(Col.bookings).get()).docs, isEmpty);
    });
  });

  group('safari seats ARE locked (§8.6)', () {
    Future<void> seedTrip({int capacity = 2}) =>
        db.collection(Col.safariTrips).doc('trip1').set({
          'hostId': trainer, 'title': 'Downwinder', 'capacity': capacity,
          'bookedSeats': 0, 'status': 'open', 'price': 300,
        });

    Future<Map<String, dynamic>> raw() async =>
        (await db.collection(Col.safariTrips).doc('trip1').get()).data()!;

    Future<SafariTrip> trip() async => SafariTrip.fromDoc('trip1', await raw());

    // NOT TESTABLE HERE — and the reason matters, because the obvious test
    // produces a confident false positive.
    //
    // Running three concurrent reserveSafariSeat calls against a 2-seat trip
    // sells three seats. That looks exactly like an overselling bug, but it
    // is the test double: fake_cloud_firestore's runTransaction has no
    // isolation at all. Two concurrent transactions that each read a counter
    // and write read+1 land on 1, not 2 — a plain lost update.
    //
    // So NOTHING in this file, or anywhere else in the Dart suite, can verify
    // a transactional-isolation claim: not safari seats, not markPaid's
    // double-settle guard, not checkIn, not blockUser. Those tests verify
    // their *precondition logic*, which is real and worth having, and say
    // nothing about contention.
    //
    // Real-Firestore contention is verified instead in
    // test_rules/transactions.test.mjs, against the emulator.

    test('sequentially, the capacity check refuses the seat past the last one',
        () async {
      await seedTrip(capacity: 1);
      await repo.reserveSafariSeat(
          trip: await trip(), hostName: 'Anna', riderUid: 'r1',
          riderName: 'r1');

      await expectLater(
        repo.reserveSafariSeat(
            trip: await trip(), hostName: 'Anna', riderUid: 'r2',
            riderName: 'r2'),
        throwsA(isA<SlotTakenFailure>()),
      );
      expect((await trip()).bookedSeats, 1);
    });

    test('the trip flips to full on the last seat', () async {
      await seedTrip(capacity: 1);
      await repo.reserveSafariSeat(
          trip: await trip(), hostName: 'Anna', riderUid: 'r1',
          riderName: 'r1');

      expect((await raw())['status'], 'full');
    });
  });
}
