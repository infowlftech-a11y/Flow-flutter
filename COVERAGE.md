# Coverage against APP_LOGIC_BLUEPRINT.md

Every numbered section of §6.2, §6.3, §8, §9, §10 and §11 gets a row.
"Not covered" is an acceptable row; a missing row is not.

**Suites**

| Suite | Runs against | Count |
|---|---|---|
| `test/` (`flutter test`) | `fake_cloud_firestore` — **rules are not evaluated** | 636 |
| `test_rules/` (`npm test`) | Firestore emulator — the real `firestore.rules` | 268 |

636 = the 445 that existed before this work, unmodified and still green,
plus 191 new. New files: `flow_approval_test.dart` (30),
`flow_booking_test.dart` (51), `flow_collision_test.dart` (30),
`flow_checkin_test.dart` (17), `flow_review_test.dart` (34),
`flow_moderation_test.dart` (28).

---

## Two limits that shape every row below

**1. The Dart suite cannot evaluate security rules.** `fake_cloud_firestore`
ignores them entirely. Every "X cannot do Y" claim is therefore answered in
`test_rules/`, not in `test/`, and a row that says "rules" means the
emulator ran it.

**2. The Dart suite cannot evaluate Firestore semantics that depend on the
real backend.** Measured divergences:

| Behaviour | Real Firestore | fake_cloud_firestore |
|---|---|---|
| transaction isolation | retries the loser | lost update |
| `arrayUnion` of an identical value | collapses to one | appends both |
| transactional `update` of a missing doc | rejects | creates it |
| snapshot stream after a transactional write | re-emits | may not |

Consequences are recorded in BUGS.md under **NOTE**. The last one caused a
false negative during this work; the first caused a false positive. Both are
now routed to `test_rules/transactions.test.mjs` and
`test_rules/arrays.test.mjs`.

---

## §6.2 Queries

| Query | Test | Status |
|---|---|---|
| Active trainers | `flow_approval_test` — "Explore membership is exactly role=business AND status=active" (3 cases) | pass |
| Rider bookings | `flow_booking_test` — "the request lands on both lists"; rules: `bookings — read` | pass |
| Trainer bookings | `flow_booking_test` — same group; rules: filter-authorised list | pass |
| Day blocks | `availability_merge_test` (pre-existing) | pass |
| Day bookings | `flow_collision_test` — overlap geometry (8 cases) | pass |
| Vacations | `availability_merge_test` (pre-existing) | pass |
| Reviews for trainer | `flow_review_test` — "the trainers own review list" (3 cases) | pass |
| All ratings | `flow_review_test` — "§8.10 — what it does to the score" (8 cases) | pass |
| Inbox | `chats.test.mjs` — array-contains authorisation | pass |
| Messages | `chats.test.mjs` — read/create/immutability | pass |
| Notifications | `flow_booking_test` throughout; `misc.test.mjs` — targetUserId filter | pass |
| Tickets | `support.test.mjs` — owner/staff/stranger | pass |
| Ticket messages | `support.test.mjs` — 7 cases | pass |
| My appeal | `flow_moderation_test` — "the appeal round trip" | pass |
| Safari trips | `flow_collision_test`; `transactions.test.mjs` | pass |
| Station sub-collections | `users.test.mjs` — 12 cases | pass |
| **Client-side sorting is preserved** (no composite indexes) | Not covered | **not covered** — needs a test asserting no query carries an `orderBy` beside an equality filter. Worth adding; a server-side sort would break the screen with `failed-precondition` and nothing would catch it. |

## §6.3 Document writes

| Write | Test | Status |
|---|---|---|
| Booking created by rider | `booking_repository_test` — "writes the canonical shape" (pre-existing) | pass |
| Walk-in | `flow_booking_test` — "walk-ins have no rider to notify" (3 cases) | pass |
| Safari booking | `booking_repository_test` (pre-existing); `transactions.test.mjs` | pass |
| Status change | `flow_booking_test` — approve/decline/cancel/complete | pass |
| Rider cancel | `flow_booking_test` — "the write records who cancelled" | pass |
| Check-in | `flow_checkin_test` — "it records the check-in, not just the status" | pass |
| Hide | Not covered — **`hide()` has no callers** (BUG-002) | **not covered**, deliberately |
| Notification | `flow_booking_test` — §11.1 asserted row by row | pass |
| Chat message + thread | `chats.test.mjs`; §8.11 below | partial — see §8.11 |
| Availability block | `schedule.test.mjs` — 11 cases | pass |
| Vacation | `schedule.test.mjs` — 11 cases | pass |
| Review | `flow_review_test` — "what submit writes" (4 cases) | pass |
| Report | `flow_moderation_test` — "filing a report" (5 cases) | pass |
| Leave reason | `support.test.mjs` — write-only, staff-read | pass |
| Ticket + first message | `support.test.mjs` | pass |
| Appeal + arrayUnion replies | `flow_moderation_test`; `arrays.test.mjs` | pass |

