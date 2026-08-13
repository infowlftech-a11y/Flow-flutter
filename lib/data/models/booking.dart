import '../../core/utils/date_x.dart';
import '../../core/utils/doc_x.dart';
import 'payment.dart';

/// Booking lifecycle (§5.2). `unknown` serialises back to `pending`.
enum BookingStatus {
  pending('pending', 'Pending'),
  confirmed('confirmed', 'Confirmed'),
  inProgress('in_progress', 'Active'),
  completed('completed', 'Completed'),
  cancelled('cancelled', 'Cancelled'),
  rejected('rejected', 'Declined'),
  unknown('pending', 'Unknown');

  const BookingStatus(this.wire, this.label);
  final String wire;
  final String label;

  static BookingStatus parse(String? raw) => switch (raw) {
        'pending' => pending,
        'confirmed' => confirmed,
        'in_progress' || 'active' => inProgress,
        'completed' => completed,
        'cancelled' => cancelled,
        'rejected' => rejected,
        _ => unknown,
      };

  /// Live bookings hold their calendar hours.
  bool get isLive => this == pending || this == confirmed || this == inProgress;
  bool get isDead => this == cancelled || this == rejected;
}

enum BookingBucket { upcoming, active, history }

class Booking {
  const Booking({
    required this.id,
    required this.date,
    required this.status,
    required this.instructorId,
    required this.instructorName,
    required this.kiterId,
    required this.studentName,
    this.studentLevel,
    this.listingTitle,
    this.subTarget,
    this.startTime,
    this.endTime,
    this.bufferedEndTime,
    this.selectedTimes = const [],
    this.durationHours,
    this.totalPrice,
    this.type,
    this.gearNeeded = false,
    this.message,
    this.createdAt,
    this.hiddenByGuest = false,
    this.hiddenByInstructor = false,
    this.reminderSent = false,
    this.checkedIn = false,
    this.tripId,
    this.cancelledAt,
    this.cancelledBy,
    this.payment = PaymentInfo.none,
  });

  final String id;

  /// Local `YYYY-MM-DD`.
  final String date;
  final BookingStatus status;
  final String instructorId;
  final String instructorName;

  /// `'manual_entry'` for walk-ins.
  final String kiterId;
  final String studentName;
  final String? studentLevel;
  final String? listingTitle;

  /// Instructor / service inside a station.
  final String? subTarget;
  final String? startTime;
  final String? endTime;
  final String? bufferedEndTime;
  final List<String> selectedTimes;
  final int? durationHours;
  final double? totalPrice;
  final String? type;
  final bool gearNeeded;
  final String? message;
  final DateTime? createdAt;
  final bool hiddenByGuest;
  final bool hiddenByInstructor;
  final bool reminderSent;
  final bool checkedIn;
  final String? tripId;

  /// Who ended a cancelled booking and when — `'user'` for the rider
  /// (stamped by rules, riderStatusIsCancellation), `'provider'` for the
  /// trainer, `'staff'`/absent otherwise. The cancellation policy derives
  /// the money outcome from exactly these two fields, so a rider cancel
  /// cannot exist without them.
  final DateTime? cancelledAt;
  final String? cancelledBy;

  /// What is owed and whether it has been collected.
  ///
  /// Defaults to [PaymentInfo.none] — status [PaymentStatus.unknown] — for
  /// every booking written before payments were tracked. That is not the same
  /// as unpaid, and the UI treats it differently on purpose.
  final PaymentInfo payment;

  /// Reads the canonical field names only.
  ///
  /// v2.6 accepted several aliases per field (`stationId`, `guestId`,
  /// `guestName`, `serviceName`, `time`, `price`, `bookingType`…) because a
  /// loosely-typed web client had written them over years. This app is the
  /// sole writer now, so each field has one name. The readers stay tolerant
  /// of *malformed* values — a bad type must still never crash a screen
  /// (§5) — just not of legacy spellings.
  factory Booking.fromDoc(String id, Map<String, dynamic> d) => Booking(
        id: id,
        date: d.str('date') ?? '',
        status: BookingStatus.parse(d.str('status')),
        instructorId: d.str('instructorId') ?? '',
        instructorName: d.str('instructorName') ?? '',
        kiterId: d.str('kiterId') ?? '',
        studentName: d.str('studentName') ?? 'Rider',
        studentLevel: d.str('studentLevel'),
        listingTitle: d.strAny(['listingTitle', 'tripTitle']),
        subTarget: d.str('subTarget'),
        startTime: d.str('startTime'),
        endTime: d.str('endTime'),
        bufferedEndTime: d.str('bufferedEndTime'),
        selectedTimes: d.strList('selectedTimes'),
        durationHours: d.integer('durationHours'),
        totalPrice: d.money('totalPrice'),
        type: d.str('type'),
        gearNeeded: d.boolean('gearNeeded'),
        message: d.str('message'),
        createdAt: d.date('createdAt'),
        hiddenByGuest: d.boolean('hiddenByGuest'),
        hiddenByInstructor: d.boolean('hiddenByInstructor'),
        reminderSent: d.boolean('reminderSent'),
        checkedIn: d.boolean('checkedIn'),
        tripId: d.str('tripId'),
        cancelledAt: d.date('cancelledAt'),
        cancelledBy: d.str('cancelledBy'),
        payment: PaymentInfo.fromDoc(d),
      );

