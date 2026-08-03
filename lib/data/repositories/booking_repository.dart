import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/utils/date_x.dart';
import '../firestore_paths.dart';
import '../models/booking.dart';
import '../models/catalogue.dart';
import 'notification_repository.dart';

/// Someone else took the hour (or seat) between the rider's tap and the
/// write (§8.6).
class SlotTakenFailure implements Exception {
  const SlotTakenFailure(this.slots);
  final List<String> slots;
  @override
  String toString() =>
      'Those hours were just taken. Pick a different time.';
}

class BookingRepository {
  BookingRepository(this._db, this._notifications);
  final FirebaseFirestore _db;
  final NotificationRepository _notifications;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(Col.bookings);

  Booking _fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      Booking.fromDoc(doc.id, doc.data() ?? const {});

  // ── Streams ────────────────────────────────────────────────────────────

  Stream<Booking?> watchBooking(String id) =>
      _col.doc(id).snapshots().map((d) => d.exists ? _fromDoc(d) : null);

  /// Client-side sort by date desc (§6.2) — server-side would need an index.
  Stream<List<Booking>> watchRiderBookings(String uid) =>
      _col.where('kiterId', isEqualTo: uid).snapshots().map(_sortDesc);

  Stream<List<Booking>> watchTrainerBookings(String uid) =>
      _col.where('instructorId', isEqualTo: uid).snapshots().map(_sortDesc);

  Stream<List<Booking>> watchDayBookings(String instructorId, String date) =>
      _col
          .where('instructorId', isEqualTo: instructorId)
          .where('date', isEqualTo: date)
          .snapshots()
          .map((qs) => [for (final d in qs.docs) _fromDoc(d)]);