> **§6.3 was stale** — it documented the pre-cleanup dual-write shape
> (`guestId`, `time`, `price`, `bookingType` on bookings, `userId` on
> notifications). Corrected in commit `f46996e`; BUG-009 and BUG-010 record
> what changed.

## §8 Business logic rules — 11 of 11 have tests

| § | Rule | Test | Status |
|---|---|---|---|
| 8.1 | Time slots, `Slot.tryParse` | `core_logic_test` (pre-existing) + `flow_collision_test` — "boundaries of the bookable day" | pass |
| 8.2 | Same-day lead time | `core_logic_test`; `booking_repository_test` — LeadTimeFailure | pass |
| 8.3 | Booking window & travel buffer | `flow_collision_test` — "the travel buffer is stored, not enforced" (3 cases) | pass — **and the warning is now pinned** |
| 8.4 | Contiguous hour selection | `core_logic_test` — `leadingRun` (4 cases) | **partial** — `leadingRun` is tested; `_tapSlot` itself is a private method in `booking_screen.dart` and is not. BUG-015 records that `createBooking` does not re-check it. |
| 8.5 | Availability composition | `availability_merge_test` (pre-existing); `flow_collision_test` — "which statuses hold an hour" (6 cases) | pass |
| 8.6 | Collision handling | `flow_collision_test` (5 cases) + `transactions.test.mjs` (5 cases) | pass — both halves, hourly and safari |
| 8.7 | Booking bucketing + subLabel | `booking_model_test`, `providers_logic_test` (pre-existing); `flow_booking_test` — subLabel table in full | pass — subLabel went from 1 of 7 rows to 7 of 7 |
| 8.8 | Explore filtering | `providers_logic_test` (pre-existing) | pass — not re-tested here |
| 8.9 | Review eligibility | `flow_review_test` — 13 cases across two groups | pass |
| 8.10 | Ratings | `flow_review_test` — 8 cases | pass |
| 8.11 | Unread messages | `providers_logic_test` (pre-existing) covers `unreadFor`/badge sum | **partial** — the increment/reset *round trip* between two participants is not driven end to end. Gap. |

## §9 Form validation — 7 of 7 have tests, 5 pre-existing

| § | Rule | Test | Status |
|---|---|---|---|
| 9.1 | Auth | `auth_test` — 28 cases (pre-existing) | pass |
| 9.2 | Rider onboarding | `core_logic_test` — `OnboardingValidators` (pre-existing) | pass |
| 9.3 | Trainer onboarding per-step gates | `core_logic_test`; `onboarding_rebuild_test` (pre-existing) | pass |
| 9.4 | Edit profile | `edit_profile_rebuild_test` (pre-existing) | pass |
| 9.5 | Booking | `flow_collision_test` — empty slots, midnight; `booking_repository_test` | pass |
| 9.6 | Walk-in | `flow_booking_test` — walk-in group; `booking_repository_test` — `fitsInDay` | **partial** — the repository side is covered; the form's "name non-empty and a start time chosen" gate is UI and is not |
| 9.7 | Support & appeals | `flow_moderation_test` — report/appeal writes | **partial** — the writes are covered; the required-field gates are UI and are not |

## §10 Edge cases, loading, errors — 6 of 10 covered, 4 are UI-only

