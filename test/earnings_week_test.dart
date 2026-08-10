// Weekday bucketing and the week-over-week delta.
//
// This is the only genuinely new arithmetic the redesign introduced, and it is
// arithmetic about money, so it is tested directly rather than through a
// widget. Three things here are decisions rather than mechanics, and each has
// a test that fails if someone "simplifies" it later:
//
//   1. a week starts on Monday, fixed, because the seven buckets have to line
//      up with the seven labels under the chart;
//   2. a delta against a zero week is *null*, not +100% — a percentage change
//      from nothing is undefined, and "+100%" on a first week of trading is a
//      flattering lie;
//   3. a booking whose stored date will not parse is skipped, not bucketed
//      into Monday — silent misattribution here is money in the wrong column.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flow/data/models/booking.dart';
import 'package:flow/providers/providers.dart';

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

Booking _completed(String date, double price) => Booking.fromDoc('b-$date-$price', {
      'date': date,
      'status': 'completed',
      'totalPrice': price,
    });

/// Monday of the current week, which every case here is expressed relative to
/// so the suite does not rot on a particular calendar date.
DateTime get _monday {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return today.subtract(Duration(days: today.weekday - DateTime.monday));
}

EarningsWeek _read(List<Booking> completed) {
  final container = ProviderContainer(overrides: [
    trainerCompletedProvider.overrideWithValue(AsyncValue.data(completed)),
  ]);
  addTearDown(container.dispose);
  return container.read(trainerEarningsWeekProvider).requireValue;
}

void main() {
  test('buckets by weekday, Monday first', () {
    final week = _read([
      _completed(_ymd(_monday), 100), // Mon
      _completed(_ymd(_monday.add(const Duration(days: 2))), 50), // Wed
      _completed(_ymd(_monday.add(const Duration(days: 2))), 30), // Wed again
      _completed(_ymd(_monday.add(const Duration(days: 6))), 20), // Sun
    ]);

    expect(week.byWeekday, [100, 0, 80, 0, 0, 0, 20]);
    expect(week.total, 200);
  });

  test('a delta against a week that earned nothing is null, not +100%', () {
    final week = _read([_completed(_ymd(_monday), 250)]);

    expect(week.total, 250);
    expect(week.deltaVsPrevious, isNull,
        reason: 'a percentage change from zero is undefined — showing +100% '
            'for a first week of trading invents a comparison');
  });

  test('computes the delta against the previous seven days', () {
    final lastMonday = _monday.subtract(const Duration(days: 7));
    final week = _read([
      _completed(_ymd(lastMonday), 100), // previous week
      _completed(_ymd(_monday), 118), // this week
    ]);

    expect(week.deltaVsPrevious, closeTo(0.18, 0.0001));
  });

  test('ignores anything older than the previous week', () {
    final longAgo = _monday.subtract(const Duration(days: 40));
    final week = _read([
      _completed(_ymd(longAgo), 9999),
      _completed(_ymd(_monday), 100),
    ]);

    expect(week.total, 100);
    expect(week.deltaVsPrevious, isNull,
        reason: 'a session 40 days ago must not count as last week');
  });

  test('skips a booking whose date will not parse', () {
    final week = _read([
      _completed('not-a-date', 500),
      _completed(_ymd(_monday), 60),
    ]);

    expect(week.byWeekday.first, 60,
        reason: 'an unparseable date was bucketed into Monday');
    expect(week.total, 60);
  });

  test('marks today so the chart knows which bar to point at', () {
    final week = _read([_completed(_ymd(_monday), 10)]);
    final expected = DateTime.now().weekday - DateTime.monday;

    expect(week.todayIndex, expected);
  });
}
