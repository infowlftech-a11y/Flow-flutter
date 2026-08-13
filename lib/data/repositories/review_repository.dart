import 'package:cloud_firestore/cloud_firestore.dart';

import '../firestore_paths.dart';
import '../models/booking.dart';
import '../models/social.dart';
import 'notification_repository.dart';

class ReviewRepository {
  ReviewRepository(this._db, this._notifications);
  final FirebaseFirestore _db;
  final NotificationRepository _notifications;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(Col.reviews);

  /// Reviews for one trainer — newest first, client-side (§6.2).
  Stream<List<Review>> watchForTrainer(String trainerId) =>
      _col.where('trainerId', isEqualTo: trainerId).snapshots().map((qs) {
        final list = [for (final d in qs.docs) Review.fromDoc(d.id, d.data())];
        list.sort(
          (a, b) => (b.createdAt ?? DateTime(0)).compareTo(
            a.createdAt ?? DateTime(0),
          ),
        );
        return list;
      });

  /// One snapshot of the entire collection, grouped client-side — Explore's
  /// averages (§8.10; a known scaling risk, preserved by design).
  Stream<Map<String, RatingSummary>> watchAllRatings() =>
      _col.snapshots().map((qs) {
        final byTrainer = <String, List<Review>>{};
        for (final d in qs.docs) {
          final r = Review.fromDoc(d.id, d.data());
          if (r.trainerId.isEmpty) continue;
          (byTrainer[r.trainerId] ??= []).add(r);
        }
        return {
          for (final e in byTrainer.entries) e.key: RatingSummary.from(e.value),
        };
      });

  /// The first completed, not-yet-reviewed booking with this trainer — the
  /// composer only renders when this returns non-null (§8.9).
  Future<Booking?> findReviewableBooking({
    required String trainerId,
    required String riderId,
  }) async {
    final bookingsQs = await _db
        .collection(Col.bookings)
        .where('kiterId', isEqualTo: riderId)
        .get();
    final completed =
        [for (final d in bookingsQs.docs) Booking.fromDoc(d.id, d.data())]
            .where(
              (b) =>
                  b.status == BookingStatus.completed &&
                  b.instructorId == trainerId,
            )
            .toList();
    if (completed.isEmpty) return null;

    final reviewsQs = await _col.where('userId', isEqualTo: riderId).get();
    final reviewedBookingIds = {
      for (final d in reviewsQs.docs)
        if ((d.data()['bookingId'] ?? '') is String)
          d.data()['bookingId'] as String,
    };
    for (final b in completed) {
      if (!reviewedBookingIds.contains(b.id)) return b;
    }
    return null;
  }

  /// Independently re-checks for an existing review on that bookingId and
  /// silently no-ops if found — double submission is impossible even by
  /// race (§8.9).
  Future<void> submit({
    required String trainerId,
    required String userId,
    required String userName,
    required int rating,
    String? comment,
    required String bookingId,
  }) async {
    final existing = await _col
        .where('bookingId', isEqualTo: bookingId)
        .limit(1)
        .get();
    if (existing.docs.isNotEmpty) return;
    await _col.add({
      'trainerId': trainerId,
      'userId': userId,
      'userName': userName,
      'rating': rating.clamp(1, 5),
      'comment': (comment ?? '').trim(),
      'bookingId': bookingId,
      'createdAt': FieldValue.serverTimestamp(),
    });
    // Tell the trainer (P2). Fire-and-forget: a review that saved is a
    // review, whether or not this write lands. `bookingId` is load-bearing —
    // the rules only let a rider notify someone they share that booking
    // with, which is exactly what a review is.
    final stars = rating.clamp(1, 5);
    _notifications
        .notify(
          targetUserId: trainerId,
          title: 'New review ⭐',
          message:
              '$userName rated your session $stars star${stars == 1 ? '' : 's'}.'
              '${(comment ?? '').trim().isEmpty ? '' : ' "${comment!.trim()}"'}',
          type: 'review_received',
          bookingId: bookingId,
        )
        .ignore();
  }

  Future<void> delete(String reviewId) => _col.doc(reviewId).delete();
}
