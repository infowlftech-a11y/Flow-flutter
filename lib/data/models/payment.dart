/// Money — the vocabulary, not a processor.
///
/// ## What this is for
///
/// Money moves through FLOW (P1): a rider pays FLOW at booking and FLOW pays
/// the trainer after the session, keeping 20% (P14). Cash survives as the
/// walk-in path, where there is no rider account to charge.
///
/// This header used to open "FLOW takes no money today" — true when the file
/// was written, false since P1, and left standing long enough to reach the
/// README. v2.6 wrote a `paymentStatus: 'paid'` field that nothing read and
/// nothing could act on — a no-op that made the database *look* like it
/// tracked payment while recording nothing, which is worse than an empty
/// field because it invites trust.
///
/// This replaces it with something honest and, more importantly, with a shape
/// a real processor can be dropped into without a migration. Every booking now
/// records what was owed, in what currency, by what method, and whether it has
/// actually been collected. Cash is simply one method among several rather
/// than an unstated assumption baked into the UI copy.
///
/// ## What it deliberately is not
///
/// There is no Stripe, no RevenueCat, no card capture and no wallet here.
/// Wiring a processor is a product and compliance decision — who is the
/// merchant of record, who holds the float, what happens on a no-show — and
/// guessing at those in code would produce a payment system nobody agreed to.
/// What is here is the seam: `PaymentMethod` names the options,
/// `PaymentStatus` covers the states an online payment actually moves
/// through (including the asynchronous ones), and `paymentRef` is where a
/// processor's identifier goes.
library;

import '../../core/utils/doc_x.dart';

/// How a booking is settled.
enum PaymentMethod {
  /// The legacy answer, still real for walk-ins: the rider pays the trainer
  /// at the centre. There is no rider account behind a walk-in to charge.
  cash('cash', 'Pay at the centre'),

  /// The escrow path (P1 in FLOW_REDESIGN.md): the rider pays FLOW at
  /// booking, FLOW pays the trainer after the session completes. Until a
  /// processor is wired this is a recorded hold, not a card charge — the
  /// PSP drops into `paymentRef` and the executed statuses below.
  app('app', 'Paid through FLOW'),

  /// Reserved. Card taken in-app at booking time.
  card('card', 'Card'),

  /// Reserved. Prepaid balance or lesson package.
  wallet('wallet', 'FLOW balance'),

  /// Reserved. Common for multi-day safari deposits.
  transfer('transfer', 'Bank transfer');

  const PaymentMethod(this.wire, this.label);
  final String wire;
  final String label;

  /// Unrecognised wire values fall back to [cash] rather than throwing — the
  /// same tolerance every other reader in the app applies (§5).
  static PaymentMethod parse(String? raw) => switch (raw) {
        'app' => app,
        'card' => card,
        'wallet' => wallet,
        'transfer' => transfer,
        _ => cash,
      };

  /// Whether settling this method needs a person to hand over money.
  ///
  /// This is the line between "the trainer confirms they were paid" and "the
  /// processor tells us" — the only branch in the app that has to change when
  /// a real processor arrives.
  bool get isCollectedInPerson => this == cash;

  /// Whether this method can be chosen right now. Everything else is modelled
  /// but not offered, so the enum can be complete without the UI lying about
  /// what works.
  bool get isAvailable => this == cash || this == app;
}

/// Where a booking's money has got to.
enum PaymentStatus {
  /// **No payment information was ever recorded.**
  ///
  /// Every booking written before payments were tracked. Deliberately its own
  /// state rather than being folded into [unpaid]: a session from last month
  /// whose cash changed hands on the beach is not the same thing as one that
  /// is owing, and quietly relabelling history as "unpaid" would tell every
  /// trainer they are out of pocket for work they were already paid for.
  unknown('', 'Not tracked'),

  /// Owed. The normal state of a cash booking until the trainer collects.
  unpaid('unpaid', 'Unpaid'),

