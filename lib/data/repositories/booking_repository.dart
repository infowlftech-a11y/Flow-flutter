import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/utils/date_x.dart';
import '../../core/utils/doc_x.dart';
import '../firestore_paths.dart';
import '../models/booking.dart';
import '../models/catalogue.dart';
import '../models/payment.dart';
import '../models/schedule.dart';
import 'notification_repository.dart';

/// Someone else took the hour (or seat) between the rider's tap and the
/// write (§8.6).
class SlotTakenFailure implements Exception {
  const SlotTakenFailure(this.slots, {this.message = _taken});
  static const _taken = 'Those hours were just taken. Pick a different time.';

  final List<String> slots;

  /// User-facing wording — the reason differs (taken vs. too late) but every
  /// caller recovers the same way, so they stay one catchable type.
  final String message;

  @override
  String toString() => message;
}

/// A scanned ticket that cannot start a session (§6.3).
///
/// Carries the reason so the trainer is told *why* the scan bounced —
/// "cancelled" and "that's for Thursday" call for very different responses
/// on a beach.
class CheckInFailure implements Exception {
  const CheckInFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A settlement was refused.
///
/// Separate from [CheckInFailure] because the recoveries differ: a bounced
/// scan means "try again or check the ticket", a refused settlement means
/// money is involved and the trainer needs the specific reason.
class PaymentFailure implements Exception {
  const PaymentFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The booking moved on before this write landed (§8.7).
///
/// Both lists are live streams, so a control can be tapped on a row that has
/// already changed underneath. Two things went wrong while that was
/// unguarded: an approval tapped just after the rider cancelled resurrected
/// the booking as `confirmed` and told the rider it was on, and a rider
/// cancelling a session that had already been delivered and settled took it
/// out of `completed` — and so out of the trainer's earnings, which are a sum
/// over exactly that status.
///
/// Distinct from the others because the recovery is neither "retry" nor
/// "check the ticket": the caller's copy is simply stale, and the fix is to
/// look again.
class StatusConflictFailure implements Exception {
  const StatusConflictFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The same-day lead-time cutoff moved past a selected hour while the rider
/// had the sheet open (§8.2). A subclass so existing `on SlotTakenFailure`
/// handlers keep working — they already clear the selection, which is the
/// right recovery here too.
class LeadTimeFailure extends SlotTakenFailure {
  const LeadTimeFailure(super.slots)
      : super(
          message: 'That hour is too close to now. Pick a later time.',
        );
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

  /// The `availability` doc a live booking maintains for its hours (§8.5).
  ///
  /// Keyed by the booking's own id, so it is addressable without a query:
  /// the delete in [_writeIfLive] and the rules' `getAfter` both depend on
  /// that. `status: 'occupied'` is the half of §8.5 nothing wrote — blocks
  /// were only ever `host-blocked` — and it is what lets the booking grid and
  /// the clash check run against `availability`, which any signed-in user may
  /// read, instead of `bookings`, which only the two parties may. The doc
  /// carries the hours and nothing else: no rider name, no message, no price.
  DocumentReference<Map<String, dynamic>> _occupiedRef(String bookingId) =>
      _db.collection(Col.availability).doc(bookingId);

  Map<String, dynamic> _occupiedDoc({
    required String instructorId,
    required String date,
    required Slot start,
    required Slot end,
  }) =>
      {
        'instructorId': instructorId,
        'date': date,
        'startTime': start.value,
        'endTime': end.value,
        'status': 'occupied',
        'label': 'Booked',
        'createdAt': FieldValue.serverTimestamp(),
      };

