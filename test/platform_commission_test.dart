// FLOW's 20% platform commission (P14).
//
// The split is a business rule ordered on 2026-08-13: the rider pays the
// trainer's full rate, FLOW keeps 20%, the trainer takes home 80%. It lives in
// exactly two places — the rate in FlowConst, and the derivation in
// Booking.trainerEarning — so it is pinned here directly rather than only
// through the earnings aggregates. A change to the rate is a deliberate act,
// and this test makes an accidental one fail loudly.
import 'package:flutter_test/flutter_test.dart';

import 'package:flow/core/constants.dart';
import 'package:flow/data/models/booking.dart';

Booking _priced({double? total, double? amountDue}) => Booking.fromDoc('b1', {
      'date': '2026-08-14',
      'status': 'completed',
      'totalPrice': ?total,
      'amountDue': ?amountDue,
    });

void main() {
  test('the commission and trainer share are complements that sum to 1', () {
    expect(FlowConst.platformCommissionRate, 0.20);
    expect(FlowConst.trainerShareRate, 0.80);
    expect(
      FlowConst.platformCommissionRate + FlowConst.trainerShareRate,
      closeTo(1, 1e-9),
    );
  });

  test('trainerEarning is 80% of what the rider pays', () {
    expect(_priced(total: 100).trainerEarning, closeTo(80, 1e-9));
    expect(_priced(total: 250).trainerEarning, closeTo(200, 1e-9));
    expect(_priced(total: 0).trainerEarning, 0);
  });

  test('the captured amountDue wins over the listed price, then nets the fee', () {
    // amountDue is the price captured at booking time; it is what the trainer
    // earns 80% of, so a later rate change on the listing cannot move it.
    final b = _priced(total: 80, amountDue: 95);
    expect(b.amountDue, 95);
    expect(b.trainerEarning, closeTo(76, 1e-9));
  });

  test('the rider-facing amount stays the full price — only the take is net', () {
    // The split is invisible to the rider: amountDue is the gross they pay.
    // Only trainerEarning applies the commission.
    final b = _priced(total: 120);
    expect(b.amountDue, 120, reason: 'the rider pays the full rate');
    expect(b.trainerEarning, closeTo(96, 1e-9), reason: 'the trainer nets 80%');
  });
}