  List<Booking> _sortDesc(QuerySnapshot<Map<String, dynamic>> qs) {
    final list = [for (final d in qs.docs) _fromDoc(d)];
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  // ── Creation ───────────────────────────────────────────────────────────

  /// Hourly bookings are **checked, not locked**: Firestore transactions
  /// cannot read a query, so we re-query the day right before writing and
  /// throw [SlotTakenFailure] on a clash. Two simultaneous confirms both land
  /// as pending and the trainer declines one (§8.6).
  Future<void> _assertSlotsFree(
      String instructorId, String date, List<Slot> wanted,
      {String? ignoreBookingId}) async {
    final qs = await _col
        .where('instructorId', isEqualTo: instructorId)
        .where('date', isEqualTo: date)
        .get();
    final taken = <String>{};
    for (final doc in qs.docs) {
      if (doc.id == ignoreBookingId) continue;
      final b = _fromDoc(doc);
      if (!b.status.isLive) continue;
      taken.addAll([for (final s in b.occupiedSlots) s.value]);
    }
    final clash = [for (final s in wanted) if (taken.contains(s.value)) s.value];
    if (clash.isNotEmpty) throw SlotTakenFailure(clash);
  }

  /// Rider booking. Every rider booking is created `pending`.
  ///
  /// v2.6 dual-wrote legacy + modern field names (`time`/`startTime`,
  /// `price`/`totalPrice`, `type`/`bookingType`, `guestId`/`kiterId`) because
  /// a web client shared the database. This app is now the sole writer, so
  /// one canonical name each.
  Future<String> createBooking({
    required BookingTarget target,
    required String riderUid,
    required String riderName,
    required String riderLevel,
    required String date,
    required List<Slot> slots,
    required bool gearNeeded,
    String? message,
    int bufferMinutes = 60,
  }) async {
    if (slots.isEmpty) {
      throw ArgumentError('Select at least one hour.');
    }
    final sorted = [...slots]..sort((a, b) => a.minutesOfDay - b.minutesOfDay);
    final start = sorted.first;
    final hours = sorted.length;
    final window =
        BookingMath.window(start, hours, bufferMinutes: bufferMinutes);
    if (!window.isValid) throw ArgumentError(window.error!);

    await _assertSlotsFree(target.providerId, date, sorted);

    final total = target.rate * hours;
    final doc = _col.doc();
    final title = target.subTarget != null
        ? '${target.title} — ${target.subTarget}'
        : target.title;
    await doc.set({
      'id': doc.id,
      'instructorId': target.providerId,
      'instructorName': target.title,
      'kiterId': riderUid,
      'studentName': riderName,
      'studentLevel': riderLevel,
      'listingTitle': title,
      if (target.subTarget != null) 'subTarget': target.subTarget,
      'date': date,
      'startTime': start.value,
      'endTime': window.end.value,
      'bufferedEndTime': window.bufferedEnd.value,
      'selectedTimes': [for (final s in sorted) s.value],
      'durationHours': hours,
      'totalPrice': total,
      'type': target.bookingType,
      'gearNeeded': gearNeeded,
      'message': message ?? '',
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });

    await _notifications.notify(
      targetUserId: target.providerId,
      title: 'New booking request',
      message: '$riderName requested ${prettyYmd(date)} at ${start.value}.',
      type: 'booking_request',
      bookingId: doc.id,
    );
    return doc.id;
  }

  /// Trainer walk-in — same shape, confirmed immediately, never notifies
  /// (`manual_entry` has no account behind it) (§6.3, §11.1).
  Future<void> createWalkIn({
    required String instructorId,
    required String instructorName,
    required String studentName,
    required String date,
    required Slot start,
    required int durationHours,
    required double totalPrice,
    int bufferMinutes = 60,
  }) async {
    final window =
        BookingMath.window(start, durationHours, bufferMinutes: bufferMinutes);
    if (!window.isValid) throw ArgumentError(window.error!);
    final slots = [for (var i = 0; i < durationHours; i++) start.plusHours(i)];
    await _assertSlotsFree(instructorId, date, slots);

    final doc = _col.doc();
    await doc.set({
      'id': doc.id,
      'instructorId': instructorId,
      'instructorName': instructorName,
      'kiterId': 'manual_entry',
      'studentName': studentName,
      'studentLevel': 'Walk-in',
      'listingTitle': 'Private lesson (walk-in)',
      'date': date,
      'startTime': start.value,
      'endTime': window.end.value,
      'bufferedEndTime': window.bufferedEnd.value,
      'selectedTimes': [for (final s in slots) s.value],
      'durationHours': durationHours,
      'totalPrice': totalPrice,
      'type': 'manual',
      'gearNeeded': false,
      'message': '',
      'status': 'confirmed',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Safari seats ARE transactional — the seat count lives on one known
  /// document, so the transaction re-reads capacity (§8.6).
  Future<void> reserveSafariSeat({
    required SafariTrip trip,
    required String hostName,
    required String riderUid,
    required String riderName,
  }) async {
    final tripRef = _db.collection(Col.safariTrips).doc(trip.id);
    final bookingRef = _col.doc();
    await _db.runTransaction((tx) async {
      final snap = await tx.get(tripRef);
      final data = snap.data() ?? const <String, dynamic>{};
      final capacity = (data['capacity'] as num?)?.toInt() ?? trip.capacity;
      final booked = (data['bookedSeats'] as num?)?.toInt() ?? 0;
      if (capacity > 0 && booked >= capacity) {
        throw const SlotTakenFailure(['seat']);
      }
      final newBooked = booked + 1;
      tx.update(tripRef, {
        'bookedSeats': newBooked,
        'status': newBooked >= capacity ? 'full' : 'open',
      });
      tx.set(bookingRef, {
        'id': bookingRef.id,
        'instructorId': trip.hostId,
        'instructorName': hostName,
        'kiterId': riderUid,
        'studentName': riderName,
        'studentLevel': 'Rider',
        'tripId': trip.id,
        'tripTitle': trip.title,
        'listingTitle': 'Expedition: ${trip.title}',
        'date': trip.startDate ?? todayYmd(),
        'durationHours': 0,
        'totalPrice': trip.price,
        'type': 'safari',
        'gearNeeded': false,
        'message': '',
        'status': 'confirmed',
        // `paymentStatus: 'paid'` dropped — it was a legacy no-op (§1).
        // Nothing is ever charged in the app; prices settle in person.
        'createdAt': FieldValue.serverTimestamp(),
      });
    });

    await _notifications.notify(
      targetUserId: trip.hostId,
      title: 'New safari booking 🛥️',
      message: '$riderName reserved a seat on ${trip.title}.',
      type: 'booking_confirmed',
      bookingId: bookingRef.id,
    );
  }

  // ── Status transitions ─────────────────────────────────────────────────

  /// Approve / decline / complete, with the matching rider notification.
  /// Returns early for manual bookings or an empty kiterId (§11.1).
  Future<void> setStatus(Booking booking, BookingStatus status,
      {String? declineReason}) async {
    await _col.doc(booking.id).update({
      'status': status.wire,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (booking.isManual || booking.kiterId.isEmpty) return;

    switch (status) {
      case BookingStatus.confirmed:
        await _notifications.notify(
          targetUserId: booking.kiterId,
          title: 'Booking approved ✅',
          message:
              'Your session on ${prettyYmd(booking.date)} is confirmed.',
          type: 'booking_confirmed',
          bookingId: booking.id,
        );
      case BookingStatus.rejected:
        final reason = (declineReason ?? '').trim();
        await _notifications.notify(
          targetUserId: booking.kiterId,
          title: 'Booking declined',
          message:
              'Your request for ${prettyYmd(booking.date)} was declined.'
              '${reason.isEmpty ? '' : ' Reason: $reason'}',
          type: 'booking_rejected',
          bookingId: booking.id,
        );
      case BookingStatus.cancelled:
        await _notifications.notify(
          targetUserId: booking.kiterId,
          title: 'Booking cancelled',
          message:
              'Your session on ${prettyYmd(booking.date)} was cancelled.',
          type: 'booking_cancelled',
          bookingId: booking.id,
        );
      case BookingStatus.completed:
        await _notifications.notify(
          targetUserId: booking.kiterId,
          title: 'Session complete 🎉',
          message: 'Hope it was a good one. Tap to rate your trainer.',
          type: 'review',
          bookingId: booking.id,
        );
      case _:
        break;
    }
  }

  /// Rider cancel — releases a safari seat too, and tells the trainer (§6.3).
  Future<void> cancelByRider(Booking booking) async {
    await _col.doc(booking.id).update({
      'status': 'cancelled',
      'cancelledAt': FieldValue.serverTimestamp(),
      'cancelledBy': 'user',
    });
    if (booking.isSafari && booking.tripId != null) {
      await _db.collection(Col.safariTrips).doc(booking.tripId!).update({
        'bookedSeats': FieldValue.increment(-1),
        'status': 'open',
      });
    }
    await _notifications.notify(
      targetUserId: booking.instructorId,
      title: 'Rider cancelled ⚠️',
      message:
          '${booking.studentName} cancelled ${booking.title} on ${prettyYmd(booking.date)}.',
      type: 'booking_cancelled',
      bookingId: booking.id,
    );
  }

  /// The trainer's scan — presence proven, session starts (§6.3).
  Future<void> checkIn(String bookingId) => _col.doc(bookingId).update({
        'status': 'in_progress',
        'checkedIn': true,
        'startedAt': FieldValue.serverTimestamp(),
      });

  /// Per-side history hiding.
  Future<void> hide(String bookingId, {required bool asInstructor}) =>
      _col.doc(bookingId).update(
          {asInstructor ? 'hiddenByInstructor' : 'hiddenByGuest': true});
}