| § | Rule | Test | Status |
|---|---|---|---|
| 10.1 | The three async states | `providers_logic_test` (pre-existing) | pass |
| 10.2 | Loading must not lie | `availability_merge_test` — "emits nothing until all three streams have reported" | pass |
| 10.3 | Error message mapping | `error_copy_test` (pre-existing, 5 cases) | pass |
| 10.4 | Destructive vs reversible | Not covered | **not covered** — dialogs and toasts; needs widget tests |
| 10.5 | In-flight and failure handling | Not covered | **not covered** — busy guards are widget state. Relevant: BUG-013 shows the `_busy` guard does not protect against *stale* state, only double taps |
| 10.6 | Offline & fire-and-forget | `misc.test.mjs` — notification mark-read permissions | **partial** — the permission is verified; the fire-and-forget *behaviour* (not awaiting the ack) is not |
| 10.7 | Data-quality fallbacks | `flow_checkin_test` — malformed/empty payloads; `flow_review_test` — review with no trainerId; `flow_booking_test` — unknown status; `core_logic_test` — unparseable dates | pass |
| 10.8 | Accessibility | `tap_target_test`, `text_contrast_test`, `component_render_test` (pre-existing) | pass |
| 10.9 | Motion | Not covered | **not covered** — no test asserts durations or curves |
| 10.10 | Haptics | Not covered | **not covered** — no test asserts a haptic fires |

## §11 Notifications — 7 of 9 rows exist in the code

| Trigger | Test | Status |
|---|---|---|
| Rider requests a booking | `flow_booking_test` — "the request lands on both lists" | pass |
| …with instant confirm | — | **row removed from §11.1** (commit f46996e): `instantBooking` was deleted from `AppUser`, so the feature it described is unreachable |
| Trainer approves | `flow_booking_test` — title, body, kind, bookingId | pass |
| Trainer declines | `flow_booking_test` — with, without, and whitespace-only reason | pass |
| Booking cancelled (by trainer) | `flow_booking_test` — "trainer cancels a confirmed session" | pass |
| Session completed | `flow_booking_test`; `flow_checkin_test` | pass |
| Rider cancels | `flow_booking_test` — "the trainer is told, with the session named" | pass |
| Safari seat reserved | `booking_repository_test` (pre-existing) | pass |
| Chat message | `chats.test.mjs` — permissions only | **partial** — the 117-char truncation is not tested |
| account_approved / account_rejected / account_restored | `flow_approval_test`, `flow_moderation_test` | pass — **now documented in §11.1** (commit f46996e). All three still parse to `NotificationKind.system` (BUG-011, open) |

| §11.2 In-app tap routing | Not covered | **not covered** — routing lives in `notifications_screen.dart` |
| §11.3 Push (FCM) | Not covered | **not covered** — and **Cloud Functions are disabled on this project**, so no push is delivered at all today |

## firestore.rules — every rule has an allow *and* a deny

260 emulator cases. Coverage by block:

| Block | Cases | Notes |
|---|---|---|
| `users` | 46 | one denial per privileged field; the no-op-write semantic of `affectedKeys()` pinned |
| `bookings` | 43 | **BUG-001 found and fixed here** |
| `availability` + `vacations` | 22 | driven from one table, identical rules |
| `reviews` | 21 | rating bounds on both edges and both sides; what the rules deliberately do *not* enforce is pinned (BUG-004) |
| `chats` + messages | 25 | **BUG-008 found and fixed here** |
| tickets, appeals, reports, leave_reasons | 44 | reports write-only for the reporter (§3.12) |
| notifications, safari_trips, catch-all | 40 | BUG-005 and BUG-006 pinned as current behaviour |
| blocked-account reach | 15 | **BUG-007 fixed** — notBlocked() on the five creates that reach someone else; the appeal, ticket, cancel, delete and read paths each have a test proving they stay open |
| transactions + arrays | 9 | real-Firestore semantics the Dart double gets wrong |

---

## The honest gaps, in one place

1. **No test runs the real Dart repositories against the real rules.**
   The rules are verified on the emulator; the repositories are verified
   against a fake. Nothing verifies that the app's actual writes are
   *accepted* by the rules in production. `test_rules/` uses payloads shaped
   like the real ones, which is close, not identical. Closing this needs an
   `integration_test` on a device pointed at the emulator — the harness for
   it already exists (`integration_test/walkthrough_test.dart`).
2. **Widget-level behaviour is largely untested by this work** — §10.4,
   §10.5, §10.9, §10.10, §11.2, and the form gates in §9.6/§9.7.
3. **§8.11's unread round trip** is not driven end to end.
4. **§6.2's "sorting stays client-side"** has no guard.
5. **The QR scanner's own parse branches** (§10.7) are exercised through
   their contract, not directly — the method is private inside a widget that
   builds a live camera.
6. **Push (§11.3) is untestable here and inert in production** while Cloud
   Functions are disabled.
