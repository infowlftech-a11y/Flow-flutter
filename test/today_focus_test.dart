// Which of today's sessions gets the card, and which get rows.
//
// The trainer's manifest used to be cards all the way down — six sessions, six
// SCAN TO START buttons, only one of which was ever the next thing to do. Now
// one session is promoted and the rest are rows, which means an ordering rule
// decides where the button lives.
//
// That rule is invisible: a manifest that promotes the wrong session looks
// completely normal and puts the wrong button under the trainer's thumb on a
// beach. So it is asserted here, with the clock pinned.
import 'package:flutter_test/flutter_test.dart';

import 'package:flow/data/models/booking.dart';
import 'package:flow/features/command_center/command_center_screen.dart';

/// Midday on the fixture's date, so 09:00 is over and 14:00 is ahead.
final _noon = DateTime(2026, 8, 9, 12);

Booking at(String start, BookingStatus status) => Booking(
      id: '$start-${status.wire}',
      date: '2026-08-09',
      status: status,
      instructorId: 't1',
      instructorName: 'Marco',
      kiterId: 'r1',
      studentName: 'Rider $start',
      startTime: start,
      durationHours: 1,
    );

void main() {
  test('an empty day has no focus', () {
    expect(todayFocus(const [], now: _noon), isNull);
  });

  test('a day that is over has no focus', () {
    // Every session done means there is no button to press, and the manifest
    // is correctly just a list of what happened.
    final done = [
      at('09:00', BookingStatus.completed),
      at('11:00', BookingStatus.completed),
    ];
    expect(todayFocus(done, now: _noon), isNull);
  });

  test('the next session still ahead is the one promoted', () {
    final day = [
      at('09:00', BookingStatus.confirmed),
      at('14:00', BookingStatus.confirmed),
      at('16:00', BookingStatus.confirmed),
    ];
    expect(todayFocus(day, now: _noon)?.startTime, '14:00');
  });

  test('a confirmed session that already ended is skipped', () {
    // Not the same as the test above: here 09:00 is the *only* other option,
    // so a naive "first confirmed" would pick a session that finished three
    // hours ago and offer to scan someone in to it.
    final day = [
      at('09:00', BookingStatus.confirmed),
      at('16:00', BookingStatus.confirmed),
    ];
    expect(todayFocus(day, now: _noon)?.startTime, '16:00');
  });

  test('a live session wins even when it has overrun', () {
    // The 09:00 is past its scheduled end but the trainer never finished it —
    // it is still the session happening on the water, and FINISH SESSION is
    // the button they need. Promoting the 14:00 instead would hide it.
    final day = [
      at('09:00', BookingStatus.inProgress),
      at('14:00', BookingStatus.confirmed),
    ];
    expect(todayFocus(day, now: _noon)?.status, BookingStatus.inProgress);
  });

  test('a pending request is never the focus', () {
    // Pending sessions have their own section with approve/decline. Promoting
    // one here would offer SCAN TO START for a booking the trainer has not
    // agreed to.
    final day = [at('14:00', BookingStatus.pending)];
    expect(todayFocus(day, now: _noon), isNull);
  });

  test('the answer does not depend on the order the day arrives in', () {
    // `todayManifestProvider` sorts, but the focus rule must not quietly
    // depend on that — the two are in different files and only one has a test.
    final day = [
      at('09:00', BookingStatus.completed),
      at('14:00', BookingStatus.confirmed),
      at('16:00', BookingStatus.confirmed),
    ];
    expect(todayFocus(day, now: _noon)?.id,
        todayFocus(day.reversed.toList(), now: _noon)?.id);
  });
}
