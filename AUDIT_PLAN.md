# AUDIT_PLAN — Autonomous full-application audit, 2026-08-13

Protocol: `CLAUDE_FULL_AUDIT.md`. Tracker: `BUGS.md` (extends the existing
BUG-001…018 log from the fix-everything pass; same format, same severity
scale). Coverage map of record: `COVERAGE.md`.

## How the generic protocol maps to this app

This is a Flutter client on Firebase. There is no HTTP API layer and no SQL
database, so the protocol's sections land as follows:

| Protocol says | Here that means |
|---|---|
| API audit, HTTP status codes | `firestore.rules` — the only server-side authority. Suite: `test_rules/` on the emulator (real rules engine). |
| Database audit | Firestore document shapes (`lib/data/models/`), invariants held by repositories, rules `hasOnly`/precondition guards. |
| Server-side authorization, IDOR | Rules denial tests: cross-user reads/writes, filter-shape queries, privileged-field writes. |
| E2E / use the app from outside | Widget-harness tests driving real screens against `fake_cloud_firestore` + the 71-frame capture board (`test/capture/board_capture.dart`). On-device drive against live needs the user's credentials — out of scope, recorded as residual risk. |
| Sessions, multiple tabs, back button | go_router guards, gate routing, Android back handling, provider stream lifecycles. |
| Roles | Admin (staff console), Coach (trainer/station), Rider. |

Known harness limits (measured, recorded in BUGS.md NOTE): the Dart fake has
no transaction isolation, diverges on `arrayUnion`/missing-doc update/stream
re-emit after transactional writes. Concurrency claims are answered only in
`test_rules/transactions.test.mjs`.

## Baseline — 2026-08-13

- `flutter analyze`: clean (0 issues) — **TESTED**
- `flutter test`: **780 passed, 0 failed** — **TESTED**
- `test_rules` (`npm test`, emulator): running — result recorded below when in
- Build: release APK built clean earlier today (29.4 MB arm64) — **TESTED**
- Working tree: carries the user's uncommitted theme work (25 paths). It is
  part of the audited surface (tests run against it) but is never committed
  by the audit.

## Scope decision

The fix-everything pass (closed `d37e123`) already adversarially audited:
auth gating, booking CRUD + collisions, reviews, chats, moderation/suspension,
appeals, rules privilege escalation, notifications spoofing. Those areas are
re-verified by the baseline suites, then spot-checked — not re-audited from
scratch. The audit effort goes where no adversarial pass has ever run:

**A. Code landed after `d37e123`** (19 commits, `26c410c..034950a`):
escrow/payments, Instant Book, notification fan-out, ban records, App Check
wiring, cancel-window, receipts/handover, session names, P9 ticket topics,
P10 console doors, P11 coach profile, P12 motion, P13 top bars.

**B. COVERAGE.md's honest-gaps list**: widget-level behaviour (§10.4
destructive confirms, §10.5 busy guards vs stale state), §11.2 notification
tap routing, §9.6/§9.7 form gates, §8.11 unread round trip, the misleading
`screen_overlap_test` admin case.

**C. Deploy drift**: BUG-003/004/005/006/018 rules fixes were "deploy
pending" at `d37e123` — verify whether live wlf-flow runs the current
`firestore.rules`.

## Checklist

Statuses: NOT_STARTED / IN_PROGRESS / TESTED / FIXED / VERIFIED.
(TESTED = executed with no new defect; FIXED = defect found and fixed;
VERIFIED = fix regression-tested.)

### 1. Baseline & environment
- [x] Static analysis — TESTED
- [x] Full Dart suite (780) — TESTED
- [ ] Rules suite on emulator — IN_PROGRESS
- [ ] Local rules vs deployed rules drift — NOT_STARTED

### 2. Money & escrow (post-audit code, highest stakes)
- [x] Rules: paymentStatus/amount writes; escrow state transitions — FIXED
      (BUG-021: provider could forge paid_out / settle held escrow)
- [x] Repository: double-settle/refund-after-payout guards present in
      markPaid/markRefunded; terminal-transition guard was repository-only —
      FIXED at the API (BUG-019)
