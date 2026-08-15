// BUG-027: a refunded-but-completed session must not count as earnings.
//
// `completed` means work delivered; `refunded` means the money went back.
// Before this fix the three earnings figures (all-time, this-month, week
// chart) summed on status alone, so a refunded session stood in the ledger
// at full price with nothing marking it. Latent today — `markRefunded` has
// no UI caller — but live the moment staff or the future processor refunds
// a delivered session, which is exactly the flow P1 anticipates.
//
// Each case pairs one ordinary completed session with one refunded one and
// asserts the figure equals the ordinary session's take-home alone (80% of
// the rider price, per P14).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flow/data/models/booking.dart';
import 'package:flow/providers/providers.dart';

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

Booking _completed(String date, double price, {String? paymentStatus}) =>
    Booking.fromDoc('b-$date-$price-${paymentStatus ?? 'none'}', {
      'date': date,
      'status': 'completed',
      'totalPrice': price,
      'paymentStatus': ?paymentStatus,
    });

ProviderContainer _container(List<Booking> completed) {
  final container = ProviderContainer(
    overrides: [
      trainerCompletedProvider.overrideWithValue(AsyncValue.data(completed)),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  final today = _ymd(DateTime.now());

  test('all-time revenue excludes a refunded session', () {
    final c = _container([
      _completed(today, 100, paymentStatus: 'paid'),
      _completed(today, 500, paymentStatus: 'refunded'),
    ]);

    expect(
      c.read(trainerRevenueProvider).requireValue,
      80, // 80% of 100; the refunded 500 contributes nothing
      reason: 'a refunded session is money returned, not money earned',
    );
  });

  test('this-month revenue excludes a refunded session', () {
    final c = _container([
      _completed(today, 100, paymentStatus: 'paid'),
      _completed(today, 500, paymentStatus: 'refunded'),
    ]);

    expect(c.read(trainerMonthRevenueProvider).requireValue, 80);
  });

  test('the week chart excludes a refunded session', () {
    final c = _container([
      _completed(today, 100, paymentStatus: 'paid'),
      _completed(today, 500, paymentStatus: 'refunded'),
    ]);

    final week = c.read(trainerEarningsWeekProvider).requireValue;
    expect(week.total, 80);
  });

  test('a session with no payment data at all still counts', () {
    // Every booking written before payments were tracked has no
    // paymentStatus; `unknown` is not `refunded`, and dropping history
    // out of "earned" would silently rewrite a number trainers know.
    final c = _container([_completed(today, 100)]);

    expect(c.read(trainerRevenueProvider).requireValue, 80);
  });
}
