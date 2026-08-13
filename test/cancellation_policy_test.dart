// The cancellation policy — the booking.com template with FLOW's numbers —
// and the escrow ledger derived from it (P1 in FLOW_REDESIGN.md).
//
// Every branch here is money: a wrong answer either charges a rider who
// cancelled in time or refunds one who cancelled on the beach. The rules
// make the inputs trustworthy (a rider cancel cannot exist without its
// cancelledBy/cancelledAt stamp); this file pins what the derivation does
// with them, including the boundary instant and the stamp-missing case.
import 'package:flutter_test/flutter_test.dart';

import 'package:flow/data/models/booking.dart';
import 'package:flow/data/models/cancellation.dart';
import 'package:flow/data/models/payment.dart';

Booking _booking({
  BookingStatus status = BookingStatus.confirmed,
  PaymentStatus payment = PaymentStatus.held,
  String date = '2099-08-29',
  String? startTime = '10:00',
  String? endTime = '12:00',
  DateTime? cancelledAt,
  String? cancelledBy,
}) =>
    Booking(
      id: 'b1',
      date: date,
      status: status,
      instructorId: 't1',
      instructorName: 'Anna',
      kiterId: 'r1',
      studentName: 'Seif',
      startTime: startTime,
      endTime: endTime,
      totalPrice: 100,
      cancelledAt: cancelledAt,
      cancelledBy: cancelledBy,
      payment: PaymentInfo(status: payment, amount: 100),
    );

// Session starts 2099-08-29 10:00 → free cancellation ends 2099-08-28 10:00.
final _deadline = DateTime(2099, 8, 28, 10);

void main() {
  group('preview — what cancelling right now would do', () {
    test('outside the window: full refund, deadline named', () {
      final p = CancellationPolicy.preview(_booking(),
          at: _deadline.subtract(const Duration(minutes: 1)));
      expect(p.prepaid, isTrue);
      expect(p.charged, isFalse);
      expect(p.refund, 100);
      expect(p.deadline, _deadline);
    });

    test('at the deadline instant and after: charged in full', () {
      for (final at in [
        _deadline,
        _deadline.add(const Duration(hours: 1)),
        DateTime(2099, 8, 29, 11), // mid-session no-show cancel
      ]) {
        final p = CancellationPolicy.preview(_booking(), at: at);
        expect(p.charged, isTrue, reason: 'at $at');
        expect(p.refund, 0, reason: 'at $at');
      }
    });

    test('a pending request refunds in full even inside the window', () {
      final p = CancellationPolicy.preview(
          _booking(status: BookingStatus.pending),
          at: _deadline.add(const Duration(hours: 12)));
      expect(p.charged, isFalse);
      expect(p.refund, 100,
          reason: 'no hours were committed — a request is never charged '
              'before the trainer accepts it');
    });

    test('a cash booking moves no money whenever it is cancelled', () {
      final p = CancellationPolicy.preview(
          _booking(payment: PaymentStatus.unpaid),
          at: _deadline.add(const Duration(hours: 1)));
      expect(p.prepaid, isFalse);
      expect(p.charged, isFalse);
      expect(p.refund, 0);
    });

    test('no readable start: the doubt benefits the rider', () {
      final p = CancellationPolicy.preview(
          _booking(date: '', startTime: null, endTime: null));
      expect(p.charged, isFalse);
      expect(p.refund, 100);
    });
  });

  group('settle — the ledger line after the fact', () {
    test('a live held booking is simply held', () {
      expect(CancellationPolicy.settle(_booking(), at: _deadline),
          EscrowState.held);
    });

    test('completed: payout due to the trainer', () {
      expect(
          CancellationPolicy.settle(
              _booking(status: BookingStatus.completed)),
          EscrowState.payoutDue);
    });

    test('declined: refund due, whenever it happened', () {
      expect(
          CancellationPolicy.settle(_booking(status: BookingStatus.rejected)),
          EscrowState.refundDue);
    });

    test('rider cancel before the deadline: refund due', () {
      expect(
        CancellationPolicy.settle(_booking(
          status: BookingStatus.cancelled,
          cancelledBy: 'user',
          cancelledAt: _deadline.subtract(const Duration(minutes: 1)),
        )),
        EscrowState.refundDue,
      );
    });

    test('rider cancel at or after the deadline: charged — payout due', () {
      for (final stamp in [
        _deadline,
        _deadline.add(const Duration(hours: 6)),
      ]) {
        expect(
          CancellationPolicy.settle(_booking(
            status: BookingStatus.cancelled,
            cancelledBy: 'user',
            cancelledAt: stamp,
          )),
          EscrowState.payoutDue,
          reason: 'stamped $stamp',
        );
      }
    });

    test('a rider cancel with no stamp reads as late — omission never pays',
        () {
      expect(
        CancellationPolicy.settle(_booking(
            status: BookingStatus.cancelled, cancelledBy: 'user')),
        EscrowState.payoutDue,
      );
    });

    test('provider or staff cancel: refund due, stamps irrelevant', () {
      for (final by in ['provider', 'staff', null]) {
        expect(
          CancellationPolicy.settle(_booking(
            status: BookingStatus.cancelled,
            cancelledBy: by,
            cancelledAt: _deadline.add(const Duration(hours: 6)),
          )),
          EscrowState.refundDue,
          reason: 'cancelledBy $by',
        );
      }
    });

    test('an expired request: refund due without anyone touching it', () {
      expect(
        CancellationPolicy.settle(_booking(status: BookingStatus.pending),
            at: DateTime(2099, 8, 30)),
        EscrowState.refundDue,
      );
    });

    test('executed states win over any derivation', () {
      expect(
          CancellationPolicy.settle(_booking(
              status: BookingStatus.cancelled,
              cancelledBy: 'user',
              payment: PaymentStatus.refunded)),
          EscrowState.refunded);
      expect(
          CancellationPolicy.settle(_booking(
              status: BookingStatus.completed,
              payment: PaymentStatus.paidOut)),
          EscrowState.paidOut);
    });

    test('cash-era bookings have no escrow line at all', () {
      for (final s in [
        PaymentStatus.unknown,
        PaymentStatus.unpaid,
        PaymentStatus.paid,
      ]) {
        expect(CancellationPolicy.settle(_booking(payment: s)),
            EscrowState.none,
            reason: '$s');
      }
    });
  });

  group('the payment vocabulary the escrow rests on', () {
    test('held and paid_out survive the wire round trip', () {
      expect(PaymentStatus.parse('held'), PaymentStatus.held);
      expect(PaymentStatus.parse('paid_out'), PaymentStatus.paidOut);
      expect(PaymentMethod.parse('app'), PaymentMethod.app);
    });

    test('held is not settled and not outstanding — it is its own thing', () {
      expect(PaymentStatus.held.isSettled, isFalse,
          reason: 'the trainer has not been paid');
      expect(PaymentStatus.held.isOutstanding, isFalse,
          reason: 'the rider does not owe — they already paid FLOW');
      expect(PaymentStatus.held.isHeldByApp, isTrue);
    });

    test('awaitsPayout is completed + held, nothing else', () {
      expect(_booking(status: BookingStatus.completed).awaitsPayout, isTrue);
      expect(_booking().awaitsPayout, isFalse);
      expect(
          _booking(
                  status: BookingStatus.completed,
                  payment: PaymentStatus.unpaid)
              .awaitsPayout,
          isFalse);
    });
  });
}