- [x] 24 h free-cancel window: math sound; the derivation trusts a
      client-written `cancelledAt` on a live booking by documented design —
      TESTED, residue noted (NOTE in BUGS.md)
- [~] Earnings/reporting figures vs hand-computed data — agent auditing;
      folded below

### 3. Instant Book (post-audit code)
- [x] Rules: rider create status='confirmed' requires trainerAllowsInstant —
      pinned by existing tests; safari's always-confirmed create was denied by
      the same gate — FIXED (BUG-022, critical live-blocker)
- [x] Provider cancel signature + terminal guard cover the instant paths —
      TESTED

### 4. Notification fan-out (post-audit code)
- [ ] Every new notification type parses and routes (§11.2 gap) — NOT_STARTED
- [ ] New creates still fit BUG-005's constrained rule shapes — NOT_STARTED
- [ ] Badge/unread correctness (§8.11 round trip gap) — NOT_STARTED

### 5. Ticketing (P9) & admin doors (P10)
- [ ] Ticket topic: rules accept app payload; junk topic from raw SDK
      renders safely; ownership on ticket reads — NOT_STARTED
- [ ] Console ID doors: deleted/missing targets, cross-links, walk-in rows — NOT_STARTED

### 6. Coach profile (P11) & auth/session spot-check
- [x] createdAt null-guarded (legacy docs show nothing); monthsShort index
      safe; rating breakdown guarded at >=3 reviews, no divide-by-zero — TESTED
- [x] Gate routing: extracted `gateRedirect` + full truth-table test — FIXED
      (BUG-025: rejected trainer bounced off own ticket thread, P12 regression)
- [x] Failure-type copy: StatusConflictFailure/PaymentFailure caught by type
      and surfaced with their own message; destructive confirms present — TESTED

### 7. Widget-level behaviour gaps (COVERAGE.md §10.4/§10.5/§9.6/§9.7)
- [x] Destructive actions confirm; the rider cancel shows the money
      consequence before confirming — TESTED
- [x] In-flight/stale handling: StatusConflictFailure surfaced with its own
      reason on a stale row; generic fallback avoids the false-success trap —
      TESTED
- [x] Support form gate blocks empty topic (agent-verified) — TESTED

### 8. State management
- [x] Stale stream rows: _writeIfLive terminal guard + StatusConflict copy;
      badge/unread stream re-emits on mark-read (agent-verified) — TESTED
- [x] Door resolvers on P10 paths use one-shot reads with mounted checks +
      toast fallbacks (agent-verified) — TESTED

### 9. Error handling
- [x] Money-path catch blocks surface copy and reset UI — TESTED
- [x] StatusConflictFailure/PaymentFailure/DuplicateAppealFailure caught by
      type and shown with their own message — TESTED

### 10. UI/UX, responsive, accessibility
- [x] 71-frame board read at 1.0x/1.3x/320px — TESTED (24a29f2, this window)
- [x] Tap targets + labels (guideline suite) — TESTED
- [x] Contrast both themes (guideline suite) — TESTED
- [x] Only widget touched this pass (notifications_screen) changed a nav
      target, not layout — no re-render needed — TESTED

### 11. Exploratory
- [x] Invalid IDs (deleted booking/ticket/profile) handled without crash
      (agent-verified); long station name in ticket chip fixed earlier
      (misc.dart); boundary dates in escrow/DST surfaced (BUG-028) — TESTED

### 12. Regression & close-out
- [x] Full Dart (797) + rules (389) green after fixes; analyze clean — TESTED
- [x] Self-review of audit diffs — clean, no debug residue, no dead code
- [x] FINAL_AUDIT_REPORT.md written — DONE

## Deploy action for the owner
`firebase deploy --only firestore:rules` — the five rules fixes take effect
only once deployed; the live database runs the prior rules until then.

## Out of scope, recorded honestly
- Push delivery (§11.3): Cloud Functions disabled on the project — inert in
  production, untestable here. Standing user action.
- On-device walk against live Firestore: needs the user's credentials
  (seed cast cannot sign in to live as of 2026-08-12).
- `lib/dev/` seed tooling: separate entry point, per CLAUDE.md.
