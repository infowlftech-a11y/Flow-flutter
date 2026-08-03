import 'package:flutter_test/flutter_test.dart';

import 'package:flow/core/utils/date_x.dart';
import 'package:flow/data/models/booking.dart';
import 'package:flow/data/models/schedule.dart';

void main() {
  group('Slot', () {
    test('parses H:mm and HH:mm, rejects invalid', () {
      expect(Slot.tryParse('9:30')?.value, '09:30');
      expect(Slot.tryParse('09:30 extra')?.value, '09:30');
      expect(Slot.tryParse('24:00'), isNull);
      expect(Slot.tryParse('10:61'), isNull);
    });

    test('arithmetic and overflow', () {
      expect(const Slot('17:00').plusHours(1).value, '18:00');
      expect(const Slot('23:30').overflowsDay(45), isTrue);
    });
  });

  group('BookingMath', () {
    test('exactly 10 bookable slots, 08:00–17:00', () {
      final slots = BookingMath.slots();
      expect(slots.length, 10);
      expect(slots.first.value, '08:00');
      expect(slots.last.value, '17:00');
    });

    test('same-day lead time: at 09:30 the first bookable hour is 11:00', () {
      final now = DateTime(2026, 8, 2, 9, 30);
      final past = BookingMath.pastSlots(ymd(now), now: now);
      expect(past.contains(const Slot('10:00')), isTrue);
      expect(past.contains(const Slot('11:00')), isFalse);
    });

    test('other days have no past slots', () {
      expect(BookingMath.pastSlots('2099-01-01'), isEmpty);
    });

    test('window flags past-midnight overflow', () {
      final w = BookingMath.window(const Slot('17:00'), 6, bufferMinutes: 90);
      expect(w.isValid, isFalse);
      expect(w.error, 'Booking extends past midnight');
    });
  });

  group('Booking', () {
    test('bucketing: unanswered past request expires to history', () {
      final b = Booking.fromDoc('x', {
        'date': '2020-01-01',
        'status': 'pending',
        'startTime': '09:00',
        'durationHours': 2,
      });
      expect(b.bucket(DateTime(2026)), BookingBucket.history);
      expect(b.subLabel, 'Expired — never confirmed');
    });

    test('no usable time → runs to end of day, never prematurely expired',
        () {
      final b = Booking.fromDoc('x', {
        'date': '2026-08-02',
        'status': 'confirmed',
      });
      expect(b.bucket(DateTime(2026, 8, 2, 12)), BookingBucket.upcoming);
    });

    test('canonical field names parse', () {
      final b = Booking.fromDoc('x', {
        'date': '2026-08-14',
        'status': 'active',
        'instructorId': 'trainer1',
        'kiterId': 'rider1',
        'studentName': 'Lina',
        'startTime': '09:00',
        'totalPrice': 72.5,
        'type': 'lesson',
      });
      expect(b.status, BookingStatus.inProgress);
      expect(b.instructorId, 'trainer1');
      expect(b.kiterId, 'rider1');
      expect(b.studentName, 'Lina');
      expect(b.startTime, '09:00');
      expect(b.totalPrice, 72.5);
    });

    // The legacy web client is gone, so alias spellings are no longer read.
    // Tolerance to *malformed* values is a separate guarantee and survives.
    test('legacy aliases are no longer honoured', () {
      final b = Booking.fromDoc('x', {
        'date': '2026-08-14',
        'status': 'confirmed',
        'stationId': 'station1',
        'guestId': 'rider1',
        'guestName': 'Lina',
        'time': '09:00',
        'price': 90,
      });
      expect(b.instructorId, isEmpty);
      expect(b.kiterId, isEmpty);
      expect(b.studentName, 'Rider');
      expect(b.totalPrice, isNull);
    });

    test('a malformed document still never crashes a screen', () {
      final b = Booking.fromDoc('x', {
        'date': 42,
        'status': {'nope': true},
        'totalPrice': 'not a number',
        'selectedTimes': '09:00',
        'durationHours': '3',
        'gearNeeded': 'true',
      });
      expect(b.status, BookingStatus.unknown);
      expect(b.totalPrice, isNull);
      expect(b.selectedTimes, ['09:00']);
      expect(b.durationHours, 3);
      expect(b.gearNeeded, isTrue);
      expect(b.timeRange, '—');
    });
  });

  group('DayAvailability', () {
    test('blocked reason precedence: Away wins over everything', () {
      final day = DayAvailability.compose(
        date: '2099-01-01',
        blocks: [
          Availability.fromDoc('b1', {
            'instructorId': 't',
            'date': '2099-01-01',
            'startTime': '09:00',
            'endTime': '10:00',
            'status': 'host-blocked',
          }),
        ],
        bookings: const [],
        vacations: [
          Vacation.fromDoc('v1', {
            'instructorId': 't',
            'startDate': '2099-01-01',
            'endDate': '2099-01-02',
          }),
        ],
      );
      expect(day.blockedReason(const Slot('09:00')), 'Away');
      expect(day.isFree(const Slot('12:00')), isFalse);
    });

    test('vacation covers() is inclusive', () {
      final v = Vacation.fromDoc('v', {
        'instructorId': 't',
        'startDate': '2026-08-10',
        'endDate': '2026-08-12',
      });
      expect(v.covers('2026-08-10'), isTrue);
      expect(v.covers('2026-08-12'), isTrue);
      expect(v.covers('2026-08-13'), isFalse);
    });
  });

  group('euro', () {
    test('whole vs fractional display', () {
      expect(euro(120), '€120');
      expect(euro(72.5), '€72.50');
      expect(euro(null), '—');
    });
  });
}
