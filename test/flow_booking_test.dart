// FLOW 2 — a rider requests an hour, the trainer answers, both sides agree.
//
// booking_repository_test.dart already covers the single-actor mechanics:
// the write shape, clash detection, lead time, settlement and the stale-QR
// matrix. What it does not cover is the thing that makes this a *flow* — that
// after every transition the rider's list and the trainer's list are telling
// the same story, and that the right party is told about it.
//
// Two views resolve from one database:
//
//   rider   → watchRiderBookings(uid)    (Sessions)
//   trainer → watchTrainerBookings(uid)  (Command Center)
//
// §11.1's notification table is asserted row by row, on content, because a
// notification with the wrong recipient is invisible rather than wrong, and
// nothing else in the suite would notice.
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

  const day = '2099-06-15';
  const rider = 'rider1';
  const trainer = 'trainer1';

  Future<String> request({
    List<String> hours = const ['10:00', '11:00'],
    String uid = rider,
    String name = 'Seif',
  }) =>
      repo.createBooking(
        target: const BookingTarget(
            providerId: trainer, title: 'Anna', rate: 50),
        riderUid: uid,
        riderName: name,
        riderLevel: 'Independent',
        date: day,
        slots: [for (final h in hours) Slot.tryParse(h)!],
        gearNeeded: false,
      );

  Future<Booking> asRider(String id) async => (await repo
          .watchRiderBookings(rider)
          .first)
      .firstWhere((b) => b.id == id);

  Future<Booking> asTrainer(String id) async => (await repo
          .watchTrainerBookings(trainer)
          .first)
      .firstWhere((b) => b.id == id);

  /// Asserts both parties resolve the same booking to the same status — the
  /// whole point of the flow.
  Future<void> expectBothSee(String id, BookingStatus status) async {
    expect((await asRider(id)).status, status, reason: "rider's view");
    expect((await asTrainer(id)).status, status, reason: "trainer's view");
  }

  Future<List<AppNotification>> inbox(String uid) =>
      notifications.watchFor(uid).first;

  group('the request lands on both lists', () {
    test('rider sees it pending, trainer sees it pending', () async {
      final id = await request();
      await expectBothSee(id, BookingStatus.pending);
    });

    test('it is the same document, not two', () async {
      final id = await request();
      expect((await asRider(id)).id, (await asTrainer(id)).id);
      expect((await db.collection(Col.bookings).get()).docs, hasLength(1));
    });

    test('a third party sees nothing', () async {
      await request();
      expect(await repo.watchRiderBookings('someone-else').first, isEmpty);
      expect(await repo.watchTrainerBookings('other-trainer').first, isEmpty);
    });

    test('the rider is waiting, not approved (§8.7 subLabel)', () async {
      final id = await request();
      expect((await asRider(id)).subLabel, 'Waiting for trainer');
    });
  });

  group('approve', () {
    test('both sides move to confirmed together', () async {
      final id = await request();
      await repo.setStatus(await asTrainer(id), BookingStatus.confirmed);
      await expectBothSee(id, BookingStatus.confirmed);
      expect((await asRider(id)).subLabel, 'Approved');
    });

    test('notifies the rider and not the trainer (§11.1)', () async {
      final id = await request();
      await repo.setStatus(await asTrainer(id), BookingStatus.confirmed);

      final theirs = await inbox(rider);
      expect(theirs, hasLength(1));
      expect(theirs.single.title, 'Booking approved ✅');
      expect(theirs.single.message, contains('is confirmed'));
      expect(theirs.single.kind, NotificationKind.bookingConfirmed);
      expect(theirs.single.bookingId, id,
          reason: 'the tap must deep-link to this booking (§11.2)');

      // The trainer keeps only the original request notification.
      final trainers = await inbox(trainer);
      expect(trainers, hasLength(1));
      expect(trainers.single.title, 'New booking request');
    });

    test('approving twice does not double-notify the rider', () async {
      // IDEMPOTENCY. Unlike the admin console, approve here has a busy guard
      // (§10.5) — but a second device can still land the same write.
      final id = await request();
      final b = await asTrainer(id);
      await repo.setStatus(b, BookingStatus.confirmed);
      await repo.setStatus(b, BookingStatus.confirmed);

      await expectBothSee(id, BookingStatus.confirmed);
      expect(await inbox(rider), hasLength(2),
          reason: 'documents current behaviour: the write is idempotent, '
              'the notification is not');
    });
  });

  group('decline', () {
    test('both sides move to rejected together', () async {
      final id = await request();
      await repo.setStatus(await asTrainer(id), BookingStatus.rejected);
      await expectBothSee(id, BookingStatus.rejected);
      expect((await asRider(id)).subLabel, 'Declined');
    });

    test('with no reason, the message carries none', () async {
      final id = await request();
      await repo.setStatus(await asTrainer(id), BookingStatus.rejected);

      final m = (await inbox(rider)).first.message;
      expect(m, contains('was declined'));
      expect(m, isNot(contains('Reason:')));
    });

    test('a whitespace-only reason is treated as no reason', () async {
      final id = await request();
      await repo.setStatus(await asTrainer(id), BookingStatus.rejected,
          declineReason: '   ');

      expect((await inbox(rider)).first.message, isNot(contains('Reason:')));
    });

    test('declined hours go back on the calendar (§8.5)', () async {
      final id = await request(hours: ['10:00']);
      await repo.setStatus(await asTrainer(id), BookingStatus.rejected);

      // The proof: the same hour books again without a clash.
      await expectLater(request(hours: ['10:00']), completes);
    });
  });

  group('rider cancels', () {
    test('both sides move to cancelled together', () async {
      final id = await request();
      await repo.setStatus(await asTrainer(id), BookingStatus.confirmed);
      await repo.cancelByRider(await asRider(id));

      await expectBothSee(id, BookingStatus.cancelled);
      expect((await asRider(id)).subLabel, 'Cancelled');
    });

    test('the trainer is told, with the session named (§11.1)', () async {
      final id = await request();
      await repo.cancelByRider(await asRider(id));

      final theirs = await inbox(trainer);
      expect(theirs, hasLength(2)); // the request, then the cancellation
      final cancel = theirs.firstWhere((n) => n.title.contains('cancelled'));
      expect(cancel.title, 'Rider cancelled ⚠️');
      expect(cancel.message, contains('Seif'));
      expect(cancel.kind, NotificationKind.bookingCancelled);
    });

    test('the rider is not told about their own cancellation', () async {
      final id = await request();
      await repo.cancelByRider(await asRider(id));

      expect(await inbox(rider), isEmpty,
          reason: 'you do not need telling about a thing you just did');
    });

    test('the write records who cancelled (§6.3)', () async {
      final id = await request();
      await repo.cancelByRider(await asRider(id));

      final doc = (await db.collection(Col.bookings).doc(id).get()).data()!;
      expect(doc['cancelledBy'], 'user');
      expect(doc['cancelledAt'], isNotNull);
    });
  });

  group('trainer cancels a confirmed session', () {
    test('the rider is told (§11.1)', () async {
      final id = await request();
      await repo.setStatus(await asTrainer(id), BookingStatus.confirmed);
      await repo.setStatus(await asTrainer(id), BookingStatus.cancelled);

      await expectBothSee(id, BookingStatus.cancelled);
      final cancel =
          (await inbox(rider)).firstWhere((n) => n.title == 'Booking cancelled');
      expect(cancel.message, contains('was cancelled'));
      expect(cancel.kind, NotificationKind.bookingCancelled);
    });
  });

  group('completion', () {
    test('both sides see completed, and the rider is asked to rate', () async {
      final id = await request();
      await repo.setStatus(await asTrainer(id), BookingStatus.confirmed);
      await repo.setStatus(await asTrainer(id), BookingStatus.completed);

      await expectBothSee(id, BookingStatus.completed);
      final n = (await inbox(rider)).firstWhere((x) => x.title.contains('🎉'));
      expect(n.title, 'Session complete 🎉');
      expect(n.message, contains('rate your trainer'));
      expect(n.kind, NotificationKind.review,
          reason: 'routes to /sessions, where the composer lives (§11.2)');
    });
  });

  group('walk-ins have no rider to notify (§11.1)', () {
    Future<void> walkIn() => repo.createWalkIn(
          instructorId: trainer,
          instructorName: 'Anna',
          studentName: 'Beach walk-up',
          date: day,
          start: Slot.tryParse('14:00')!,
          durationHours: 1,
          totalPrice: 60,
        );

    test('creating one notifies nobody', () async {
      await walkIn();
      expect(await inbox(trainer), isEmpty);
      expect((await db.collection(Col.notifications).get()).docs, isEmpty);
    });

    test('it appears on the trainers list only', () async {
      await walkIn();
      expect(await repo.watchTrainerBookings(trainer).first, hasLength(1));
      expect(await repo.watchRiderBookings(rider).first, isEmpty);
    });

    test('completing one notifies nobody — manual_entry has no account',
        () async {
      await walkIn();
      final b = (await repo.watchTrainerBookings(trainer).first).single;
      await repo.setStatus(b, BookingStatus.completed);

      expect(b.status, isNot(BookingStatus.completed),
          reason: 'the local object is stale; the stored doc is what moved');
      expect((await db.collection(Col.notifications).get()).docs, isEmpty);
    });
  });

  group('§8.7 subLabel — the full table', () {
    Booking make(BookingStatus s, {String date = '2099-01-01'}) =>
        Booking.fromDoc('x', {
          'instructorId': trainer, 'kiterId': rider, 'date': date,
          'startTime': '10:00', 'endTime': '11:00', 'status': s.wire,
        });

    test('a future pending request is waiting', () {
      expect(make(BookingStatus.pending).subLabel, 'Waiting for trainer');
    });

    test('a past pending request expired', () {
      expect(make(BookingStatus.pending, date: '2020-01-01').subLabel,
          'Expired — never confirmed');
    });

    test('a future confirmed booking is approved', () {
      expect(make(BookingStatus.confirmed).subLabel, 'Approved');
    });

    test('a past confirmed booking is a past session', () {
      expect(make(BookingStatus.confirmed, date: '2020-01-01').subLabel,
          'Past session');
    });

    test('the terminal states read plainly', () {
      expect(make(BookingStatus.inProgress).subLabel, 'In progress');
      expect(make(BookingStatus.completed).subLabel, 'Completed');
      expect(make(BookingStatus.cancelled).subLabel, 'Cancelled');
      expect(make(BookingStatus.rejected).subLabel, 'Declined');
    });

    test('an unrecognised status does not render as something reassuring', () {
      final b = Booking.fromDoc('x', {
        'instructorId': trainer, 'kiterId': rider, 'date': '2099-01-01',
        'status': 'teleported',
      });
      expect(b.status, BookingStatus.unknown);
      expect(b.subLabel, 'Unknown');
    });
  });

  group('adversarial — state moved under the actor', () {
    test('approving a booking the rider already cancelled still lands',
        () async {
      // ORDERING. The trainer's list is a stream; they can tap approve on a
      // row the rider cancelled a moment earlier. Nothing prevents it, so
      // both parties end up looking at a confirmed session neither wants.
      final id = await request();
      await repo.cancelByRider(await asRider(id));
      final stale = await asTrainer(id); // read before, acted on after

      await repo.setStatus(stale, BookingStatus.confirmed);

      await expectBothSee(id, BookingStatus.confirmed);
      expect((await inbox(rider)).any((n) => n.title == 'Booking approved ✅'),
          isTrue,
          reason: 'BUG-013: a cancelled booking was resurrected by an '
              'in-flight approval, and the rider was told it was confirmed');
    });

    test('a rider can cancel a session that already happened, and it leaves '
        'the trainers earnings', () async {
      // BUG-014. `cancelByRider` writes unconditionally, and earnings are
      // Σ totalPrice over *completed* bookings — so cancelling a delivered,
      // settled session silently removes it from the trainer's revenue.
      // Pinned as current behaviour, not asserted as intended.
      final id = await request(hours: ['10:00', '11:00']); // 2h × €50
      await repo.setStatus(await asTrainer(id), BookingStatus.confirmed);
      await repo.setStatus(await asTrainer(id), BookingStatus.completed);
      await repo.markPaid(id, trainerId: trainer);

      Future<double> earnings() async => (await repo
              .watchTrainerBookings(trainer)
              .first)
          .where((b) => b.status == BookingStatus.completed)
          .fold<double>(0, (acc, b) => acc + (b.totalPrice ?? 0));

      expect(await earnings(), 100);

      await repo.cancelByRider(await asRider(id));

      await expectBothSee(id, BookingStatus.cancelled);
      expect(await earnings(), 0,
          reason: 'BUG-014: €100 of delivered, paid work vanished from the '
              'trainer’s earnings because the rider cancelled afterwards');
    });

    test('a booking whose trainer account is gone still resolves', () async {
      // EMPTY. The rider must not lose their history because the other party
      // deleted their account.
      final id = await request();
      await db.collection(Col.users).doc(trainer).delete();

      final b = await asRider(id);
      expect(b.id, id);
      expect(b.instructorName, 'Anna',
          reason: 'the name is denormalised onto the booking for exactly this');
    });
  });
}