  /// The rider paid FLOW at booking and FLOW is holding it — escrow. Not
  /// settled: the trainer has not been paid, and if the booking dies in the
  /// rider's favour the money goes back. What the hold becomes ("refund
  /// due", "payout due") is *derived* from the booking, never written from a
  /// client — see EscrowState in cancellation.dart and P1 in
  /// FLOW_REDESIGN.md.
  held('held', 'Held by FLOW'),

  /// Reserved. Handed to a processor, no result yet — the state that makes
  /// asynchronous payment methods representable at all.
  processing('processing', 'Processing'),

  paid('paid', 'Paid'),

  refunded('refunded', 'Refunded'),

  /// A held payment FLOW has actually transferred to the trainer. Written by
  /// the processor/Functions layer (or staff), never by either party — until
  /// then a delivered session sits at [held] and reads as "payout due".
  paidOut('paid_out', 'Paid out'),

  /// Reserved. The processor declined it.
  failed('failed', 'Payment failed');

  const PaymentStatus(this.wire, this.label);
  final String wire;
  final String label;

  static PaymentStatus parse(String? raw) => switch (raw) {
        'unpaid' => unpaid,
        'held' => held,
        'processing' => processing,
        'paid' => paid,
        'refunded' => refunded,
        'paid_out' => paidOut,
        'failed' => failed,
        // Absent, empty or unrecognised — all mean "we do not know", which is
        // the truth and is not the same as "unpaid".
        _ => unknown,
      };

  /// Whether this status is worth putting on screen. [unknown] is not: a
  /// "Not tracked" pill on every historical booking is noise that teaches
  /// people to ignore the pill.
  bool get isDisplayable => this != unknown;

  /// Whether the trainer is still owed for this session *by the rider* —
  /// the cash ledger. A held payment is deliberately not here: the rider has
  /// already paid, and what FLOW owes the trainer is the payout question,
  /// answered by [isHeldByApp] + the booking's own status.
  bool get isOutstanding => this == unpaid || this == failed;

  /// FLOW is holding the rider's money.
  bool get isHeldByApp => this == held;

  /// Whether money has actually landed with the trainer.
  bool get isSettled => this == paid || this == paidOut;
}

/// The money on one booking, read as a unit.
///
/// A small value object rather than five loose fields on [Booking] so that
/// "what is the payment situation here" is one question with one answer, and
/// so a processor's identifiers have somewhere to live that is not the
/// booking's top level.
class PaymentInfo {
  const PaymentInfo({
    this.status = PaymentStatus.unknown,
    this.method = PaymentMethod.cash,
    this.currency = defaultCurrency,
    this.amount,
    this.paidAt,
    this.reference,
  });

  /// Euro, matching `money()` in the UI. Stored per booking anyway, so a
  /// currency change never needs a migration — bookings written while the
  /// app briefly quoted EGP keep their own `EGP` and stay honest about what
  /// was agreed.
  static const defaultCurrency = 'EUR';

  final PaymentStatus status;
  final PaymentMethod method;
  final String currency;

  /// What was owed, captured at booking time. Read from the booking's own
  /// `totalPrice` when absent — an older document has no separate amount.
  final double? amount;

  final DateTime? paidAt;

  /// The processor's identifier for this payment. Empty until there is one.
  final String? reference;

  static const none = PaymentInfo();

  factory PaymentInfo.fromDoc(Map<String, dynamic> d) => PaymentInfo(
        status: PaymentStatus.parse(d.str('paymentStatus')),
        method: PaymentMethod.parse(d.str('paymentMethod')),
        currency: d.str('currency') ?? defaultCurrency,
        amount: d.money('amountDue'),
        paidAt: d.date('paidAt'),
        reference: d.str('paymentRef'),
      );

  /// The fields a new booking writes. Kept here so every creation path —
  /// rider reservation, walk-in, safari seat — records payment identically.
  static Map<String, dynamic> initialFields({
    required double amount,
    PaymentMethod method = PaymentMethod.cash,
    PaymentStatus status = PaymentStatus.unpaid,
  }) =>
      {
        'paymentStatus': status.wire,
        'paymentMethod': method.wire,
        'currency': defaultCurrency,
        'amountDue': amount,
      };

  bool get isOutstanding => status.isOutstanding;
  bool get isSettled => status.isSettled;
}
