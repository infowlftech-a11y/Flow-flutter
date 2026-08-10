// What a rider is offered on one of their own bookings.
//
// The redesign moved these buttons off the card and into a detail sheet, which
// means the rules stopped being visible in the layout — you can no longer tell
// by looking at the screen that a safari offers no check-in. That is exactly
// when a switch like this starts to rot, so it is asserted here instead.
//
// Each case is a thing that would be wrong for a *reason*, not a restatement
// of the switch: checking in to a lesson that already happened, checking in to
// a safari that has no beach counter, rating a session that was cancelled.
import 'package:flutter_test/flutter_test.dart';

import 'package:flow/core/utils/date_x.dart';
import 'package:flow/data/models/booking.dart';
import 'package:flow/features/sessions/sessions_screen.dart';

Booking booking({
  required BookingStatus status,
  String? date,
  String startTime = '10:00',
  String? type,
}) =>
    Booking(
      id: 'b1',
      date: date ?? ymd(DateTime.now().add(const Duration(days: 3))),
      status: status,
      instructorId: 't1',
      instructorName: 'Marco',
      kiterId: 'r1',
      studentName: 'Rider',
      startTime: startTime,
      durationHours: 1,
      type: type,
    );

void main() {
  test('a pending request can only be withdrawn', () {
    // Nothing to check into and nothing to rate — the trainer has not even
    // agreed to it yet.
    expect(sessionActionsFor(booking(status: BookingStatus.pending)),
        [SessionAction.cancel]);
  });

  test('a confirmed lesson offers check-in first, then cancel', () {
    expect(sessionActionsFor(booking(status: BookingStatus.confirmed)),
        [SessionAction.checkIn, SessionAction.cancel]);
  });

  test('a safari offers no check-in', () {
    // A safari is a multi-day trip, not a slot at a beach counter: there is no
    // moment at which someone scans you in, so the QR would open onto nothing.
    expect(
      sessionActionsFor(
          booking(status: BookingStatus.confirmed, type: 'safari')),
      [SessionAction.cancel],
    );
  });

  test('a confirmed session that already ended offers no check-in', () {
    // The most likely real-world case: a booking nobody ever completed. It is
    // still "confirmed" in the document, but scanning in to yesterday is not a
    // thing the rider can do.
    final past = booking(
      status: BookingStatus.confirmed,
      date: ymd(DateTime.now().subtract(const Duration(days: 2))),
    );
    expect(past.isPast, isTrue, reason: 'fixture must actually be in the past');
    expect(sessionActionsFor(past), [SessionAction.cancel]);
  });

  test('a session in progress offers only its ticket', () {
    // Cancelling mid-session is not the rider's call once the trainer has
    // scanned them in — that is a conversation, not a button.
    expect(sessionActionsFor(booking(status: BookingStatus.inProgress)),
        [SessionAction.showTicket]);
  });

  test('a completed session offers a rating', () {
    expect(sessionActionsFor(booking(status: BookingStatus.completed)),
        [SessionAction.rate]);
  });

  test('dead bookings offer nothing at all', () {
    // Rating a lesson that never happened would put a fabricated review on a
    // trainer's profile.
    for (final status in [
      BookingStatus.cancelled,
      BookingStatus.rejected,
      BookingStatus.unknown,
    ]) {
      expect(sessionActionsFor(booking(status: status)), isEmpty,
          reason: '${status.name} should offer no actions');
    }
  });

  test('a booking with hours prints the day and the hours', () {
    final b = booking(status: BookingStatus.confirmed, startTime: '10:00');
    expect(dayAndTime(b, 'Sat 29 Aug'), 'Sat 29 Aug · 10:00–11:00');
  });

  test('a booking with no start time prints the day alone', () {
    // An expedition is sold by the day. `Booking.timeRange` reports its
    // missing hours as a bare em dash, which rendered on the hero card, the
    // session row, the QR ticket and the earnings ledger as "Sat 29 Aug · —"
    // — a separator joining a date to nothing.
    final safari = Booking(
      id: 'trip',
      date: '2026-08-29',
      status: BookingStatus.confirmed,
      instructorId: 't1',
      instructorName: 'Red Sea Downwind Co.',
      kiterId: 'r1',
      studentName: 'Rider',
      type: 'safari',
    );
    expect(safari.timeRange, '—', reason: 'fixture must hit the dash branch');
    expect(dayAndTime(safari, 'Sat 29 Aug'), 'Sat 29 Aug');
    expect(dayAndTime(safari, 'Sat 29 Aug'), isNot(contains('—')));
  });

  test('cancel is always last where it appears', () {
    // It is the destructive one. Anywhere it shares a row with something else,
    // it sits on the right — and the row is built straight from this list.
    for (final status in BookingStatus.values) {
      final actions = sessionActionsFor(booking(status: status));
      if (actions.contains(SessionAction.cancel)) {
        expect(actions.last, SessionAction.cancel,
            reason: '${status.name} puts cancel mid-row');
      }
    }
  });
}
