/// The cancellation policy and the escrow ledger it drives (P1 in
/// FLOW_REDESIGN.md).
///
/// booking.com's template, mapped to single sessions: **free cancellation
/// until 24 hours before start; cancelling inside that window, or not
/// showing up, is charged in full** — a session is one "night", and the late
/// fee on booking.com is the first night. A request the trainer never
/// accepted refunds in full however it dies, and a cancellation from the
/// trainer's side always refunds in full: the fee exists to protect a
/// trainer's committed hours, never to monetise their own withdrawal.
///
/// ## Written vs derived — the invariant this file guards
///
/// `paymentStatus` records only what has *actually happened* to money:
/// `held` when the rider paid FLOW at booking, `refunded`/`paid_out` when a
/// processor or staff executes a movement. Everything in between — "refund
/// due", "charged, payout due" — is derived here from facts the Firestore
/// rules already pin (booking status, `cancelledBy`, `cancelledAt`). No
/// client ever writes a claim that money moved, so no client can forge one;
/// the future Functions/PSP layer executes exactly what [EscrowState]
/// reports. A rider cancel without its `cancelledAt` stamp reads as *late*
/// — omitting the stamp can never buy a refund.
library;

import 'booking.dart';
import 'payment.dart';

/// One template, app-wide — the booking.com shape with FLOW's numbers.
abstract final class CancellationPolicy {
  /// Free cancellation ends this long before the session starts.
  static const freeCancelWindow = Duration(hours: 24);

  /// The instant free cancellation ends, or null when the booking has no
  /// readable start.
  static DateTime? freeCancelDeadline(Booking b) =>
      b.startsAt?.subtract(freeCancelWindow);

  /// What cancelling [b] at [at] (defaults to now) means for the money.
  ///
  /// Callers show this *before* the confirm — a fee nobody was warned about
  /// is a complaint, not a policy.
  static CancelPreview preview(Booking b, {DateTime? at}) {
    final now = at ?? DateTime.now();
    if (!b.payment.status.isHeldByApp) {
      // Cash-era booking or walk-in: nothing was paid in advance, so a
      // cancellation moves no money whenever it happens.
      return const CancelPreview(
          prepaid: false, charged: false, refund: 0, deadline: null);
    }
    final amount = b.amountDue;
    // A request the trainer has not accepted refunds in full at any time:
    // no hours were ever committed to the rider.
    if (b.status == BookingStatus.pending) {
      return CancelPreview(
          prepaid: true, charged: false, refund: amount, deadline: null);
    }
    final deadline = freeCancelDeadline(b);
    // No readable start — the benefit of the doubt goes to the rider.
    if (deadline == null) {
      return CancelPreview(
          prepaid: true, charged: false, refund: amount, deadline: null);
    }
    final late = !now.isBefore(deadline);
    return CancelPreview(
      prepaid: true,
      charged: late,
      refund: late ? 0 : amount,
      deadline: deadline,
    );
  }

  /// Where a booking's held money stands — the ledger line the processor
  /// will execute, derived after the fact.
  static EscrowState settle(Booking b, {DateTime? at}) {
    // Executed states win: once a processor or staff has moved the money,
    // the derivation's opinion is history.
    switch (b.payment.status) {
      case PaymentStatus.refunded:
        return EscrowState.refunded;
      case PaymentStatus.paidOut:
        return EscrowState.paidOut;
      case PaymentStatus.held:
        break;
      default:
        return EscrowState.none;
    }

    switch (b.status) {
      case BookingStatus.completed:
        return EscrowState.payoutDue;
      case BookingStatus.rejected:
        return EscrowState.refundDue;
      case BookingStatus.cancelled:
        if (b.cancelledBy != 'user') {
          // Trainer or staff ended it — the rider is made whole, whenever
          // it happened.
          return EscrowState.refundDue;
        }
        final deadline = freeCancelDeadline(b);
        final stamp = b.cancelledAt;
        // A rider cancel with no stamp cannot prove it beat the deadline,
        // and the rules make the stamp mandatory — so its absence is a
        // hand-rolled write, and it reads as late.
        if (deadline == null) return EscrowState.refundDue;
        if (stamp == null || !stamp.isBefore(deadline)) {
          return EscrowState.payoutDue;
        }
        return EscrowState.refundDue;
      case BookingStatus.pending:
        // A request nobody answered: once its day is over it is dead, and
        // the hold has to go back.
        final now = at ?? DateTime.now();
        final ends = b.endsAt;
        if (ends != null && now.isAfter(ends)) return EscrowState.refundDue;
        return EscrowState.held;
      default:
        return EscrowState.held;
    }
  }
}

/// The answer to "what happens if I cancel this right now?".
class CancelPreview {
  const CancelPreview({
    required this.prepaid,
    required this.charged,
    required this.refund,
    required this.deadline,
  });

  /// FLOW is holding money for this booking. False on the cash path, where
  /// a cancellation moves nothing.
  final bool prepaid;

  /// Cancelling now falls inside the window: the rider is charged in full.
  final bool charged;

  /// What comes back to the rider — the full amount or nothing; the policy
  /// has no partial tier.
  final double refund;

  /// When free cancellation ends. Null when it does not apply (cash,
  /// pending, or no readable start).
  final DateTime? deadline;
}

/// One booking's held money, as a ledger line.
enum EscrowState {
  /// Nothing held — cash-era booking, walk-in, or pre-escrow history.
  none,

  /// Held for a live booking.
  held,

  /// The booking died in the rider's favour: full refund owed. Trainer
  /// decline or cancel, a free-window rider cancel, or an expired request.
  refundDue,

  /// The booking resolved in the trainer's favour: payout owed. A delivered
  /// session, or a rider cancel inside the window (booking.com's late fee —
  /// the trainer's committed hours are what the fee protects).
  payoutDue,

  /// Executed by the processor or staff.
  refunded,
  paidOut,
}
