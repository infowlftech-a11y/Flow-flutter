import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/utils/date_x.dart';
import '../../core/utils/refs.dart';
import '../../data/models/booking.dart';
import '../../data/models/cancellation.dart';
import '../../data/models/payment.dart';

/// The booking record as a shareable PDF (P8) — booking.com's confirmation
/// document, sized to what FLOW actually knows.
///
/// One honest page: the session reference (the name support and the console
/// search by), the who/when/what, the amount, and where the money stands
/// straight off the escrow ledger. Deliberately titled a *booking record* —
/// until a payment processor issues real charges there is no tax invoice to
/// imitate, and a document that looks like one would be a forgery of a thing
/// that does not exist yet.
///
/// The builder is pure (bytes in, bytes out, no plugins) so a test can pin
/// that every escrow state renders; [shareReceipt] is the one line that
/// touches the platform share sheet.

const _navy = PdfColor.fromInt(0xFF071A2E);
const _azure = PdfColor.fromInt(0xFF0B7CD7);
const _faint = PdfColor.fromInt(0xFF5E6B7A);
const _line = PdfColor.fromInt(0xFFD8DfE6);

/// Where the money stands, in document language. Mirrors the session
/// sheet's PAYMENT row but says it in full sentences — paper has room.
String receiptPaymentLine(Booking b) => switch (CancellationPolicy.settle(b)) {
  EscrowState.held =>
    'Paid to FLOW and held in escrow. The trainer is paid after the '
        'session completes.',
  EscrowState.refundDue => 'Refund of ${money(b.amountDue)} due in full.',
  EscrowState.payoutDue =>
    b.status == BookingStatus.cancelled
        ? 'Charged in full — cancelled inside the 24-hour window.'
        : 'Paid. The trainer payout is queued.',
  EscrowState.refunded => 'Refunded in full.',
  EscrowState.paidOut => 'Paid and settled with the trainer.',
  EscrowState.none =>
    b.payment.status == PaymentStatus.paid
        ? 'Paid in person.'
        : 'To be settled in person.',
};

Future<Uint8List> buildReceiptPdf(Booking b) async {
  final doc = pw.Document(
    title: 'FLOW booking ${sessionRef(b.id, b.date)}',
    producer: 'FLOW',
  );

  pw.Widget row(String label, String value) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 7),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 130,
          child: pw.Text(
            label.toUpperCase(),
            style: pw.TextStyle(
              fontSize: 8.5,
              letterSpacing: 1.2,
              color: _faint,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
        pw.Expanded(
          child: pw.Text(
            value,
            style: const pw.TextStyle(fontSize: 11.5, color: _navy),
          ),
        ),
      ],
    ),
  );

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(56, 56, 56, 48),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                'FLOW',
                style: pw.TextStyle(
                  fontSize: 26,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: 2,
                  color: _azure,
                ),
              ),
              pw.Text(
                'Booking record',
                style: const pw.TextStyle(fontSize: 12, color: _faint),
              ),
            ],
          ),
          pw.SizedBox(height: 6),
          pw.Divider(color: _line, thickness: 1),
          pw.SizedBox(height: 18),
          pw.Text(
            sessionRef(b.id, b.date),
            style: pw.TextStyle(
              fontSize: 20,
              fontWeight: pw.FontWeight.bold,
              letterSpacing: 1,
              color: _navy,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            'Quote this reference in any support conversation.',
            style: const pw.TextStyle(fontSize: 9.5, color: _faint),
          ),
          pw.SizedBox(height: 20),
          row('Session', b.title),
          row('Date', longYmd(b.date)),
          if (Slot.tryParse(b.startTime) != null) row('Time', b.timeRange),
          row('Rider', b.studentName),
          row('Trainer', b.instructorName),
          if (b.gearNeeded) row('Gear', 'Provided by the centre'),
          row('Status', b.status.label),
          pw.SizedBox(height: 10),
          pw.Divider(color: _line, thickness: 1),
          pw.SizedBox(height: 10),
          row('Amount', money(b.amountDue)),
          row('Payment', receiptPaymentLine(b)),
          if (b.payment.status.isHeldByApp || b.payment.status.isSettled)
            row(
              'Cancellation',
              'Free until 24 hours before the start; inside the window the '
                  'session is charged in full. A declined or unanswered '
                  'request is always refunded.',
            ),
          pw.Spacer(),
          pw.Divider(color: _line, thickness: 1),
          pw.SizedBox(height: 8),
          pw.Text(
            'Generated by the FLOW app. A record of the booking and its '
            'escrow state — not a tax invoice.',
            style: const pw.TextStyle(fontSize: 8.5, color: _faint),
          ),
        ],
      ),
    ),
  );

  return doc.save();
}

/// Hands the PDF to the system share sheet, named after the session ref so
/// the file is findable in a downloads folder full of "document (3).pdf".
Future<void> shareReceipt(Booking b) async => Printing.sharePdf(
  bytes: await buildReceiptPdf(b),
  filename: '${sessionRef(b.id, b.date)}.pdf',
);
