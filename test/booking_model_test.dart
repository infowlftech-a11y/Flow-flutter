// The Booking getters are the arithmetic every screen leans on: which hours a
// booking holds, when it ends, which tab it lands in, what is owed. The
// existing suites exercise the happy paths through the UI; this file pins the
// fallback ladders — the branches that only fire on the malformed or
// half-written documents §5 promises will never crash a screen.
import 'package:flutter_test/flutter_test.dart';

import 'package:flow/data/models/booking.dart';
import 'package:flow/data/models/payment.dart';

Booking make({
  String date = '2099-06-15',
  BookingStatus status = BookingStatus.confirmed,
  String? startTime,
  String? endTime,
  List<String> selectedTimes = const [],
  int? durationHours,
  double? totalPrice,
  String? type,
  String? kiterId,
  String? listingTitle,
  PaymentInfo payment = PaymentInfo.none,
}) =>
    Booking(
      id: 'b',
      date: date,
      status: status,
      instructorId: 'i',
      instructorName: 'Trainer',
      kiterId: kiterId ?? 'k',
      studentName: 'Rider',
      startTime: startTime,
      endTime: endTime,
      selectedTimes: selectedTimes,
      durationHours: durationHours,
      totalPrice: totalPrice,
      type: type,
      listingTitle: listingTitle,
      payment: payment,
    );

void main() {
  group('BookingStatus.parse', () {
    test('accepts the legacy `active` wire value', () {
      expect(BookingStatus.parse('active'), BookingStatus.inProgress);
      expect(BookingStatus.parse('in_progress'), BookingStatus.inProgress);
    });

    test('unknown serialises back to pending, never to a new wire value', () {
      expect(BookingStatus.parse('surprise'), BookingStatus.unknown);
      expect(BookingStatus.unknown.wire, 'pending');
    });
  });

  group('hours — the precedence ladder', () {
    test('durationHours wins over everything', () {
      expect(
          make(
            durationHours: 3,
            selectedTimes: ['10:00'],
            startTime: '10:00',
            endTime: '15:00',
          ).hours,
          3);
    });

    test('then the count of selected slots', () {
      expect(make(selectedTimes: ['10:00', '11:00']).hours, 2);
    });

    test('then end minus start', () {
      expect(make(startTime: '10:00', endTime: '13:00').hours, 3);
    });

    test('an inverted range falls to the 1-hour floor, never negative', () {
      expect(make(startTime: '13:00', endTime: '10:00').hours, 1);
      expect(make().hours, 1);
    });
  });

  group('occupiedSlots', () {
    test('selected times win, and garbage entries are dropped not slots of 0',
        () {
      final slots =
          make(selectedTimes: ['10:00', 'garbage', '12:00']).occupiedSlots;
      expect([for (final s in slots) s.value], ['10:00', '12:00']);
    });

    test('otherwise expands start by hours', () {
      final slots = make(startTime: '09:00', durationHours: 3).occupiedSlots;
      expect([for (final s in slots) s.value], ['09:00', '10:00', '11:00']);
    });

    test('no usable time holds nothing', () {
      expect(make().occupiedSlots, isEmpty);
      expect(make(startTime: 'noon').occupiedSlots, isEmpty);
    });
  });

  group('timeRange', () {
    test('derives a missing end from the duration', () {
      expect(make(startTime: '10:00', durationHours: 2).timeRange,
          '10:00–12:00');
    });

    test('an unparseable start is an em dash, not a crash', () {
      expect(make(startTime: 'whenever').timeRange, '—');
      expect(make().timeRange, '—');
    });
  });

  group('endsAt — the fallback ladder', () {
    test('endTime wins', () {
      expect(make(startTime: '10:00', endTime: '12:00').endsAt,
          DateTime(2099, 6, 15, 12));
    });

    test('then start plus hours', () {
      expect(make(startTime: '10:00', durationHours: 2).endsAt,
          DateTime(2099, 6, 15, 12));
    });

    test('a booking with no time runs to the end of its day (§8.7)', () {
      expect(make().endsAt, DateTime(2099, 6, 15, 23, 59, 59),
          reason: 'anything earlier would prematurely expire it');
    });

    test('an unparseable date has no end at all', () {
      expect(make(date: 'someday').endsAt, isNull);
      expect(make(date: 'someday').isPast, isFalse,
          reason: 'no end means never past — fails open into upcoming');
    });
  });

  group('bucket with a pinned clock', () {
    final noon = DateTime(2050, 1, 1, 12);

    test('inProgress is active regardless of its date', () {
      expect(
          make(date: '1999-01-01', status: BookingStatus.inProgress)
              .bucket(noon),
          BookingBucket.active);
    });

    test('dead and completed are history even in the future', () {
      for (final s in [
        BookingStatus.cancelled,
        BookingStatus.rejected,
        BookingStatus.completed,
      ]) {
        expect(make(date: '2099-01-01', status: s).bucket(noon),
            BookingBucket.history);
      }
    });

    test('a live booking flips to history only once its end passes', () {
      final b = make(
          date: '2050-01-01', startTime: '10:00', endTime: '11:00');
      expect(b.bucket(DateTime(2050, 1, 1, 10, 30)), BookingBucket.upcoming,
          reason: 'still running counts as upcoming until it ends');
      expect(b.bucket(noon), BookingBucket.history);
    });
  });

  group('money', () {
    test('amountDue prefers the amount captured at booking time', () {
      final captured = make(
          totalPrice: 80,
          payment: const PaymentInfo(
              status: PaymentStatus.unpaid, amount: 95));
      expect(captured.amountDue, 95,
          reason: 'a later rate change must not reprice an old booking');
      expect(make(totalPrice: 80).amountDue, 80);
      expect(make().amountDue, 0);
    });

    test('awaitsPayment never fires on untracked history', () {
      final tracked = make(
          status: BookingStatus.completed,
          payment: const PaymentInfo(status: PaymentStatus.unpaid));
      final untracked = make(status: BookingStatus.completed);
      expect(tracked.awaitsPayment, isTrue);
      expect(untracked.awaitsPayment, isFalse,
          reason: 'unknown is not unpaid — history is not owed money');
      expect(
          make(payment: const PaymentInfo(status: PaymentStatus.unpaid))
              .awaitsPayment,
          isFalse,
          reason: 'only completed sessions can be owed');
    });
  });

  test('walk-ins are manual by id or by type', () {
    expect(make(kiterId: 'manual_entry').isManual, isTrue);
    expect(make(type: 'manual').isManual, isTrue);
    expect(make().isManual, isFalse);
  });

  test('title falls back by booking type', () {
    expect(make(listingTitle: 'Downwinder').title, 'Downwinder');
    expect(make(type: 'safari').title, 'Expedition');
    expect(make().title, 'Kitesurf lesson');
  });
}
