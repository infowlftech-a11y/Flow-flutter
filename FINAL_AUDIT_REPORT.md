# FINAL AUDIT REPORT — Flow

**Protocol:** CLAUDE_FULL_AUDIT.md (autonomous full-application audit,
zero-known-bugs pass)
**Date:** 2026-08-13
**Branch:** feat/auth-payments-push-wind
**Trackers:** [AUDIT_PLAN.md](AUDIT_PLAN.md) · [BUGS.md](BUGS.md) (BUG-019…028)

---

## Executive summary

The application is in strong shape. A previous adversarial pass (closed at
`d37e123`) had already hardened auth gating, booking collisions, reviews,
chats, moderation and the rules against privilege escalation (BUG-001…018).
This pass targeted the code that landed **after** that — escrow/payments,
Instant Book, the notification fan-out, and the P9–P13 product work — and the
areas COVERAGE.md flagged as unverified.

It found one systemic weakness and seven discrete defects. The systemic
finding: **the app's repository enforces a set of money and state-machine
invariants that the security rules — the only authority a hand-rolled
Firestore client is bound by — did not.** Five holes of that shape were
closed in the rules, one of them a *critical live blocker* (no rider could
reserve a safari seat against the real rules) and one a *critical money leak*
(a raw client could cancel a delivered, settled lesson and erase the
earnings). Two more defects sat in the app: a declined trainer was bounced
off their own support ticket, and the "tap to rate" notification landed on
the wrong tab. All seven are fixed and pinned by tests.

No high-severity, currently-reproducible defect is left open within the
tested scope.

## Environment

