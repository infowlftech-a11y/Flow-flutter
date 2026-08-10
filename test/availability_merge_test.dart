// dayAvailabilityProvider merges three Firestore streams — blocks, the day's
// bookings, vacations — and §7.5 requires it to emit only once ALL THREE have
// produced a value. The failure mode it prevents is real: emit after two and
// the booking grid renders a day as free while the stream that knew better is
// still connecting; a rider can tap an hour that was never available.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flow/core/utils/date_x.dart';
import 'package:flow/data/models/booking.dart';
import 'package:flow/data/models/schedule.dart';
import 'package:flow/data/repositories/booking_repository.dart';
import 'package:flow/data/repositories/schedule_repository.dart';
import 'package:flow/providers/providers.dart';

class _FakeScheduleRepo implements ScheduleRepository {
  final blocks = StreamController<List<Availability>>.broadcast();
  final vacations = StreamController<List<Vacation>>.broadcast();

  @override
  Stream<List<Availability>> watchDayBlocks(String instructorId, String date) =>
      blocks.stream;

  @override
  Stream<List<Vacation>> watchVacations(String instructorId) =>
      vacations.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('availability should only watch');
}

class _FakeBookingRepo implements BookingRepository {
  final day = StreamController<List<Booking>>.broadcast();

  @override
  Stream<List<Booking>> watchDayBookings(String instructorId, String date) =>
      day.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('availability should only watch');
}

void main() {
  const key = (instructorId: 'trainer1', date: '2099-06-15');

  late _FakeScheduleRepo schedule;
  late _FakeBookingRepo bookings;
  late ProviderContainer container;
  late List<AsyncValue<DayAvailability>> emissions;

  setUp(() {
    schedule = _FakeScheduleRepo();
    bookings = _FakeBookingRepo();
    container = ProviderContainer(overrides: [
      scheduleRepositoryProvider.overrideWithValue(schedule),
      bookingRepositoryProvider.overrideWithValue(bookings),
    ]);
    addTearDown(container.dispose);
    emissions = [];
    final sub = container.listen(dayAvailabilityProvider(key),
        (_, next) => emissions.add(next));
    addTearDown(sub.close);
  });

  Future<void> pump() => Future<void>.delayed(Duration.zero);

  test('emits nothing until all three streams have reported', () async {
    schedule.blocks.add(const []);
    await pump();
    bookings.day.add(const []);
    await pump();
    expect(emissions, isEmpty,
        reason: 'two of three is a half-truth the grid must never render');

    schedule.vacations.add(const []);
    await pump();
    expect(emissions, hasLength(1));
    final day = emissions.single.value!;
    expect(day.onVacation, isFalse);
    expect(day.blocked, isEmpty);
    expect(day.booked, isEmpty);
  });

  test('any later change re-emits a recomposed day', () async {
    schedule.blocks.add(const []);
    bookings.day.add(const []);
    schedule.vacations.add(const []);
    await pump();

    schedule.blocks.add(const [
      Availability(
          id: 'blk',
          instructorId: 'trainer1',
          date: '2099-06-15',
          startTime: '10:00',
          endTime: '12:00',
          status: 'host-blocked'),
    ]);
    await pump();

    final day = emissions.last.value!;
    expect(day.blockedReason(Slot.tryParse('10:00')!), 'Unavailable');
    expect(day.blockedReason(Slot.tryParse('11:00')!), 'Unavailable');
    expect(day.blockedReason(Slot.tryParse('12:00')!), isNull,
        reason: 'a block covers [start, end) — the end hour is free');
  });

  test('a live booking books its hours; vacation outranks everything',
      () async {
    schedule.blocks.add(const []);
    bookings.day.add([
      Booking.fromDoc('b1', const {
        'date': '2099-06-15',
        'status': 'confirmed',
        'startTime': '14:00',
        'durationHours': 1,
      }),
    ]);
    schedule.vacations.add(const []);
    await pump();
    expect(emissions.last.value!.blockedReason(Slot.tryParse('14:00')!),
        'Booked');

    schedule.vacations.add(const [
      Vacation(
          id: 'v',
          instructorId: 'trainer1',
          startDate: '2099-06-10',
          endDate: '2099-06-20'),
    ]);
    await pump();
    final away = emissions.last.value!;
    expect(away.onVacation, isTrue);
    expect(away.blockedReason(Slot.tryParse('14:00')!), 'Away',
        reason: 'precedence is Away → Too soon → Booked → Unavailable');
    expect(away.fullyBooked, isTrue);
  });
}