  /// What the rider owes, preferring the amount captured at booking time.
  ///
  /// Falls back to `totalPrice` so an older document still reports a figure —
  /// the two agree for anything written since payments were tracked, and the
  /// captured amount is the one that must win if a trainer ever changes their
  /// rate after a booking was made.
  double get amountDue => payment.amount ?? totalPrice ?? 0;

  /// True when this session is finished and the trainer has not been paid.
  ///
  /// [PaymentStatus.unknown] is excluded deliberately: history from before
  /// payment tracking must not be reported as money owed.
  bool get awaitsPayment =>
      status == BookingStatus.completed && payment.isOutstanding;

  /// True when this session is delivered and FLOW is still holding the
  /// rider's money — the escrow payout FLOW owes the trainer (P1).
  bool get awaitsPayout =>
      status == BookingStatus.completed && payment.status.isHeldByApp;

  bool get isManual => kiterId == 'manual_entry' || type == 'manual';
  bool get isSafari => type == 'safari';

  String get title =>
      listingTitle ?? (isSafari ? 'Expedition' : 'Kitesurf lesson');

  /// The hour slots this booking holds on the calendar.
  List<Slot> get occupiedSlots {
    if (selectedTimes.isNotEmpty) {
      return [for (final t in selectedTimes) ?Slot.tryParse(t)];
    }
    final start = Slot.tryParse(startTime);
    if (start == null) return const [];
    final h = hours;
    return [for (var i = 0; i < h; i++) start.plusHours(i)];
  }

  int get hours {
    if (durationHours != null && durationHours! > 0) return durationHours!;
    if (selectedTimes.isNotEmpty) return selectedTimes.length;
    final s = Slot.tryParse(startTime);
    final e = Slot.tryParse(endTime);
    if (s != null && e != null) {
      final diff = (e.minutesOfDay - s.minutesOfDay) ~/ 60;
      if (diff > 0) return diff;
    }
    return 1;
  }

  String get timeRange {
    final s = Slot.tryParse(startTime);
    if (s == null) return '—';
    final e = Slot.tryParse(endTime) ?? s.plusHours(hours);
    return '${s.value}–${e.value}';
  }

  DateTime? get startsAt {
    final day = parseYmd(date);
    final s = Slot.tryParse(startTime);
    if (day == null) return null;
    if (s == null) return day;
    return day.add(Duration(minutes: s.minutesOfDay));
  }

  /// End instant; a booking with no usable time runs to 23:59:59 of its day,
  /// so it is never prematurely "expired" (§8.7).
  DateTime? get endsAt {
    final day = parseYmd(date);
    if (day == null) return null;
    final e = Slot.tryParse(endTime);
    if (e != null) return day.add(Duration(minutes: e.minutesOfDay));
    final s = Slot.tryParse(startTime);
    if (s != null) {
      return day.add(Duration(minutes: s.minutesOfDay + hours * 60));
    }
    return day.add(const Duration(hours: 23, minutes: 59, seconds: 59));
  }

  bool get isPast {
    final e = endsAt;
    return e != null && DateTime.now().isAfter(e);
  }

  BookingBucket bucket([DateTime? nowOverride]) {
    final now = nowOverride ?? DateTime.now();
    if (status == BookingStatus.inProgress) return BookingBucket.active;
    if (status.isDead || status == BookingStatus.completed) {
      return BookingBucket.history;
    }
    final e = endsAt;
    if (e != null && now.isAfter(e)) return BookingBucket.history;
    return BookingBucket.upcoming;
  }

  /// The words under the status pill (§8.7).
  String get subLabel => switch (status) {
        BookingStatus.pending =>
          isPast ? 'Expired — never confirmed' : 'Waiting for trainer',
        BookingStatus.confirmed => isPast ? 'Past session' : 'Approved',
        BookingStatus.inProgress => 'In progress',
        BookingStatus.completed => 'Completed',
        BookingStatus.cancelled => 'Cancelled',
        BookingStatus.rejected => 'Declined',
        BookingStatus.unknown => 'Unknown',
      };
}