| | |
|---|---|
| Platform | Flutter (Dart) client on Firebase (Firestore, Auth, Storage, Messaging) |
| "The API" | `firestore.rules` — the only server-side authorization. There is no HTTP/SQL layer. |
| Dart suite | `flutter test` — 797 tests, `fake_cloud_firestore` (rules NOT evaluated) |
| Rules suite | `test_rules/` — 389 tests, Firestore **emulator** (real `firestore.rules`) |
| Static analysis | `flutter analyze` — clean |
| Not exercised | Live wlf-flow (needs the owner's credentials); push delivery (Cloud Functions disabled on the project); on-device drive |

Harness limits carried from BUGS.md: `fake_cloud_firestore` has no
transaction isolation and diverges on `arrayUnion` / missing-doc update /
post-transaction stream re-emit. Every "X cannot do Y" claim is therefore
answered in `test_rules/` on the emulator, never in the Dart fake.

## Test coverage this pass

- **+29 rules tests** — `test_rules/escrow.test.mjs`: the money's API surface
  (terminal transitions, cancel-signature authenticity, escrow execution,
  safari reservation, trip publishing).
- **+17 Dart tests** — `test/gate_redirect_test.dart`: the whole route-level
  authorization table, one allow-list and one denial per session stage.
- Baselines re-run green after every change: **797 Dart / 389 rules /
  analyze clean**.

Areas audited and found clean (explicitly, not by omission): notification
type-parsing and tap-routing for all 13 kinds; badge/unread/mark-read;
deleted/missing notification targets; the money aggregates (outstanding vs
payout-due are disjoint, no double-count, no NaN, cancelled-booking exclusion
holds); the earnings-screen label-vs-sum; P9 ticket `topic` null-handling on
legacy tickets; P10 console "door" resolvers (deleted target, walk-in with no
rider); P11 coach-profile edges (legacy `createdAt`, rating-breakdown at the
≥3 boundary); the failure-type → user-copy mapping on the money paths.

## Bugs found

| ID | Sev | Area | Root cause | Status |
|---|---|---|---|---|
| BUG-019 | **critical** | rules / money | Terminal booking states unguarded at the API — a rider could cancel a completed, settled lesson (erasing earnings), a trainer could resurrect a cancelled one. Repository guarded it; rules did not. | **FIXED** — `statusStays()` |
| BUG-020 | major | rules / money | A trainer, being a party, could cancel through the rider branch and sign it `cancelledBy:'user'`, keeping the late fee on their own withdrawal. | **FIXED** — rider branch gated to `kiterId==uid`, `providerCancelSigned()` |
| BUG-021 | major | rules / ledger | A trainer could forge `paid_out` (FLOW's transfer) or convert a `held` escrow booking to cash-paid. Model said these are FLOW-only; only the repository enforced it. | **FIXED** — `providerPaymentOk()` |
| BUG-022 | **critical** | rules / booking | P5's Instant-Book gate denied every safari seat reservation (always born `confirmed`, host never toggles Instant Book) — no rider could book a safari on live Firestore. | **FIXED** — `reservesASeat()` |
| BUG-024 | major | rules | Safari-trip publishing lacked the block gate every other create has, and any role could publish. | **FIXED** — `isActiveBusiness()` + `notBlocked` semantics |
| BUG-025 | major | routing | P12 made the ticket thread a pushed route `/support/ticket/:id`; the `rejected` gate allow-listed only exact `/support`, so a declined trainer was bounced off their own ticket — could file, couldn't read the reply. | **FIXED** — `gateRedirect` extracted + `/support/` prefix |
| BUG-026 | minor | notifications | "Tap to rate your trainer" dropped its `bookingId` and opened Upcoming (no rate button); the push path routed it correctly, so in-app/push diverged. | **FIXED** — mirror the booking cases |
| BUG-023 | minor (latent) | rules | A booking can be created already carrying `checkedIn`/`cancelledAt`; unreachable to money without a second party. | reported only |
| BUG-027 | minor (latent) | reporting | Revenue sums on `status==completed` alone; a refunded-completed booking would count as earnings. No UI path reaches it today. | reported only (approval-gated file) |
| BUG-028 | minor | reporting | Weekly-earnings bars can shift a day across a midnight DST change (Cairo); week total is correct. | reported only (approval-gated file) |

Each carries a full entry — reproduction, why it matters, and the fix — in
[BUGS.md](BUGS.md).

## Bugs remaining

**No known unresolved bugs of high or medium severity were identified within
the tested scope.**

Three low/latent items are documented and deliberately not fixed:

- **BUG-023, BUG-027** — latent, unreachable through the current UI. BUG-027's
  one-line fix lives in `lib/providers/` (approval-gated by CLAUDE.md) and
  should be applied together with wiring the refund action.
- **BUG-028** — cosmetic, one week a year; fix is calendar-date differencing
  in the same approval-gated file.
- **NOTE (BUGS.md)** — the rider cancellation `cancelledAt` is trusted by
  documented design ("the processor verifies the timestamp"). BUG-019's
  terminal guard closes the worst case; the residual free-window backdate on a
  *live* booking is latent until a PSP executes refunds. Pinning it
  (`cancelledAt == request.time`) is cheap and faithful but overrides an
  explicit design decision — surfaced for the owner's call.

## Regression results

Run after every fix batch, and once more at close:

- `flutter analyze` — clean.
- `flutter test` — **797 passed, 0 failed** (780 pre-existing, unmodified +
  17 new gate tests).
- `test_rules` (emulator) — **389 passed, 0 failed** (360 pre-existing,
  unmodified + 29 new escrow tests).

No pre-existing test was modified to accommodate a fix. The new rules guards
were checked to leave every existing allow-path intact (settlement and
history-hiding on completed bookings, the UNDO approve→pending path, walk-in
creation, the real `createBooking`/`cancelByRider` payloads).

## Security findings

All five rules fixes are server-side authorization hardening of the same
class as the prior pass's BUG-001/003/005/006:

- The rules now enforce the booking **state machine** (terminal transitions),
  not just the writable field set — closing the API re-opening of BUG-013/014.
- **Cancellation authorship** (`cancelledBy`) is authenticated on both branches, so
  neither party can sign the other's cancellation and bend the escrow.
- The escrow's **executed states** (`paid_out`, and any change to a `held`
  booking's payment) are FLOW/staff-only at the API, matching the model.
- **Safari-trip publishing** now requires an approved, non-blocked business,
  consistent with Explore and the suspension model.

**Deploy action required:** these fixes are in `firestore.rules` and take
effect only once deployed — `firebase deploy --only firestore:rules`. The
live database still runs the previous rules until then. (Several earlier fixes
were already marked "deploy pending" in BUGS.md; this pass could not verify
the live deployment state without project credentials, so treat a redeploy as
the safe action.)

## UI/UX findings

- BUG-025 (declined trainer's support lifeline) and BUG-026 (review
  notification tab) were the two user-facing defects; both fixed.
- The destructive-action pattern (§10.4) and in-flight/stale handling (§10.5)
  on the money paths are sound: the rider cancel shows the money consequence
  before confirming and surfaces the specific `StatusConflictFailure` reason
  when a live row moved underneath the tap.
- The 71-frame capture board was verified earlier this session (commit
  24a29f2); no rendering regressions were introduced here (the only widget
  touched, `notifications_screen.dart`, changed a navigation target, not
  layout).

## Remaining risks

- **Live vs local rules drift** — verified on the emulator, not on wlf-flow.
  A redeploy is required and its success is the owner's to confirm.
- **No test runs the real Dart repositories against the real rules** — the
  standing gap from COVERAGE.md. `test_rules/` uses payloads transcribed from
  the repositories (close, not identical). Closing it needs an
  `integration_test` on a device pointed at the emulator.
- **Push delivery** is inert (Cloud Functions disabled); its tap-routing is
  verified by reading, not by delivery.
- **Concurrency** claims rest on `test_rules/transactions.test.mjs` against the
  emulator, since the Dart fake cannot model isolation.

## Final assessment

Within the tested scope, the application is free of known high- and
medium-severity defects. The audit's material result is that the security
rules now enforce the same money and state-machine invariants the app's
repositories always did — the gap between "the app won't let you" and "the
database won't let you" was where the real exposure lived, and it is closed
for the booking lifecycle, the escrow, the cancellation ledger, and safari
reservations. The one critical availability bug (safari reservations dead on
live Firestore) and the one critical integrity bug (earnings erasable by a
raw cancel) are both fixed and pinned.

This is not a claim that the application is bug-free. It is an honest
statement that the systematic surface named in the protocol — auth,
authorization, booking, ticketing, reporting, CRUD, the rules API, state and
error handling, and the UI paths — has been exercised, the defects found have
been fixed and regression-tested, and the residual risks are named above.
