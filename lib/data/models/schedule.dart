import '../../core/utils/date_x.dart';
import '../../core/utils/doc_x.dart';
import 'booking.dart';

/// A trainer-blocked hour range (§5.3). `status` is `'host-blocked'`
/// (calendar) or `'occupied'` (legacy toggle); both mean unavailable, and any
/// other status is ignored.
class Availability {
  const Availability({
    required this.id,
    required this.instructorId,
    required this.date,
    required this.startTime,
    this.endTime,
    this.label,
    required this.status,
  });

  final String id;
  final String instructorId;
  final String date;
  final String? startTime;
  final String? endTime;
  final String? label;
  final String status;

  factory Availability.fromDoc(String id, Map<String, dynamic> d) =>
      Availability(
        id: id,
        instructorId: d.str('instructorId') ?? '',
        date: d.str('date') ?? '',
        startTime: d.str('startTime'),
        endTime: d.str('endTime'),
        label: d.str('label'),
        status: d.str('status') ?? '',
      );

  bool get blocksCalendar => status == 'host-blocked' || status == 'occupied';

  /// Hours covered: `[startHour, endHour)`; a block with no distinct end
  /// covers only its start hour.
  Set<Slot> expandBlock() {
    final start = Slot.tryParse(startTime);
    if (start == null) return const {};
    final end = Slot.tryParse(endTime);
    if (end == null || end.hour <= start.hour) return {Slot.fromHour(start.hour)};
    return {for (var h = start.hour; h < end.hour; h++) Slot.fromHour(h)};
  }
}

/// Whole-day time off. `covers` is an inclusive lexicographic comparison —
/// valid because dates are zero-padded `YYYY-MM-DD`.
class Vacation {
  const Vacation({
    required this.id,
    required this.instructorId,
    required this.startDate,
    required this.endDate,
    this.label,
  });

  final String id;
  final String instructorId;
  final String startDate;
  final String endDate;
  final String? label;

  factory Vacation.fromDoc(String id, Map<String, dynamic> d) => Vacation(
        id: id,
        instructorId: d.str('instructorId') ?? '',
        startDate: d.str('startDate') ?? '',
        endDate: d.str('endDate') ?? d.str('startDate') ?? '',
        label: d.str('label'),
      );

  bool covers(String date) =>
      startDate.compareTo(date) <= 0 && endDate.compareTo(date) >= 0;
}

/// Computed availability for one instructor-day — never stored (§5.3, §8.5).
class DayAvailability {
  const DayAvailability({
    required this.date,
    required this.blocked,
    required this.booked,
    required this.onVacation,
    required this.past,
  });

  final String date;
  final Set<Slot> blocked;
  final Set<Slot> booked;
  final bool onVacation;
  final Set<Slot> past;

  factory DayAvailability.compose({
    required String date,
    required List<Availability> blocks,
    required List<Booking> bookings,
    required List<Vacation> vacations,
    DateTime? now,
  }) {
    return DayAvailability(
      date: date,
      blocked: {
        for (final b in blocks)
          if (b.blocksCalendar) ...b.expandBlock(),
      },
      booked: {
        for (final b in bookings)
          if (b.status.isLive) ...b.occupiedSlots,
      },
      onVacation: vacations.any((v) => v.covers(date)),
      past: BookingMath.pastSlots(date, now: now),
    );
  }

  bool isFree(Slot slot) =>
      !onVacation &&
      !blocked.contains(slot) &&
      !booked.contains(slot) &&
      !past.contains(slot);

  /// Precedence: Away → Too soon → Booked → Unavailable (§5.3).
  String? blockedReason(Slot slot) {
    if (onVacation) return 'Away';
    if (past.contains(slot)) return 'Too soon';
    if (booked.contains(slot)) return 'Booked';
    if (blocked.contains(slot)) return 'Unavailable';
    return null;
  }

  bool get fullyBooked => BookingMath.slots().every((s) => !isFree(s));
}
