// FLOW 5 — who may review whom, once, and what it does to the rating.
//
// social_model_test.dart covers Review.fromDoc and RatingSummary as models.
// This covers the repository, which is where §8.9's eligibility actually
// lives — and it is the *only* place it lives: firestore.rules pins
// authorship and the 1-5 range and nothing else, deliberately (see BUG-004).
// So every rule below is enforced by this code or by nothing.
//
// Two views resolve from one database:
//
//   rider   → findReviewableBooking(trainerId, riderId)  (is the composer shown)
//   Explore → watchAllRatings()                          (the score on the card)
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flow/data/firestore_paths.dart';
import 'package:flow/data/models/booking.dart';
import 'package:flow/data/models/social.dart';
import 'package:flow/data/repositories/notification_repository.dart';
import 'package:flow/data/repositories/review_repository.dart';

void main() {
  late FakeFirebaseFirestore db;
  late ReviewRepository repo;

  setUp(() {
    db = FakeFirebaseFirestore();
    // P2 (ordered): a submitted review notifies the trainer, so the
    // repository carries the notification writer. Construction only — every
    // assertion in this file is unchanged.
    repo = ReviewRepository(db, NotificationRepository(db));
  });

  const rider = 'rider1';
  const trainer = 'trainer1';
  var seq = 0;

  Future<String> seedBooking({
    BookingStatus status = BookingStatus.completed,
    String kiterId = rider,
    String instructorId = trainer,
  }) async {
    final id = 'b${seq++}';
    await db.collection(Col.bookings).doc(id).set({
      'id': id,
      'instructorId': instructorId,
      'kiterId': kiterId,
      'date': '2026-08-01',
      'startTime': '10:00',
      'endTime': '11:00',
      'status': status.wire,
    });
    return id;
  }

  Future<Booking?> reviewable({String t = trainer, String r = rider}) =>
      repo.findReviewableBooking(trainerId: t, riderId: r);

  Future<RatingSummary?> rating(String t) async =>
      (await repo.watchAllRatings().first)[t];

  group('§8.9 — when the composer appears', () {
    test('never, with no bookings at all', () async {
      expect(await reviewable(), isNull);
    });

    test('after a completed session with that trainer', () async {
      final id = await seedBooking();
      expect((await reviewable())?.id, id);
    });

    for (final s in [
      BookingStatus.pending,
      BookingStatus.confirmed,
      BookingStatus.inProgress,
      BookingStatus.cancelled,
      BookingStatus.rejected,
    ]) {
      test(
        'not for a ${s.wire} booking — only a session that happened',
        () async {
          await seedBooking(status: s);
          expect(await reviewable(), isNull);
        },
      );
    }

    test('not for another riders completed session', () async {
      await seedBooking(kiterId: 'rider2');
      expect(await reviewable(), isNull);
    });

    test('not for a session with a different trainer', () async {
      await seedBooking(instructorId: 'trainer2');
      expect(await reviewable(), isNull);
    });

    test('the right trainer is picked out of a mixed history', () async {
      await seedBooking(instructorId: 'trainer2');
      final mine = await seedBooking();
      await seedBooking(instructorId: 'trainer3');

      expect((await reviewable())?.id, mine);
      expect((await reviewable(t: 'trainer2'))?.id, isNot(mine));
    });
  });

  group('§8.9 — once, and only once', () {
    test('the composer closes after the review lands', () async {
      final id = await seedBooking();
      await repo.submit(
        trainerId: trainer,
        userId: rider,
        userName: 'Seif',
        rating: 5,
        bookingId: id,
      );

      expect(
        await reviewable(),
        isNull,
        reason: 'the booking is now in the reviewed set',
      );
    });

    test('a second completed session re-opens it', () async {
      final first = await seedBooking();
      await repo.submit(
        trainerId: trainer,
        userId: rider,
        userName: 'Seif',
        rating: 5,
        bookingId: first,
      );
      final second = await seedBooking();

      expect(
        (await reviewable())?.id,
        second,
        reason: 'each session earns its own review',
      );
    });

    test(
      'reviewing one trainer does not close the composer for another',
      () async {
        final a = await seedBooking();
        final b = await seedBooking(instructorId: 'trainer2');
        await repo.submit(
          trainerId: trainer,
          userId: rider,
          userName: 'Seif',
          rating: 5,
          bookingId: a,
        );

        expect((await reviewable(t: 'trainer2'))?.id, b);
      },
    );

    test('another riders review does not close mine', () async {
      final mine = await seedBooking();
      final theirs = await seedBooking(kiterId: 'rider2');
      await repo.submit(
        trainerId: trainer,
        userId: 'rider2',
        userName: 'Other',
        rating: 1,
        bookingId: theirs,
      );

      expect((await reviewable())?.id, mine);
    });

    test('submitting twice for the same booking writes one review', () async {
      // The race guard: submit re-checks bookingId independently of
      // findReviewableBooking, so a double tap cannot double-post.
      final id = await seedBooking();
      for (var i = 0; i < 2; i++) {
        await repo.submit(
          trainerId: trainer,
          userId: rider,
          userName: 'Seif',
          rating: 5,
          comment: 'Great',
          bookingId: id,
        );
      }

      expect((await db.collection(Col.reviews).get()).docs, hasLength(1));
    });

    test('the second submit does not overwrite the first', () async {
      final id = await seedBooking();
      await repo.submit(
        trainerId: trainer,
        userId: rider,
        userName: 'Seif',
        rating: 5,
        comment: 'Brilliant',
        bookingId: id,
      );
      await repo.submit(
        trainerId: trainer,
        userId: rider,
        userName: 'Seif',
        rating: 1,
        comment: 'Changed my mind',
        bookingId: id,
      );

      final only = (await repo.watchForTrainer(trainer).first).single;
      expect(only.rating, 5);
      expect(
        only.comment,
        'Brilliant',
        reason: 'silently no-ops, so the first review stands (§8.9)',
      );
    });
  });

  group('what submit writes', () {
    test('the canonical shape (§6.3)', () async {
      final id = await seedBooking();
      await repo.submit(
        trainerId: trainer,
        userId: rider,
        userName: 'Seif',
        rating: 4,
        comment: '  Solid coaching  ',
        bookingId: id,
      );

      final doc = (await db.collection(Col.reviews).get()).docs.single.data();
      expect(doc['trainerId'], trainer);
      expect(doc['userId'], rider);
      expect(doc['userName'], 'Seif');
      expect(doc['rating'], 4);
      expect(doc['bookingId'], id);
      expect(doc['comment'], 'Solid coaching', reason: 'trimmed');
      expect(doc['createdAt'], isNotNull);
    });

    test('a null comment becomes empty, never the string "null"', () async {
      final id = await seedBooking();
      await repo.submit(
        trainerId: trainer,
        userId: rider,
        userName: 'Seif',
        rating: 4,
        bookingId: id,
      );

      expect(
        (await db.collection(Col.reviews).get()).docs.single.data()['comment'],
        '',
      );
    });

    test('a rating above 5 is clamped, not rejected', () async {
      final id = await seedBooking();
      await repo.submit(
        trainerId: trainer,
        userId: rider,
        userName: 'Seif',
        rating: 99,
        bookingId: id,
      );

      expect(
        (await repo.watchForTrainer(trainer).first).single.rating,
        5,
        reason:
            'firestore.rules rejects out-of-range writes outright, so '
            'the clamp is what keeps a UI bug from being a denied write',
      );
    });

    test('a rating below 1 is clamped up', () async {
      final id = await seedBooking();
      await repo.submit(
        trainerId: trainer,
        userId: rider,
        userName: 'Seif',
        rating: 0,
        bookingId: id,
      );

      expect((await repo.watchForTrainer(trainer).first).single.rating, 1);
    });
  });

  group('§8.10 — what it does to the score', () {
    Future<void> review(
      int stars, {
      String t = trainer,
      String by = rider,
    }) async {
      final id = await seedBooking(instructorId: t, kiterId: by);
      await repo.submit(
        trainerId: t,
        userId: by,
        userName: by,
        rating: stars,
        bookingId: id,
      );
    }

    test('an unrated trainer shows 5.0 out of nothing', () async {
      expect(
        await rating(trainer),
        isNull,
        reason:
            'absent from the map entirely — the UI substitutes '
            'RatingSummary.none',
      );
      expect(RatingSummary.none.average, 5.0);
      expect(RatingSummary.none.count, 0);
      expect(RatingSummary.none.display, '5.0');
    });

    test('one review is the average', () async {
      await review(4);
      expect((await rating(trainer))!.average, 4.0);
      expect((await rating(trainer))!.count, 1);
    });

    test('several average, and the display rounds to one place', () async {
      await review(5);
      await review(4, by: 'rider2');
      await review(4, by: 'rider3');

      final r = (await rating(trainer))!;
      expect(r.count, 3);
      expect(r.average, closeTo(4.333, 0.001));
      expect(r.display, '4.3');
    });

    test('a one-star review actually moves it down', () async {
      await review(5);
      await review(1, by: 'rider2');

      expect((await rating(trainer))!.average, 3.0);
    });

    test('ratings are grouped per trainer, not pooled', () async {
      await review(5);
      await review(1, t: 'trainer2', by: 'rider2');

      expect((await rating(trainer))!.average, 5.0);
      expect((await rating('trainer2'))!.average, 1.0);
    });

    test('deleting a review returns the score to the others', () async {
      await review(5);
      await review(1, by: 'rider2');
      expect((await rating(trainer))!.average, 3.0);

      final one = (await repo.watchForTrainer(trainer).first).firstWhere(
        (r) => r.rating == 1,
      );
      await repo.delete(one.id);

      expect((await rating(trainer))!.average, 5.0);
      expect((await rating(trainer))!.count, 1);
    });

    test('deleting the last review drops the trainer from the map', () async {
      await review(5);
      final only = (await repo.watchForTrainer(trainer).first).single;
      await repo.delete(only.id);

      expect(await rating(trainer), isNull);
    });

    test('a review with no trainerId is skipped, not counted as ""', () async {
      // MALFORMED. watchAllRatings groups by trainerId; a blank one would
      // otherwise create a phantom entry under the empty key.
      await db.collection(Col.reviews).add({
        'userId': rider,
        'rating': 5,
        'comment': '',
        'bookingId': 'x',
      });

      expect((await repo.watchAllRatings().first).containsKey(''), isFalse);
    });
  });

  group('the trainers own review list', () {
    test('is newest first', () async {
      for (final (i, stars) in [3, 4, 5].indexed) {
        await db.collection(Col.reviews).add({
          'trainerId': trainer,
          'userId': 'r$i',
          'userName': 'R$i',
          'rating': stars,
          'comment': '',
          'bookingId': 'b$i',
          'createdAt': Timestamp.fromDate(DateTime(2026, 1, i + 1)),
        });
      }

      final list = await repo.watchForTrainer(trainer).first;
      expect([for (final r in list) r.rating], [5, 4, 3]);
    });

    test(
      'a review with no timestamp sorts last rather than crashing',
      () async {
        await db.collection(Col.reviews).add({
          'trainerId': trainer,
          'userId': 'a',
          'rating': 5,
          'bookingId': 'b1',
          'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
        });
        await db.collection(Col.reviews).add({
          'trainerId': trainer,
          'userId': 'b',
          'rating': 3,
          'bookingId': 'b2',
        });

        final list = await repo.watchForTrainer(trainer).first;
        expect(list, hasLength(2));
        expect(list.last.rating, 3);
      },
    );

    test('only that trainers reviews', () async {
      await db.collection(Col.reviews).add({
        'trainerId': 'trainer2',
        'userId': 'a',
        'rating': 1,
        'bookingId': 'b1',
      });

      expect(await repo.watchForTrainer(trainer).first, isEmpty);
    });
  });

  group('adversarial — eligibility is repository-deep only', () {
    test('submit does not verify the booking exists', () async {
      // Pinned, not asserted as intended. findReviewableBooking is what the
      // UI gates on, but submit itself takes bookingId on trust — and
      // firestore.rules does not check it either (BUG-004). A client talking
      // to Firestore directly can post a review for a session that never
      // happened.
      await repo.submit(
        trainerId: trainer,
        userId: rider,
        userName: 'Seif',
        rating: 5,
        bookingId: 'never-existed',
      );

      expect((await repo.watchForTrainer(trainer).first), hasLength(1));
      expect((await rating(trainer))!.average, 5.0);
    });

    test('submit does not verify the reviewer was the rider', () async {
      final id = await seedBooking(kiterId: 'rider2');
      await repo.submit(
        trainerId: trainer,
        userId: rider,
        userName: 'Seif',
        rating: 1,
        bookingId: id,
      );

      expect(
        (await rating(trainer))!.average,
        1.0,
        reason:
            'the composer would never have opened, but the write '
            'itself is unguarded',
      );
    });

    test(
      'a completed booking still reviewable after the trainer is deleted',
      () async {
        final id = await seedBooking();
        await db.collection(Col.users).doc(trainer).delete();

        expect(
          (await reviewable())?.id,
          id,
          reason: 'the booking carries the trainer id; no profile read',
        );
      },
    );
  });

  // ── P2: the trainer hears about the review ──────────────────────────────
  group('P2 — a submitted review notifies the trainer', () {
    Future<List<Map<String, dynamic>>> notifications() async => [
      for (final d in (await db.collection(Col.notifications).get()).docs)
        d.data(),
    ];

    test('writes review_received with the shared booking attached', () async {
      final id = await seedBooking();
      await repo.submit(
        trainerId: trainer,
        userId: rider,
        userName: 'Seif',
        rating: 5,
        comment: 'Great wind, great coach',
        bookingId: id,
      );
      // The notify is fire-and-forget by design — a saved review must not
      // hang on it — so give the queue one turn before reading.
      await pumpEventQueue();

      final n = (await notifications()).single;
      expect(n['targetUserId'], trainer);
      expect(n['type'], 'review_received');
      expect(
        n['bookingId'],
        id,
        reason:
            'the rules only let a rider notify someone across a '
            'shared booking — the id is the permission',
      );
      expect(n['message'], contains('5 stars'));
      expect(n['message'], contains('Great wind'));
    });

    test('the double-submit guard also means no second notification', () async {
      final id = await seedBooking();
      for (var i = 0; i < 2; i++) {
        await repo.submit(
          trainerId: trainer,
          userId: rider,
          userName: 'Seif',
          rating: 4,
          bookingId: id,
        );
      }
      await pumpEventQueue();

      expect(await notifications(), hasLength(1));
    });
  });
}
