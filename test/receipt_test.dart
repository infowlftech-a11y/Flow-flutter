// The booking record PDF (P8).
//
// The builder is pure — bytes in, bytes out, no platform channels — so this
// can pin the two things that matter: every escrow state renders to a real
// PDF (a throw here would surface as a dead Save button on exactly one kind
// of booking), and the payment line tells each state's truth.
import 'package:flutter_test/flutter_test.dart';

import 'package:flow/data/models/booking.dart';
import 'package:flow/data/models/payment.dart';
import 'package:flow/features/sessions/receipt.dart';

Booking _booking({
  BookingStatus status = BookingStatus.confirmed,
  PaymentStatus payment = PaymentStatus.held,
  PaymentMethod method = PaymentMethod.app,
  String? cancelledBy,
}) => Booking(
  id: 'xK9fQ2abcd7x8k',
  date: '2099-08-28',
  status: status,
  instructorId: 't1',
  instructorName: 'Anna Bergström',
  kiterId: 'r1',
  studentName: 'Seif Ahmed',
  startTime: '10:00',
  endTime: '12:00',
  totalPrice: 190,
  cancelledBy: cancelledBy,
  payment: PaymentInfo(status: payment, method: method, amount: 190),
);

void main() {
  test('every escrow state renders a real PDF', () async {
    final variants = [
      _booking(), // held
      _booking(status: BookingStatus.rejected), // refund due
      _booking(status: BookingStatus.completed), // payout due
      _booking(payment: PaymentStatus.refunded),
      _booking(payment: PaymentStatus.paidOut),
      _booking(payment: PaymentStatus.paid, method: PaymentMethod.cash),
    ];
    for (final b in variants) {
      final bytes = await buildReceiptPdf(b);
      expect(bytes.length, greaterThan(500));
      // %PDF — the magic number, so this is a document and not an error blob.
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    }
  });

  test('the payment line tells each state its own truth', () {
    expect(receiptPaymentLine(_booking()), contains('held in escrow'));
    expect(
      receiptPaymentLine(_booking(status: BookingStatus.rejected)),
      contains('Refund'),
    );
    expect(
      receiptPaymentLine(_booking(payment: PaymentStatus.refunded)),
      'Refunded in full.',
    );
    expect(
      receiptPaymentLine(_booking(payment: PaymentStatus.paidOut)),
      contains('settled with the trainer'),
    );
    expect(
      receiptPaymentLine(
        _booking(payment: PaymentStatus.paid, method: PaymentMethod.cash),
      ),
      'Paid in person.',
    );
    expect(
      receiptPaymentLine(
        _booking(status: BookingStatus.cancelled, cancelledBy: 'user'),
      ),
      contains('Charged in full'),
      reason:
          'a rider cancel with no readable window stamp reads as late — '
          'the ledger rule (P1), told on paper',
    );
  });
}
