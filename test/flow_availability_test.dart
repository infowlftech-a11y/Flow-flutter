// BUG-017 — the occupied half of §8.5, written at last.
//
// The booking read rule is `isParty() || isStaff()`, so a rider can never run
// the `instructorId + date` query the booking grid and `_assertSlotsFree`
// depend on: every rider booking failed at the moment of confirming, and the
// stopgap was a world-readable bookings collection marked MUST NOT SHIP.
//
// The fix is the schema §8.5 already specifies and nothing wrote: a booking
// that holds calendar hours also maintains `availability/{bookingId}` with
// `status: 'occupied'`. The grid and the clash check read `availability` —
// world-readable by design, and carrying no name, message or price — and
// bookings go back to being private.
//
// These tests pin the *lifecycle*: the doc exists exactly while the booking
// holds its hours, and dies with it. The rules side (who may write these
// docs) lives in test_rules/schedule.test.mjs, where rules actually execute.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flow/core/utils/date_x.dart';
import 'package:flow/data/firestore_paths.dart';
import 'package:flow/data/models/booking.dart';
import 'package:flow/data/models/catalogue.dart';
import 'package:flow/data/models/schedule.dart';
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
  const rider = 'rider1';
  const trainer = 'trainer1';

  Future<String> request({List<String> hours = const ['10:00', '11:00']}) =>
      repo.createBooking(
        target:
            const BookingTarget(providerId: trainer, title: 'Anna', rate: 50),
        riderUid: rider,
        riderName: 'Seif',
        riderLevel: 'Independent',
        date: day,
        slots: [for (final h in hours) Slot.tryParse(h)!],
        gearNeeded: false,
      );

  Future<Booking> booking(String id) async =>
      Booking.fromDoc(id, (await db.collection(Col.bookings).doc(id).get()).data()!);

  Future<Map<String, dynamic>?> occupiedDoc(String bookingId) async =>
      (await db.collection(Col.availability).doc(bookingId).get()).data();

  group('creation writes the occupied doc', () {
    test('a rider booking writes availability/{bookingId}', () async {
      final id = await request();
      final doc = await occupiedDoc(id);
      expect(doc, isNotNull,
          reason: 'the occupied doc is what makes the hours visible to the '
              'next rider once bookings are private again');
      expect(doc!['status'], 'occupied');
      expect(doc['instructorId'], trainer);
      expect(doc['date'], day);
      expect(doc['startTime'], '10:00');
      expect(doc['endTime'], '12:00');
    });

    test('the occupied doc expands to exactly the booked hours', () async {
      final id = await request(hours: ['09:00', '10:00', '11:00']);
      final doc = await occupiedDoc(id);
      final block = Availability.fromDoc(id, doc!);
      expect(block.blocksCalendar, isTrue);
      expect(
        block.expandBlock(),
        {Slot.fromHour(9), Slot.fromHour(10), Slot.fromHour(11)},
        reason: 'the grid renders exactly what expandBlock returns — a '
            'mismatch here double-books or falsely blocks an hour',
      );
    });

    test('a walk-in writes one too — riders cannot see the booking behind it',
        () async {
      await repo.createWalkIn(
        instructorId: trainer,
        instructorName: 'Anna',
        studentName: 'Beach walk-in',
        date: day,
        start: Slot.fromHour(14),
        durationHours: 2,
        totalPrice: 100,
      );
      final qs = await db
          .collection(Col.availability)
          .where('instructorId', isEqualTo: trainer)
          .where('date', isEqualTo: day)
          .get();
      expect(qs.docs, hasLength(1));
      expect(qs.docs.single['status'], 'occupied');
      expect(qs.docs.single['startTime'], '14:00');
      expect(qs.docs.single['endTime'], '16:00');
    });

    test('a safari seat holds no hours and writes none', () async {
      const trip = SafariTrip(
          id: 't1', hostId: trainer, title: 'Downwinder', price: 300,
          capacity: 6, bookedSeats: 0);
      await db.collection(Col.safariTrips).doc('t1').set({
        'hostId': trainer, 'title': 'Downwinder', 'price': 300,
        'capacity': 6, 'bookedSeats': 0, 'status': 'open',
      });
      await repo.reserveSafariSeat(
          trip: trip, hostName: 'Anna', riderUid: rider, riderName: 'Seif');
      expect((await db.collection(Col.availability).get()).docs, isEmpty);
    });
  });

  group('the doc dies with the booking', () {
    test('decline deletes it', () async {
      final id = await request();
      await repo.setStatus(await booking(id), BookingStatus.rejected);
      expect(await occupiedDoc(id), isNull,
          reason: 'a declined request must release its hours');
    });

    test('rider cancel deletes it', () async {
      final id = await request();
      await repo.cancelByRider(await booking(id));
      expect(await occupiedDoc(id), isNull);
    });

    test('completion deletes it — the hours are in the past', () async {
      final id = await request();
      await repo.setStatus(await booking(id), BookingStatus.confirmed);
      await repo.setStatus(await booking(id), BookingStatus.completed);
      expect(await occupiedDoc(id), isNull);
    });

    test('approval keeps it — a confirmed booking still holds its hours',
        () async {
      final id = await request();
      await repo.setStatus(await booking(id), BookingStatus.confirmed);
      expect(await occupiedDoc(id), isNotNull);
    });

    test('the approve UNDO (confirmed → pending) keeps it', () async {
      final id = await request();
      await repo.setStatus(await booking(id), BookingStatus.confirmed);
      await repo.setStatus(await booking(id), BookingStatus.pending);
      expect(await occupiedDoc(id), isNotNull,
          reason: 'pending still holds the hours (§8.5 isLive)');
    });

    test('a cancel on a booking with no occupied doc still lands', () async {
      // Every booking written before this change. The delete must be a no-op,
      // not an error that blocks the cancel itself.
      final ref = db.collection(Col.bookings).doc();
      await ref.set({
        'id': ref.id, 'instructorId': trainer, 'instructorName': 'Anna',
        'kiterId': rider, 'studentName': 'Seif', 'date': day,
        'startTime': '10:00', 'endTime': '11:00',
        'selectedTimes': ['10:00'], 'durationHours': 1,
        'totalPrice': 50, 'status': 'confirmed', 'paymentStatus': 'unpaid',
      });
      await repo.cancelByRider(await booking(ref.id));
      expect((await booking(ref.id)).status, BookingStatus.cancelled);
    });
  });

  group('the clash check reads availability, not bookings', () {
    test('a second rider is refused hours held by an occupied doc', () async {
      await request(hours: ['10:00', '11:00']);
      expect(
        () => repo.createBooking(
          target: const BookingTarget(
              providerId: trainer, title: 'Anna', rate: 50),
          riderUid: 'rider2',
          riderName: 'Nadia',
          riderLevel: 'Beginner',
          date: day,
          slots: [Slot.fromHour(11)],
          gearNeeded: false,
        ),
        throwsA(isA<SlotTakenFailure>()),
      );
    });

    test('a declined booking frees its hours for the next rider', () async {
      final id = await request(hours: ['10:00']);
      await repo.setStatus(await booking(id), BookingStatus.rejected);
      await expectLater(
        repo.createBooking(
          target: const BookingTarget(
              providerId: trainer, title: 'Anna', rate: 50),
          riderUid: 'rider2',
          riderName: 'Nadia',
          riderLevel: 'Beginner',
          date: day,
          slots: [Slot.fromHour(10)],
          gearNeeded: false,
        ),
        completes,
      );
    });

    test("a trainer's host-blocked hour also refuses the write (§8.6)",
        () async {
      // Before, the re-check only saw bookings: a block added between the
      // grid snapshot and the confirm slipped through to the calendar.
      await db.collection(Col.availability).add({
        'instructorId': trainer, 'date': day,
        'startTime': '10:00', 'endTime': '11:00', 'status': 'host-blocked',
      });
      expect(
        () => repo.createBooking(
          target: const BookingTarget(
              providerId: trainer, title: 'Anna', rate: 50),
          riderUid: rider,
          riderName: 'Seif',
          riderLevel: 'Independent',
          date: day,
          slots: [Slot.fromHour(10)],
          gearNeeded: false,
        ),
        throwsA(isA<SlotTakenFailure>()),
      );
    });

    test('a walk-in is refused hours an occupied doc holds', () async {
      await request(hours: ['10:00', '11:00']);
      expect(
        () => repo.createWalkIn(
          instructorId: trainer,
          instructorName: 'Anna',
          studentName: 'Walk-in',
          date: day,
          start: Slot.fromHour(11),
          durationHours: 1,
          totalPrice: 50,
        ),
        throwsA(isA<SlotTakenFailure>()),
      );
    });
  });

  group('DayAvailability.compose understands occupied docs', () {
    test('an occupied block lands in booked, not blocked', () {
      final day = DayAvailability.compose(
        date: '2099-06-15',
        blocks: [
          Availability.fromDoc('a1', {
            'instructorId': trainer, 'date': '2099-06-15',
            'startTime': '10:00', 'endTime': '12:00', 'status': 'occupied',
          }),
          Availability.fromDoc('a2', {
            'instructorId': trainer, 'date': '2099-06-15',
            'startTime': '14:00', 'endTime': '15:00', 'status': 'host-blocked',
          }),
        ],
        bookings: const [],
        vacations: const [],
      );
      expect(day.booked, {Slot.fromHour(10), Slot.fromHour(11)},
          reason: "an occupied hour is someone's session — the grid must say "
              "'Booked', and the schedule tab must not offer to release it");
      expect(day.blocked, {Slot.fromHour(14)});
      expect(day.blockedReason(Slot.fromHour(10)), 'Booked');
      expect(day.blockedReason(Slot.fromHour(14)), 'Unavailable');
    });
  });

  group('BUG-015 — a non-contiguous selection is refused at the write', () {
    test('createBooking throws on a gap', () async {
      // §8.4 lived only in the grid's _tapSlot. The write itself accepted
      // ['10:00', '15:00'] and recorded endTime 12:00 — a booking whose range
      // disagrees with the hours it actually holds.
      expect(
        () => request(hours: ['10:00', '15:00']),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('contiguous hours still book', () async {
      await expectLater(request(hours: ['10:00', '11:00', '12:00']),
          completion(isNotEmpty));
    });
  });
}