  /// Hourly bookings are **checked, not locked**: Firestore transactions
  /// cannot read a query, so we re-query the day right before writing and
  /// throw [SlotTakenFailure] on a clash. Two simultaneous confirms both land
  /// as pending and the trainer declines one (§8.6).
  ///
  /// Reads both calendars and lets the more informed one win.
  ///
  /// The day's bookings are authoritative — but readable only by their own
  /// two parties (BUG-017), so for a rider that query is refused wholesale
  /// and no rider ever completed a booking against live Firestore. The
  /// `availability` docs are the answer anyone may read: host blocks, plus
  /// the `occupied` doc every live booking maintains. Where the bookings
  /// query *was* readable, a booking speaks for itself and its occupied doc
  /// is ignored — a status written around the repository (staff consoles,
  /// tests) must still release the hours even if the doc lingers.
  ///
  /// Host blocks joining the check is deliberate: one added between the grid
  /// snapshot and the confirm used to slip through, because the re-check
  /// only looked at bookings (§8.6).
  Future<void> _assertSlotsFree(
      String instructorId, String date, List<Slot> wanted,
      {String? ignoreBookingId}) async {
    final taken = <String>{};
    final visible = <String>{};
    try {
      final qs = await _col
          .where('instructorId', isEqualTo: instructorId)
          .where('date', isEqualTo: date)
          .get();
      for (final doc in qs.docs) {
        visible.add(doc.id);
        if (doc.id == ignoreBookingId) continue;
        final b = _fromDoc(doc);
        if (!b.status.isLive) continue;
        taken.addAll([for (final s in b.occupiedSlots) s.value]);
      }
    } on FirebaseException catch (e) {
      // The rider's case, by design, not an outage — fall through to the
      // occupied docs. Anything else is a real failure.
      if (e.code != 'permission-denied') rethrow;
    }

    final blocksQs = await _db
        .collection(Col.availability)
        .where('instructorId', isEqualTo: instructorId)
        .where('date', isEqualTo: date)
        .get();
    for (final doc in blocksQs.docs) {
      if (doc.id == ignoreBookingId) continue;
      final block = Availability.fromDoc(doc.id, doc.data());
      if (!block.blocksCalendar) continue;
      // An occupied doc is keyed by its booking's id. If that booking was
      // readable above, its own status has already decided these hours.
      if (block.status == 'occupied' && visible.contains(doc.id)) continue;
      taken.addAll([for (final s in block.expandBlock()) s.value]);
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
    // §8.4 — the hours must be one unbroken run. The grid's _tapSlot enforces
    // this, but a write has to hold its own invariants: ['10:00', '15:00']
    // used to be accepted and recorded as endTime 12:00, a booking whose
    // range disagrees with the hours it holds (BUG-015) — and the occupied
    // availability doc below is a single range, so it *depends* on this.
    for (var i = 1; i < sorted.length; i++) {
      if (sorted[i].minutesOfDay - sorted[i - 1].minutesOfDay != 60) {
        throw ArgumentError('Selected hours must be consecutive.');
      }
    }
    final start = sorted.first;
    final hours = sorted.length;
    final window =
        BookingMath.window(start, hours, bufferMinutes: bufferMinutes);
    if (!window.isValid) throw ArgumentError(window.error!);

    // The grid greys out "too soon" hours from the availability snapshot, so
    // that set is only as fresh as the last stream emission. A rider who
    // opens the sheet at 09:50 and confirms at 10:10 gets no new snapshot to
    // redraw it, and would book 11:00 with under an hour's notice. The clash
    // re-check below already closes this gap for hours someone else took;
    // the lead time needs the same treatment (§8.2, §8.6).
    final tooSoon = BookingMath.pastSlots(date);
    final late = [for (final s in sorted) if (tooSoon.contains(s)) s.value];
    if (late.isNotEmpty) throw LeadTimeFailure(late);

    await _assertSlotsFree(target.providerId, date, sorted);

    final total = target.rate * hours;
    final doc = _col.doc();
    final title = target.subTarget != null
        ? '${target.title} — ${target.subTarget}'
        : target.title;
    // One atomic commit: the booking and its occupied doc must never exist
    // without each other, and the rules authorise the rider's occupied-doc
    // write by reading the booking in the same commit (getAfter).
    final batch = _db.batch();
    batch.set(doc, {
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
      // Payment is recorded from the first write, not bolted on at the end:
      // a booking that exists without an amount owed is a booking nobody can
      // reconcile later.
      ...PaymentInfo.initialFields(amount: total),
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(
        _occupiedRef(doc.id),
        _occupiedDoc(
          instructorId: target.providerId,
          date: date,
          start: start,
          end: window.end,
        ));
    await batch.commit();

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
    // `window` only rejects a *midnight* overflow, which 17:00 + 4h clears
    // comfortably — the real bound is the 18:00 close (§8.1).
    if (!BookingMath.fitsInDay(start, durationHours)) {
      throw ArgumentError(
          'A session must finish by ${BookingMath.lastHour}:00.');
    }
    final slots = [for (var i = 0; i < durationHours; i++) start.plusHours(i)];
    await _assertSlotsFree(instructorId, date, slots);

    final doc = _col.doc();
    final batch = _db.batch();
    batch.set(doc, {
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
      ...PaymentInfo.initialFields(amount: totalPrice),
      'createdAt': FieldValue.serverTimestamp(),
    });
    // A walk-in holds hours like any other booking, and with bookings private
    // the occupied doc is the only way another rider's grid can see them.
    batch.set(
        _occupiedRef(doc.id),
        _occupiedDoc(
          instructorId: instructorId,
          date: date,
          start: start,
          end: window.end,
        ));
    await batch.commit();
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
      // Tolerant readers, not raw casts: a `capacity` the web client wrote as
      // "12" would throw a TypeError inside the transaction and surface as a
      // generic failure (§5).
      final capacity = data.integer('capacity') ?? trip.capacity;
      final booked = data.integer('bookedSeats') ?? 0;
      if (capacity > 0 && booked >= capacity) {
        throw const SlotTakenFailure(['seat']);
      }
      final newBooked = booked + 1;
      tx.update(tripRef, {
        'bookedSeats': newBooked,
        // `capacity <= 0` means "uncapped" everywhere else — SafariTrip's
        // isSoldOut and fillRatio both guard on it. Without the same guard
        // here, `1 >= 0` marks an uncapped trip full on its first booking.
        'status': capacity > 0 && newBooked >= capacity ? 'full' : 'open',
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
        // v2.6 wrote `paymentStatus: 'paid'` here, which was a lie: nothing
        // had been charged. A seat is now recorded as owed like everything
        // else, and the host settles it when the rider turns up.
        ...PaymentInfo.initialFields(amount: trip.price),
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

  /// Statuses nothing moves out of.
  ///
  /// `confirmed` is deliberately absent: the approve toast has no confirm
  /// dialog, only an UNDO, and that UNDO writes `confirmed -> pending`
  /// (§10.4). Catching it here would break the one control that depends on
  /// being reversible.
  static const _terminal = {
    BookingStatus.completed,
    BookingStatus.cancelled,
    BookingStatus.rejected,
  };

  /// Applies [data] only if the booking has not already reached a terminal
  /// state, with the read and the write in one transaction.
  ///
  /// Both lists are live streams, so the caller's copy can be stale by the
  /// time they act on it. `markPaid`, `markRefunded` and `checkIn` have always
  /// re-read state before writing; `setStatus` and `cancelByRider` moved the
  /// same document with a bare `update` and did not.
  /// Returns false when the booking was already in [target] and nothing was
  /// written, so the caller can skip the notification that would otherwise
  /// announce a change that did not happen.
  Future<bool> _writeIfLive(
          String bookingId, BookingStatus target, Map<String, dynamic> data) =>
      _db.runTransaction((tx) async {
        final ref = _col.doc(bookingId);
        final snap = await tx.get(ref);
        if (!snap.exists) {
          throw const StatusConflictFailure('That booking no longer exists.');
        }
        // A terminal transition releases the booking's occupied doc (§8.5).
        // Read before any write — a transaction demands that order — and only
        // delete what exists: bookings written before the occupied docs did
        // have none, and their cancel must still land.
        final occupied = _terminal.contains(target)
            ? await tx.get(_occupiedRef(bookingId))
            : null;
        final current = BookingStatus.parse(snap.data()?.str('status'));
        // Asking for the state it is already in is a retry, not a conflict:
        // a cancel issued from two screens, or one that had actually landed.
        // The same reading `markPaid` takes of a second settlement — and the
        // reason the safari seat count cannot be decremented twice.
        if (current == target) return false;
        if (_terminal.contains(current)) {
          throw StatusConflictFailure(switch (current) {
            BookingStatus.completed => 'That session is already finished.',
            BookingStatus.cancelled => 'That booking was cancelled.',
            BookingStatus.rejected => 'That booking was already declined.',
            _ => 'That booking has already moved on.',
          });
        }
        tx.update(ref, data);
        if (occupied != null && occupied.exists) {
          tx.delete(_occupiedRef(bookingId));
        }
        return true;
      });

  /// Approve / decline / complete, with the matching rider notification.
  /// Returns early for manual bookings or an empty kiterId (§11.1).
  ///
  /// Throws [StatusConflictFailure] if the booking has already finished, been
  /// cancelled or been declined — the notification below is sent only when the
  /// write actually lands, so a refused approval cannot tell the rider their
  /// session is on.
  Future<void> setStatus(Booking booking, BookingStatus status,
      {String? declineReason}) async {
    final written = await _writeIfLive(booking.id, status, {
      'status': status.wire,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (!written) return;

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

  // ── Settlement ─────────────────────────────────────────────────────────

  /// Records that the trainer has been paid.
  ///
  /// Written by the *trainer*, never the rider — the rules enforce it, and
  /// they must, because a rider who could set their own booking to `paid`
  /// could walk off the beach owing money with the app agreeing they did not.
  ///
  /// Transactional so a double tap (or two devices) cannot overwrite a
  /// settlement that already happened with a second, later `paidAt`.
  Future<void> markPaid(
    String bookingId, {
    required String trainerId,
    PaymentMethod method = PaymentMethod.cash,
    String? reference,
  }) async {
    final ref = _col.doc(bookingId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) {
        throw const PaymentFailure('That booking no longer exists.');
      }
      final data = snap.data() ?? const <String, dynamic>{};
      if (data.str('instructorId') != trainerId) {
        throw const PaymentFailure('Only the trainer can settle a session.');
      }
      final current = PaymentStatus.parse(data.str('paymentStatus'));
      if (current == PaymentStatus.paid) {
        // Idempotent, not an error — the money arrived either way.
        return;
      }
      if (current == PaymentStatus.refunded) {
        throw const PaymentFailure(
            'That session was refunded. Reopen it before taking payment.');
      }
      tx.update(ref, {
        'paymentStatus': PaymentStatus.paid.wire,
        'paymentMethod': method.wire,
        'paidAt': FieldValue.serverTimestamp(),
        'paymentRef': ?reference,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Reverses a settlement.
  ///
  /// Deliberately keeps `paidAt` rather than deleting it: a refund is a second
  /// event, not the erasure of the first, and a ledger that forgets it was
  /// ever paid cannot be reconciled against a till.
  Future<void> markRefunded(
    String bookingId, {
    required String trainerId,
  }) async {
    final ref = _col.doc(bookingId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) {
        throw const PaymentFailure('That booking no longer exists.');
      }
      final data = snap.data() ?? const <String, dynamic>{};
      if (data.str('instructorId') != trainerId) {
        throw const PaymentFailure('Only the trainer can refund a session.');
      }
      tx.update(ref, {
        'paymentStatus': PaymentStatus.refunded.wire,
        'refundedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Rider cancel — releases a safari seat too, and tells the trainer (§6.3).
  ///
  /// Throws [StatusConflictFailure] on a session that has already finished:
  /// earnings are a sum over `completed` bookings, so cancelling a delivered,
  /// settled lesson used to take the money off the trainer's books while
  /// `paidAt` stayed on the document.
  Future<void> cancelByRider(Booking booking) async {
    final written = await _writeIfLive(booking.id, BookingStatus.cancelled, {
      'status': 'cancelled',
      'cancelledAt': FieldValue.serverTimestamp(),
      'cancelledBy': 'user',
    });
    // A cancel that had already landed releases no second seat and sends no
    // second warning to the trainer.
    if (!written) return;
    if (booking.isSafari && booking.tripId != null) {
      final tripRef = _db.collection(Col.safariTrips).doc(booking.tripId!);
      await _db.runTransaction((tx) async {
        final snap = await tx.get(tripRef);
        final booked = snap.data()?.integer('bookedSeats') ?? 0;
        tx.update(tripRef, {
          // Floored at zero. `increment(-1)` is unconditional, so cancelling
          // from two screens — or retrying a cancel that had actually landed
          // — drove the count negative, and seatsLeft then over-reports free
          // seats because it clamps against a now-inflated remainder.
          'bookedSeats': booked > 0 ? booked - 1 : 0,
          'status': 'open',
        });
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
  ///
  /// Validated inside a transaction. The QR payload is rendered by the
  /// *rider's* device, so the `trainerId` it carries proves nothing; the
  /// authoritative check is against the stored `instructorId`. A blind
  /// `update` here let a scanned ticket:
  ///   * resurrect a booking the rider had already cancelled — back to
  ///     `in_progress`, re-holding its calendar hours and re-entering
  ///     earnings when finished;
  ///   * rewind a `completed` session, or start one still `pending`;
  ///   * start a booking dated next week, which the Today manifest never
  ///     lists and the trainer therefore has no way to finish — it holds its
  ///     hours forever.
  /// A stale ticket is a screenshot away, so none of these need bad intent.
  Future<void> checkIn(String bookingId, {required String trainerId}) async {
    final ref = _col.doc(bookingId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) {
        throw const CheckInFailure('That booking no longer exists.');
      }
      final booking = Booking.fromDoc(snap.id, snap.data() ?? const {});

      if (booking.instructorId != trainerId) {
        throw const CheckInFailure('This ticket belongs to another trainer.');
      }
      if (booking.status == BookingStatus.inProgress) {
        throw const CheckInFailure('That session is already running.');
      }
      if (booking.status != BookingStatus.confirmed) {
        throw CheckInFailure(switch (booking.status) {
          BookingStatus.pending =>
            'That request is still waiting for your approval.',
          BookingStatus.cancelled => 'That booking was cancelled.',
          BookingStatus.rejected => 'That booking was declined.',
          BookingStatus.completed => 'That session is already finished.',
          _ => "That booking can't be checked in.",
        });
      }
      if (booking.date != todayYmd()) {
        throw CheckInFailure("That ticket is for ${prettyYmd(booking.date)}.");
      }

      tx.update(ref, {
        'status': 'in_progress',
        'checkedIn': true,
        'startedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Per-side history hiding.
  Future<void> hide(String bookingId, {required bool asInstructor}) =>
      _col.doc(bookingId).update(
          {asInstructor ? 'hiddenByInstructor' : 'hiddenByGuest': true});
}
