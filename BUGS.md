# Defects found while verifying the multi-party logic

Every finding is logged here when found, before any fix. Includes the ones
fixed immediately, the cosmetic ones, and the ones deliberately not fixed.

Severity: **critical** = privilege escalation or data loss · **major** =
a documented rule does not hold · **minor** = cosmetic, dead, or
inconsistent but not exploitable.

---

## BUG-001 — A rider can write any non-payment field on their own booking

**Severity:** critical (privilege escalation)
**Found:** rules suite, `test_rules/bookings.test.mjs`
**File:** [firestore.rules:120-123](firestore.rules#L120-L123)
**Status:** FIXED and deployed to wlf-flow

### What

The booking update rule authorises either party for anything that is not a
money field:

```
allow update: if signedIn()
  && (isProvider()
      || (isParty() && paymentFieldsUnchanged())
      || isStaff());
```

A rider *is* `isParty()`, and `paymentFieldsUnchanged()` names only
`paymentStatus, paymentMethod, paidAt, refundedAt, paymentRef, amountDue,
currency, totalPrice`. Every other field on the document — `status`,
`date`, `time`, `instructorId`, `checkedIn` — is therefore writable by the
rider.

### Reproduction

Five denial tests in `bookings — update, the rider` fail, each with
`Expected request to fail, but it succeeded`:

| Test | Write that should not be permitted |
|---|---|
| rider approving their own pending booking | `{status: 'confirmed'}` |
| rider checking themselves in | `{status: 'in_progress', checkedIn: true}` |
| rider marking their own session completed | `{status: 'completed'}` |
| rider moving the session to another day | `{date: '2026-09-01'}` |
| rider reassigning the booking to another trainer | `{instructorId: 'trainer2'}` |

Signed in as the rider on the booking, against the real rules on the
emulator. The app's UI never offers these writes; the Firestore SDK does.

### Why it matters

1. **Forged approval.** A rider flips `pending` to `confirmed` without the
   trainer agreeing. Per §8.5 availability subtracts bookings whose status
   `isLive`, so this also blocks the trainer's calendar for that hour.
2. **Check-in defeated.** Setting `in_progress` + `checkedIn` directly makes
   the QR scan (flow 4) decorative.
3. **Fake reviews.** §8.9 makes review eligibility depend on a **completed**
   booking. A rider can self-complete and then review a trainer they never
   trained with — an attack on the rating that drives Explore (§8.10).
4. **Writing onto a third party's calendar.** Reassigning `instructorId`
   puts a booking on `trainer2`'s calendar that they never accepted and can
   then read.

### Fix

Close the rider's writable key set instead of stripping money fields from
an open one. The rider's real write surface is exactly one call —
`cancelByRider` writing `{status:'cancelled', cancelledAt, cancelledBy}` —
plus the (currently uncalled, see BUG-002) `hide` writing `hiddenByGuest`.

`paymentFieldsUnchanged()` is kept in the chain although `hasOnly` already
excludes every field it names: if the key set is ever widened by mistake,
the money guard still holds.

---

## BUG-002 — `BookingRepository.hide()` has no callers

**Severity:** minor (dead code)
**Found:** call-graph search while scoping BUG-001
**File:** [lib/data/repositories/booking_repository.dart:527-529](lib/data/repositories/booking_repository.dart#L527-L529)
**Status:** not fixed — reported only

`hide({required bool asInstructor})` writes `hiddenByInstructor` /
`hiddenByGuest`, and §8.7 specifies that the bucket providers exclude
bookings carrying those flags. The read side is implemented and tested; the
write side is never invoked anywhere in `lib/`, so no user can ever hide a
booking.

Either a screen lost its call during the redesign, or the feature was never
finished. Not fixed because wiring it up is a **feature**, not a bug fix,
and the freeze permits neither without approval. The rules fix in BUG-001
deliberately keeps `hiddenByGuest` writable so wiring it later needs no
rules change.

---

## BUG-003 — A trainer can reassign a booking to a different trainer

**Severity:** major
**Found:** rules suite, while scoping BUG-001
**File:** [firestore.rules](firestore.rules) — `providerFieldsOnly()`
**Status:** FIXED — deploy pending

`isProvider()` was checked first and carried no field restriction at all, so
the trainer on a booking could write `instructorId` and hand the session to
someone else, who then had a booking on their calendar they never accepted.

Fixed under the blanket fix-everything instruction, resolving the open
question the same way §6.3 implies: no repository write ever changes
`instructorId`, `date`, `kiterId`, the selected hours or the price after
creation, so `providerFieldsOnly()` closes the trainer's writable set to
what the repository actually writes — status transitions, check-in fields,
settlement fields, `hiddenByInstructor`, `updatedAt`. Five denial tests in
`bookings — update, the trainer` pin it. If station-internal reassignment
ever becomes a feature, it needs its own rule, written on purpose.

---

## BUG-004 — Review eligibility is unenforceable outside the app

**Severity:** major
**Found:** rules suite, `test_rules/reviews.test.mjs`
**File:** [firestore.rules](firestore.rules) — `reviewedBooking()`
**Status:** MOSTLY FIXED — deploy pending; one residue stands

The rules pinned authorship and the 1-5 range; everything §8.9 specifies
lived in `ReviewRepository`, which a direct Firestore client does not run.
Of the four writes the rules accepted:

- ~~a review whose `bookingId` refers to no booking at all~~ — **denied**
- ~~a trainer reviewing themselves~~ — **denied** (`kiterId == uid()`)
- ~~a blocked user writing a review~~ — **denied** since BUG-007
- **two reviews for the same `bookingId` — still possible.** Enforcing it
  needs a deterministic review id (review id == booking id), a document-
  shape change, which per the standing constraint is not made unilaterally.
  The repository's re-check guard holds that line; the rules test pins the
  gap open so it stays visible.

The create rule now `get()`s the named booking — one billed read per review
write — and requires: `status == 'completed'`, `kiterId == uid()`, and
`instructorId == trainerId`. Six denial tests in
`reviews — eligibility is enforced at the API` pin it.

---

## BUG-005 — Any signed-in user can send any user a notification

**Severity:** major (spoofing and spam surface)
**Found:** rules suite, `test_rules/misc.test.mjs`
**File:** [firestore.rules](firestore.rules) — notifications `allow create`
**Status:** FIXED — deploy pending

`allow create: if signedIn()` had no constraint on `targetUserId`, title,
body or `type`, so any account could write a convincing "Booking cancelled"
into any stranger's inbox and it rendered identically to a genuine one.

Fixed exactly the way the entry predicted it had to be: the create is tied
to a relationship the sender can prove. Permitted shapes —

- **staff**, unconditionally (approval, rejection, restoration notices);
- **a booking-scoped notification** whose `bookingId` names a booking both
  the sender and the recipient are parties to (one billed `get()`);
- **a `message` notification** where a chat thread between sender and
  target exists — the thread id is the sorted uid pair, so it is
  addressable without a query;
- and never to yourself (`targetUserId != uid()`).

Deliberately **not** `notBlocked()`: a blocked rider may still cancel
(BUG-007's carve-out), so the cancel's warning to the trainer must still
land — asserted by `a blocked rider cancelling still warns the trainer`.
The relationship constraint is what keeps a blocked account from reaching
anyone *new*. A trainer can still send a false "cancelled" to their own
rider about their own booking; that is a dispute between counterparties,
not spoofing across strangers, and no rule can adjudicate it.

---

## BUG-006 — Any signed-in user can rewrite any safari trip

**Severity:** major
**Found:** rules suite, `test_rules/misc.test.mjs`
**File:** [firestore.rules](firestore.rules) — safari_trips `allow update`
**Status:** FIXED — deploy pending; one residue stands

`allow update: if signedIn()` was justified in the comment for one field —
`bookedSeats`, moved by the reserving rider's transaction — but authorised
every field, so any signed-in user could set a trip's `price` to 0 or its
`capacity` to 999.

Fixed with the `hasOnly` treatment, after tracing the two writes that
actually move a trip from outside: `reserveSafariSeat` (seats +1, status
open/full) and `cancelByRider`'s release (seats −1 floored at 0, status
open). A non-host write may now touch only `bookedSeats` and `status`, one
seat at a time, `>= 0`, `<= capacity` when capped, status in open/full.
Eight tests pin both directions.

**Residue:** one seat per write is the shape of every legitimate call, but
a signed-in stranger can still *walk* a manifest up seat by seat and mark
it full. Fully preventing that needs the seat increment tied to a booking
created in the same transaction, which needs deterministic booking ids — a
shape change, not made unilaterally. Noted in the rules comment.

---

## BUG-007 — Suspension is a client-side gate only

**Severity:** major
**Found:** rules suite, `test_rules/misc.test.mjs`
**File:** [firestore.rules](firestore.rules) (absence of a rule)
**Status:** FIXED and deployed to wlf-flow

No rule anywhere reads `status`. A blocked account keeps a valid Firebase
token and, at the API, retains the ability to read profiles, create
bookings, send chat messages, write reviews and file reports. The block is
enforced entirely by the client's gate routing (§2.3), which stops the app's
own UI from offering those actions and nothing else.

Filing an appeal *must* stay available (§3.12, and the rules comment on
appeals says so). The rest arguably should not be.

### Fix (applied)

`notBlocked()` reads `selfProfile().status` and is applied to **create**
only, on the four paths where a suspended account reaches someone else:
bookings, chats, chat messages, reviews and reports.

Deliberately left open, each with a test proving it still works:

| Still permitted | Why |
|---|---|
| filing an appeal | the point of a suspension is that it can be appealed (§3.12) |
| opening a support ticket | the other lifeline |
| **cancelling an existing booking** | otherwise a blocked rider holds a trainer's calendar hostage until the suspension lifts |
| deleting their account | §3.13 |
| recording a leave reason | follows account deletion |
| every read | they must see their own gate and their appeal |

`notBlocked()` fails closed: it `exists()`-checks the profile first, so a
signed-in user with no `users/{uid}` document is denied rather than read as
"not blocked". Onboarding writes the profile before anything else, so
nothing legitimate is caught by that.

Cost: one extra `get()` per guarded create. Accepted — the alternative is a
suspension that stops the UI from *offering* an action but not from
performing it, which is the same distinction that made BUG-001 exploitable.

---

## BUG-008 — A chat participant can rewrite the participants array

**Severity:** critical (privacy breach + denial of access)
**Found:** rules suite, `test_rules/chats.test.mjs`
**File:** [firestore.rules:164-189](firestore.rules#L164-L189)
**Status:** FIXED and deployed to wlf-flow

### What

`allow update: if signedIn() && isParticipant();` restricts *who* may write
but not *what*, and `participants` is an ordinary field on that document.

### Reproduction

Two denial tests in `chats — participant tampering` fail with `Expected
request to fail, but it succeeded`:

| Test | Write |
|---|---|
| removing the other from the thread | `{participants: ['rider']}` |
| adding an outsider to the thread | `{participants: ['rider','trainer','rider2']}` |

### Why it matters

1. **Adding an outsider exposes the whole history.** Message reads are
   gated by `inThread()`, which resolves through this same array — so one
   write hands a third party every message ever sent in that conversation.
2. **Removing the other party locks them out permanently.** They can no
   longer read the thread or its messages, and `allow delete: if false` on
   both means the design intends conversations to be indelible. This is a
   one-way loss of someone else's data.

### Fix

Pin the field. The app's only write of `participants` is
`ChatRepository.ensureThread` at
[chat_repository.dart:77-81](lib/data/repositories/chat_repository.dart#L77-L81),
a merge that writes `[me, partnerId]..sort()` — the identical value every
time, so `affectedKeys()` stays empty and the guard does not affect it.

---

## BUG-009 — Blueprint §6.2/§6.3/§8.10 name a review field the code renamed

**Severity:** minor (documentation drift)
**File:** [APP_LOGIC_BLUEPRINT.md](APP_LOGIC_BLUEPRINT.md) §6.2, §6.3, §8.10
**Status:** FIXED — blueprint corrected in `f46996e`

The blueprint says reviews carry `listingId` and that ratings are grouped by
it. The code writes and queries **`trainerId`**, and
[social.dart:5-7](lib/data/models/social.dart#L5-L7) explains the rename:
"The field was called `listingId` while it held the trainer's uid — on a
database only this app writes, it is stored honestly as `trainerId`."

The code is right and the blueprint was not updated. Flagged rather than
silently corrected because the blueprint is the specification of record.

---

## BUG-010 — Blueprint §11.1/§6.3 say notifications dual-write `userId`

**Severity:** minor (documentation drift)
**File:** [APP_LOGIC_BLUEPRINT.md](APP_LOGIC_BLUEPRINT.md) §6.3, §11.1, §15
**Status:** FIXED — §6.3 in `f46996e`; §11.1's prose and two §15 checklist
rows still asserted the dual writes and were corrected in this pass

Both sections state notifications are written with **both** `targetUserId`
and `userId`. `NotificationRepository.notify` writes only `targetUserId`,
and [notification_repository.dart:26-32](lib/data/repositories/notification_repository.dart#L26-L32)
explains why: the dual write existed for a web client that no longer
shares the database, and the Cloud Function reads
`data.userId || data.targetUserId` so it still resolves.

Same as BUG-009 — code is right, blueprint is stale.

---

## BUG-011 — The admin's own notification types are unmodelled

**Severity:** minor
**Found:** `test/flow_approval_test.dart`
**Files:** [admin_repository.dart](lib/data/repositories/admin_repository.dart),
[social.dart](lib/data/models/social.dart)
**Status:** FIXED

`AdminRepository` writes `account_approved`, `account_rejected` and
`account_restored`; `NotificationKind.parse` had a case for none of them,
so all fell through to `_ => system`. The three now resolve to their own
`NotificationKind.account`: a distinct icon on the tile, and the full-text
sheet as a *chosen* destination — a rejection carries its reason in full,
and the account state the message announces is already wherever the gate
routed the user. §11.1's table and note were updated to match, so the
three places are no longer written independently.

---

## BUG-012 — Approving a blocked account silently voids the suspension, and a later unblock then demotes them

**Severity:** major (latent — not reachable from today's UI)
**Found:** `test/flow_approval_test.dart`, adversarial pass
**File:** [admin_repository.dart](lib/data/repositories/admin_repository.dart)
**Status:** FIXED

`approveTrainer` and `restoreToPending` write `status` without touching
`blockedUntil` or `statusBeforeBlock`. Two consequences, both pinned by
passing tests:

1. **Approving a blocked trainer lifts the block as a side effect.** Status
   becomes `active`, so the gate stops applying the suspension, and they are
   bookable in Explore again — while `blockedUntil: 'forever'` sits stale on
   the document.
2. **A later unblock demotes them.** `unblockUser` restores
   `statusBeforeBlock`, which still holds the pre-block value. An approved,
   live trainer is pulled back to `pending` and disappears from Explore,
   undoing an approval that happened in between.

**Not reachable today:** the approvals queue filters `status == 'pending'`,
so a blocked account never appears in it, and `watchBlockedUsers()` has no
UI at all — so `unblockUser` currently has no caller either. This becomes
live the moment the blocked-users list is built.

### Fix (applied)

Two guards, because clearing the markers alone was not enough — with
`statusBeforeBlock` gone, a later `unblockUser` would have fallen back to
demoting any business account to `pending` anyway:

1. `approveTrainer`, `rejectTrainer` and `restoreToPending` clear
   `blockedUntil` and `statusBeforeBlock`: a review decision is an explicit
   statement of what the account now *is*, so it supersedes a suspension
   rather than cohabiting with its leftovers.
2. `unblockUser` refuses an account that is not currently blocked — the
   same stale-copy reading `_writeIfLive` and `markPaid` take: the
   blocked-users list is a live stream, and a row tapped after a colleague
   already acted is a retry, not a demotion. The no-op also skips the
   "account restored" notification.

Semantics chosen under the fix-everything instruction, ahead of the
blocked-users UI: whatever that screen becomes, an unblock that demotes an
approved trainer could never be the intended behaviour.

---

## BUG-013 / BUG-014 — Booking status writes have no preconditions

**Severity:** BUG-013 major · BUG-014 **critical** (money)
**Found:** `test/flow_booking_test.dart`, adversarial pass
**File:** [booking_repository.dart:319-323](lib/data/repositories/booking_repository.dart#L319-L323),
[booking_repository.dart:444-449](lib/data/repositories/booking_repository.dart#L444-L449)
**Status:** FIXED — `StatusConflictFailure`, commit `318c84d`

### The shared root cause

`markPaid`, `markRefunded` and `checkIn` are all transactional and all
re-read state before writing — `checkIn` has an entire documented
stale-ticket matrix behind it. `setStatus` and `cancelByRider` are plain
unconditional `update` calls. The money and check-in paths were hardened;
the status path was not, and it moves the same document.

### BUG-013 — an in-flight approval resurrects a cancelled booking

The trainer's request list is a live stream, so a row can be tapped moments
after the rider cancels it. `setStatus` writes `confirmed` over
`cancelled` without looking, and then notifies: the rider is told "Booking
approved ✅" for a session they cancelled, and the hour goes back to
blocking the trainer's calendar (§8.5, `isLive`).

The `_busy` guard in §10.5 protects against a double tap on the same
control. It does nothing about state that changed underneath.

### BUG-014 — a rider can cancel a delivered session and erase the earnings

Pinned by a passing test that follows the money:

```
2h at €50  ->  confirmed  ->  completed  ->  markPaid   earnings: €100
                           rider cancels                earnings:   €0
```

`trainerRevenueProvider` is Σ `totalPrice` over bookings whose status is
`completed` ([providers.dart:395](lib/providers/providers.dart#L395)). Once
the rider flips a completed booking to `cancelled`, it leaves that set, and
€100 of delivered, settled work disappears from the trainer's revenue. The
payment record survives on the document — `paidAt` is still there — so the
booking is simultaneously paid and cancelled, and the two figures disagree.

Reachable from the app's own UI: the rider's Sessions list offers Cancel,
and nothing filters it by whether the session already ran.

### Fix

Give both writes the same treatment `markPaid` already has: a transaction
that re-reads `status` and refuses a transition out of a terminal state
(`completed`, `cancelled`, `rejected`), throwing the way `CheckInFailure`
does so the UI can say why. Two frozen methods change, so this needs your
say-so — and BUG-014 deserves it soon, because it is live and it is money.

---

## BUG-015 — `createBooking` accepts a non-contiguous selection

**Severity:** minor (latent — unreachable from the UI)
**Found:** `test/flow_collision_test.dart`
**File:** [booking_repository.dart](lib/data/repositories/booking_repository.dart)
**Status:** FIXED

Booking `['10:00', '15:00']` succeeds. Duration is the *count* of selected
hours, so the window is cut as start + 2h: the booking claims 10:00 and
15:00 on the calendar but records `endTime: '12:00'`, and any consumer
reading the range rather than `selectedTimes` sees a two-hour 10:00-12:00
session that does not match the hours actually held.

§8.4's contiguous-run rule lives in the booking grid's `_tapSlot`, so this
selection cannot be produced by the app. `createBooking` itself does not
re-check it, which makes the invariant a property of one widget rather than
of the write.

Originally left alone as a design call. The BUG-017 fix settled it:
`createBooking` now writes an occupied availability doc that is one
`[start, end)` range and *cannot represent a gap*, so the write must hold
the contiguity invariant itself. `createBooking` refuses non-consecutive
hours with an `ArgumentError`; the pinned-behaviour test flipped to assert
the refusal writes nothing.

---

## NOTE — what the Dart harness cannot verify

Not a defect in the app, but it shapes every concurrency claim in
COVERAGE.md, so it is recorded here.

`fake_cloud_firestore.runTransaction` provides **no isolation**. A probe of
two concurrent transactions that each read a counter and write `read + 1`
lands on **1**, not 2 — a plain lost update.

Consequence: no test in `test/` can verify a transactional-isolation claim.
That covers safari seat capacity (§8.6), `markPaid`'s double-settle guard,
`checkIn`, and `blockUser`/`unblockUser`. Those tests verify their
*precondition logic*, which is real and worth having; they say nothing
about contention.

Three concurrent `reserveSafariSeat` calls against a two-seat trip sell
three seats **in the fake** — which reads exactly like an overselling bug
and is not one. `test_rules/transactions.test.mjs` settles it against real
Firestore on the emulator: the third rider is refused, `bookedSeats` lands
on 2, and the trip flips to `full`. §8.6's claim holds.

That file exercises the *pattern* the repository uses, not the Dart code —
`flutter test` cannot reach an emulator. Closing that last gap needs an
`integration_test` run on a device pointed at the emulator.

Two more divergences found the same way, both now settled in
`test_rules/arrays.test.mjs`:

| Behaviour | Real Firestore | fake_cloud_firestore |
|---|---|---|
| `arrayUnion` of an identical value twice | collapses to one | appends both |
| transactional `update` of a missing doc | rejects (NOT_FOUND) | creates it |
| snapshot stream after a **transactional** write | re-emits | may not |

The last one is the dangerous one, because it fails *silently in the
app's favour*. `watchUser(uid).first` returned a profile reading `active`
for an account the database had already stored as `blocked` — a
transactional `blockUser` had committed, and the stream had not re-emitted.
A test written the obvious way therefore asserts the suspension did not
take effect, and passes for the wrong reason.

`test/flow_approval_test.dart` and `test/flow_moderation_test.dart` both
read profiles with a direct `get()` for this reason; the comment is on the
helper in each. Any future test asserting state after `blockUser`,
`unblockUser`, `markPaid`, `markRefunded`, `checkIn` or `reserveSafariSeat`
needs the same treatment.

---

## BUG-016 — A user can file more than one appeal, and only ever sees one

**Severity:** minor
**Found:** `test/flow_moderation_test.dart`, adversarial pass
**Files:** [support_repository.dart](lib/data/repositories/support_repository.dart),
§6.2 (`My appeal` — `userId == uid`, limit 1)
**Status:** FIXED

`submitAppeal` always `add`ed a new document; the user's screen showed one
appeal while the admin queue showed both, so staff could answer the one the
user was not looking at and the thread appeared dead from both ends.
(`watchMyAppeal`'s half — an unordered `limit(1)` returning an arbitrary
document — had already been fixed to surface the most recent.)

Of the two candidate fixes, "refuse a second appeal while one is pending"
matches the screen that exists: it renders exactly one thread. The guard is
per open case, not per lifetime — a user suspended a second time appeals a
second time once the first is decided; both directions are pinned. The
refusal is its own type, `DuplicateAppealFailure`, because the generic
"try again" toast would invite exactly the retry the guard refuses; the
blocked screen closes the sheet instead, revealing the open thread behind
it.

---

## BUG-017 — A rider cannot read a trainer's day, so no rider can ever book

**Severity:** critical (total blocker on live Firestore)
**Found:** reported from the device; reproduced in `test_rules/booking_reads.test.mjs`
**File:** [firestore.rules](firestore.rules) — `match /bookings`, `allow read`
**Status:** FIXED — option B built; deploy + backfill pending

### What

```
allow read: if signedIn() && (isParty() || isStaff());
```

`isParty()` resolves per document. `_assertSlotsFree` and `watchDayBookings`
both query:

```
bookings where instructorId == <trainer> && date == <day>
```

That query is not constrained to documents the rider is a party to, so
Firestore rejects the whole list. Two tests fail against the deployed rules:

- `bookings: a rider reads the trainers booked hours for the day`
- `the clash re-check — a rider can run it`

### The chain to the toast

1. rider taps **Confirm** → `createBooking`
2. `createBooking` → `_assertSlotsFree` → `.get()` on the query above
3. rules deny it → `FirebaseException(permission-denied)`
4. the `on SlotTakenFailure` catch does not match, so the generic `catch (e)`
   in [booking_screen.dart:387](lib/features/booking/booking_screen.dart#L387)
   runs
5. → "Couldn't send your request. You don't have access to this yet."

Staff pass via `isStaff()`, which is why the same screen works when signed in
as an admin and fails as a rider — and why it was not caught by hand.

**Pre-existing.** The rule is byte-identical at `90ca448`, before this work.
No rider has ever completed a booking against live Firestore.

### Why my rules suite missed it

`bookings.test.mjs` tested per-document reads and the two *authorised* filter
shapes (`kiterId == self`, `instructorId == self`). It never ran the
`instructorId + date` shape the app actually uses. COVERAGE.md named this
class of gap — "a rule can be correct and still reject the app" — and then
the suite demonstrated it.

### The fix is a choice, not a one-liner

The rider needs the *occupied hours*. The booking document also carries the
other rider's name, message and price, and rules cannot project fields.

- **A — widen the read rule.** One line, unblocks immediately. But rules
  cannot see query filters, so any third disjunct that is true for a signed-in
  user makes the whole collection listable: every rider's name, message and
  price, platform-wide. A real privacy regression.
- **B — write `availability` docs for booked hours.** §8.5 already specifies
  blocks as `status: 'host-blocked' | 'occupied'` — the `occupied` half is
  designed and never written. The grid and the clash check would read
  `availability`, which is already world-readable to signed-in users, and
  bookings stay private. Correct, and matches the existing schema; needs
  `createBooking`, `setStatus` and `cancelByRider` to maintain it, plus a
  backfill.
- **C — a Cloud Function** maintaining a public busy-slots document. Blocked:
  Functions are disabled on this project.

### Fix (applied) — option B, after A ran as the marked stopgap

A live booking now maintains `availability/{bookingId}` with
`status: 'occupied'`: written in `createBooking`/`createWalkIn`'s batch,
deleted inside `_writeIfLive`'s transaction on any terminal transition, and
carrying the hours and nothing else — no name, no message, no price
(`booking_reads.test.mjs` pins the doc's key set). The grid's occupied docs
land in `booked` so they read "Booked" and are not releasable from the
schedule tab; `_assertSlotsFree` reads both calendars and lets a readable
booking supersede its own occupied doc; `dayAvailabilityProvider` treats
the bookings stream's permission-denied as "no bookings visible". The
rules authorise the rider's occupied-doc writes through `getAfter` on the
sibling booking in the same atomic commit, and the temporary
`allow read: if signedIn()` is reverted to `isParty() || isStaff()` — the
four TEMPORARY tests flipped back to the denials they were the checklist
for.

**Backfill:** bookings created while the stopgap was live have no occupied
docs; until each is backfilled (staff may create occupied docs directly —
tested) or reaches a terminal status, its hours are invisible to *other
riders'* grids only. The trainer's own calendar still shows them, and the
clash check for the trainer still sees them, so the §8.6 recovery (decline
one) covers the gap.

---

## BUG-018 — A user can pre-load the status a future unblock will restore

**Severity:** major (privilege escalation, two-step)
**Found:** this pass, while fixing BUG-012 — reading what `unblockUser`
restores made it obvious the restored value was user-writable
**File:** [firestore.rules](firestore.rules) — `privilegedFieldsUnchanged()`
**Status:** FIXED — deploy pending

`privilegedFieldsUnchanged()` named `role`, `status`, `blockedUntil`,
`blockedAt`, `reviewedAt` and `reviewNote` — but not `statusBeforeBlock`,
which `unblockUser` restores **verbatim**. A pending trainer could write
`statusBeforeBlock: 'active'` on their own profile (an ordinary self-update
the rules accepted), and any later block-then-unblock cycle would hand them
`active` without ever passing review.

Convoluted — it needs staff to block and unblock them — but it is exactly
the laundering path BUG-012's `restoreToPending` semantics exist to
prevent, reachable by any user, silently. `statusBeforeBlock` is now on the
privileged list; the denial test sits in the `privilegedFieldsUnchanged`
loop in `users.test.mjs`.

---

# Full-application audit — 2026-08-13 (CLAUDE_FULL_AUDIT.md)

The pass that follows re-ran the baseline suites (780 Dart / 360 rules, all
green) and then went where no adversarial pass had run: the money code that
landed after the fix-everything pass closed (`d37e123`). Its single systemic
finding: **the repository enforces a set of money and state-machine
invariants that the security rules do not.** `_writeIfLive`, `markPaid`,
`reserveSafariSeat` all re-read and refuse; the rules — the only authority a
hand-rolled Firestore client is bound by — are more permissive than the
methods. New coverage lives in `test_rules/escrow.test.mjs`.

## BUG-019 — Terminal booking states are not terminal at the API

**Severity:** critical (money — ledger-corrupting today, PSP-executed loss later)
**Found:** `test_rules/escrow.test.mjs`, terminal-states group
**File:** [firestore.rules](firestore.rules) — bookings `allow update`
**Status:** FIXED — deploy pending

BUG-013/014 hardened the *repository*: `_writeIfLive` re-reads `status` in a
transaction and refuses to move a booking out of `completed`, `cancelled`
or `rejected`. The rules never got that guard. BUG-001 closed the rider's
writable *field set* (`riderFieldsOnly`) and BUG-003 the trainer's
(`providerFieldsOnly`), but neither constrained the *from-state*, so against
a raw SDK:

| Write the rules accepted | What it does |
|---|---|
| rider: `completed` → `cancelled` (stamped) | `settle()` moves the session from `payoutDue` to `refundDue` — a delivered, settled lesson's price taken off the trainer and handed back to the rider. This is BUG-014 exactly, re-opened at the layer BUG-014 did not touch. |
| trainer: `cancelled` → `completed` | the reverse: a refund-due booking flipped to payout-due. |
| trainer: `cancelled`/`rejected` → `confirmed` | resurrects a dead booking onto the calendar. This is BUG-013 at the API. |

The repository blocks all three; a hand-rolled client did not. Earnings are
Σ `totalPrice` over `completed` bookings, so every one of these desyncs the
trainer's revenue from what was actually delivered — and once a PSP executes
`EscrowState`, it becomes real money moving the wrong way.

### Fix

A `statusStays()` guard on both party branches (not staff, who must be able
to correct history): if the write changes `status`, the *prior* status may
not be terminal. It gates only status-moving writes, so settlement
(`markPaid`/`markRefunded` write payment fields on a `completed` booking)
and history-hiding are untouched — pinned by passing allow-tests. Staff keep
the override, pinned by `staff may move history`.

## BUG-020 — A trainer can sign their own cancellation as the rider's

**Severity:** major (money)
**Found:** `test_rules/escrow.test.mjs`, provider-cancel group
**File:** [firestore.rules](firestore.rules) — `providerFieldsOnly()`
**Status:** FIXED — deploy pending

`cancelledBy` decides who the escrow favours: a *provider* cancel always
refunds the rider in full (the late fee protects committed hours, never a
trainer's own withdrawal); a *late user* cancel is charged in full. The
rider was pinned to `cancelledBy == 'user'` (BUG-001's
`riderStatusIsCancellation`), but `providerFieldsOnly()` never constrained
the value — so a trainer could cancel their own session, sign it
`cancelledBy: 'user'` with a late timestamp, and `settle()` would read it as
a rider no-show and keep the money as a payout to the trainer who withdrew.

### Fix

`providerCancelSigned()`: a provider write that sets `status: 'cancelled'`
must carry `cancelledBy: 'provider'`. The trainer's real cancel
(`setStatus` always writes `'provider'`) is pinned; the forged `'user'`
signature is denied.

## BUG-021 — A trainer can forge the escrow's executed states

**Severity:** major (ledger integrity)
**Found:** `test_rules/escrow.test.mjs`, held-money group
**File:** [firestore.rules](firestore.rules) — `providerFieldsOnly()`
**Status:** FIXED — deploy pending

`payment.dart` is explicit that `paid_out` ("FLOW actually transferred the
held money to the trainer") is *"written by the processor/Functions layer
(or staff), never by either party,"* and `markPaid` refuses to let a trainer
"collect" a `held` booking in cash because the rider already paid FLOW. Both
invariants lived only in the repository: `providerFieldsOnly()` lists
`paymentStatus` with no value constraint, so a raw trainer client could
write `paid_out` (forging FLOW's transfer), or overwrite a `held` booking to
`paid`/`refunded` (converting escrow FLOW holds into a cash claim, so the
booking reads settled while the rider's money is still in FLOW's float).

### Fix

`providerPaymentOk()`: if the write touches `paymentStatus`, the prior
status may not be `held` (escrow is FLOW's to execute) and the new value may
not be `paid_out`. The cash ledger a trainer *does* own — `unpaid` → `paid`,
`paid` → `refunded` — is pinned by passing allow-tests; staff keep the
escrow-execution door, pinned by `staff still execute the escrow`.

## BUG-022 — Safari seat reservation is dead on live Firestore

**Severity:** critical (total blocker — no rider can book a safari seat)
**Found:** `test_rules/escrow.test.mjs`, safari group
**File:** [firestore.rules](firestore.rules) — bookings `allow create`
**Status:** FIXED — deploy pending

The BUG-017 pattern, second instance. P5 (Instant Book) constrained the
booking `create` rule so a rider-written `confirmed` status is accepted only
when `trainerAllowsInstant()` — the *trainer's* `instantBook` flag. But
`reserveSafariSeat` writes every seat booking born `confirmed` (the host
published the trip; there is nothing to approve), and a safari host has no
reason to have toggled Instant Book. So the create is denied, the reserving
transaction throws `permission-denied`, and **no rider can reserve a safari
seat against the real rules at all.**

Why nothing caught it: `booking_repository_test` runs on the fake (rules
ignored); `transactions.test.mjs` runs with `withSecurityRulesDisabled`;
`payloads.test.mjs` never transcribed the safari create. Exactly the class
COVERAGE.md named — "a rule can be correct and still reject the app."

### Fix

`reservesASeat()`: a `confirmed` create is also legitimate when it is a
`type: 'safari'` booking whose named trip is hosted by the booking's
instructor *and* consumes exactly one seat on that trip in the same commit
(`getAfter(trip).bookedSeats == get(trip).bookedSeats + 1`). This mirrors
the occupied-doc `getAfter` (§8.5): the booking's right to be born confirmed
is proven by the sibling seat move in the same atomic batch. It also closes
the ghost-passenger residue BUG-006 flagged — a seat booking that moves no
seat is now denied (`DENY the ghost passenger`). The hourly Instant-Book
path is unchanged and still pinned by the existing `bookings.test.mjs`
group.

## BUG-023 — A booking can be born checked-in or pre-stamped

**Severity:** minor (latent — cannot be converted to money without the trainer)
**Found:** `test_rules/escrow.test.mjs` (documented, not asserted as denials)
**File:** [firestore.rules](firestore.rules) — bookings `allow create`
**Status:** reported only — not fixed

The create rule constrains `kiterId`, `paymentStatus` and `status`, but not
`checkedIn`, `startedAt`, `cancelledAt` or `cancelledBy`, so a rider can
create a booking already carrying those. It is latent: `settle()` reads
`cancelledAt` only when `status == 'cancelled'`, and no earnings or escrow
path reads `checkedIn` — reaching money still needs a `completed` status the
rider cannot write (`riderFieldsOnly`), which only the trainer can set, and
the trainer's own check-in is idempotent against a pre-set flag. Not fixed
because the booking `create` rule does not use `hasOnly` (a booking has ~25
legitimate fields) and the harm is unreachable without a second party's
cooperation. Flagged so a future `create` field-lockdown includes them.

## BUG-024 — Publishing a safari trip skips the block-and-role gate

**Severity:** major (a suspended account keeps publishing; junk-content surface)
**Found:** `test_rules/escrow.test.mjs`, publishing group
**File:** [firestore.rules](firestore.rules) — safari_trips `allow create`
**Status:** FIXED — deploy pending

`allow create: if signedIn() && hostId == uid()` was the whole rule. Every
*other* user-content create in the file carries `notBlocked()` (BUG-007);
safari trips did not, so a suspended business could keep publishing bookable
trips while blocked from everything else. It also placed no role constraint,
so any account — a rider, a `pending` or `rejected` business — could publish
a commercial, reservable trip, though the app has no UI that creates trips
(they are seeded), which held the blast radius to a raw SDK.

### Fix

`isActiveBusiness()` (`role == 'business' && status == 'active'`,
`exists()`-guarded so it fails closed) is now required alongside
`hostId == uid()`. This matches Explore's own membership rule (§8.8) and the
suspension model: only an approved, live business publishes a trip. Denials
pinned for blocked, rider and pending hosts; the active-business allow
pinned.

## NOTE — the rider cancellation timestamp is still trusted, deliberately

Not fixed, because the code says so on purpose. `cancellation.dart` and the
`riderStatusIsCancellation` comment both state that only the *presence* of
`cancelledAt` is provable in rules and that "the timestamp's honesty is the
processor's to verify when it executes the refund." A rider can therefore
still backdate `cancelledAt` on a *live* booking to claim the free-cancel
window (turning a `payoutDue` late cancel into a `refundDue` one). BUG-019's
terminal guard closes the worst case (backdating a *completed* booking's
cancel); what remains is the free-window edge on a confirmed booking, latent
until a PSP executes refunds. Pinning it needs `cancelledAt == request.time`,
which is a cheap and faithful change (the repository already writes
`serverTimestamp()`), but it overrides an explicit, documented design
decision — so it is surfaced here for the owner's call rather than changed
unilaterally.

## BUG-025 — A declined trainer is bounced off their own support ticket

**Severity:** major (a support lifeline is half-broken; P12 regression)
**Found:** full-audit pass 2026-08-13, reading the router gate against the
routes P12 added
**File:** [lib/router.dart](lib/router.dart) — `gateRedirect`, `rejected` case
**Status:** FIXED — `test/gate_redirect_test.dart`

The gate lets an `AppStage.rejected` user reach `/support` — a declined
trainer must be able to talk to a human — but the allow-list matched the
path *exactly* (`loc == '/support'`). P12 extracted the ticket thread into
its own pushed route, `/support/ticket/:id`. So a declined trainer could
open the support list, file a ticket, and be bounced straight back to
`/rejected` the instant they tapped it to read the reply. The lifeline let
them speak and not listen.

### Reproduction

Signed in as a `rejected` trainer, `gateRedirect(AppStage.rejected,
'/support/ticket/abc', isTrainer: true)` returned `'/rejected'` instead of
`null` — the redirect fires on every navigation, including a `push`, so the
thread screen was replaced by the rejected gate before it painted.

### Fix

The redirect closure was inlined and untestable; extracted it to a pure
`gateRedirect(stage, loc, {isTrainer})` — the whole route-authorization
table in one place — and widened the `rejected` allow-list to
`loc == '/support' || loc.startsWith('/support/')`. `gate_redirect_test.dart`
now pins every stage's allow-list and a denial, including this thread route
and a `/supportish` lookalike that must still bounce. Behaviour is otherwise
identical to the inlined closure.

## BUG-026 — "Tap to rate your trainer" lands on the wrong tab, in-app only

**Severity:** minor (dead-ends the review prompt; breaks a documented invariant)
**Found:** full-audit pass 2026-08-13, notification fan-out sub-audit
**File:** [lib/features/notifications/notifications_screen.dart](lib/features/notifications/notifications_screen.dart) — `_open`, `NotificationKind.review`
**Status:** FIXED

A completed session writes a `type: 'review'` notification — "Session
complete 🎉 / Tap to rate your trainer." — **carrying the bookingId**
([booking_repository.dart:620-627](lib/data/repositories/booking_repository.dart#L620-L627)).
The in-app tap handler ignored it and navigated to a bare `/sessions`, which
opens on the Upcoming tab. The completed booking — and the only rate button
(`SessionAction.rate`) — is on the History tab. So the notification that
says "tap to rate" dropped the rider on a tab that neither contains the
session nor offers a rating.

The push handler routes the *same* notification correctly:
[push_service.dart:132-139](lib/services/push_service.dart#L132-L139) keys off
`bookingId.isNotEmpty`, not the type, so it lands on
`/sessions?highlight=$bookingId`, which switches to History and scrolls the
card in. push_service's own header (lines 103-104) states the invariant the
two paths broke: *"Every branch mirrors `_NotificationTile._open` — the two
views of one notification must not land in two places."*

### Fix

The `review` case now mirrors the booking cases beside it:
`/sessions?highlight=${bookingId}` when present. In-app and push land in the
same place again. No dedicated widget-nav test added — the fix makes the
in-app branch identical to the push branch that already served as the
reference, and to the adjacent booking cases the existing tests cover — but
it is called out here so the parity is not silently re-broken.

## BUG-027 — Revenue counts a refunded-but-completed session as earnings

**Severity:** minor (latent — no UI path reaches it today)
**Found:** full-audit pass 2026-08-13, reporting sub-audit
**File:** [lib/providers/providers.dart](lib/providers/providers.dart) — `trainerRevenueProvider` (and month/week variants)
**Status:** FIXED — ordered 2026-08-15 ("fix any small bug"); `_earned` guard on all
three figures, pinned by `test/earnings_refund_test.dart`

`trainerRevenueProvider`, `trainerMonthRevenueProvider` and
`trainerEarningsWeekProvider` sum `totalPrice` over bookings whose *status*
is `completed`, without consulting `payment.status`. A booking that is
`completed` **and** `refunded` would be counted at full price and rendered
in the completed-sessions list with no distinguishing pill.

Not reachable through the app today: `markRefunded` has no UI caller, and
the escrow derivation never yields `refundDue`/`refunded` for a `completed`
booking (only for dead ones). It becomes live the moment a "Payment or
refund" ticket is ever resolved by refunding a delivered session (staff or
the future Functions/PSP layer) — exactly the flow P1 anticipates. The fix
is a one-line guard per provider (`&& b.payment.status != refunded`), but
`lib/providers/` is approval-gated (CLAUDE.md) and the issue is latent, so
it is surfaced for the owner rather than changed unilaterally. Pair it with
wiring the refund action.

## BUG-028 — Weekly-earnings bars can shift a day across a midnight DST change

**Severity:** minor (display distribution only; the week total is correct)
**Found:** full-audit pass 2026-08-13, reporting sub-audit
**File:** [lib/providers/providers.dart](lib/providers/providers.dart) — `trainerEarningsWeekProvider` (`.inDays` bucketing)
**Status:** FIXED — ordered 2026-08-15 ("fix any small bug"); `_weekStart` and the
bucket index now use calendar arithmetic (`_calendarDays`, UTC-anchored), never
`Duration` subtraction

The provider buckets each completed booking into a weekday with
`day.difference(weekStart).inDays`, and `Duration.inDays` truncates elapsed
real time. The stated deploy timezone is Africa/Cairo, whose DST transitions
fall at **midnight** — so in the single week containing a spring-forward, the
interval from Monday-midnight is 24h·n − 1h and truncates one day short,
moving that day's earnings into the previous weekday's bar and mis-placing
the "today" highlight by one. The weekly **total** (a plain sum) is
unaffected — only the per-bar distribution and highlight, for one week a
year. Left as documented: the fix is calendar-date differencing rather than
`Duration.inDays`, in an approval-gated file, for a cosmetic edge.

## BUG-029 — Leaving the Profile tab left its frozen frame over the whole app

**Severity:** major (the shell looks dead; every tab switch away from a
higher branch shows the old screen forever)
**Found:** on-device (Galaxy A56, release APK), reproduced over adb
2026-08-15; screenshot shows the bar selecting Discover with Profile still
painted
**File:** [lib/features/shell/app_shell.dart](lib/features/shell/app_shell.dart) — `AnimatedBranchContainer` (P12)
**Status:** FIXED — ticker stays enabled until the exit fade completes;
pinned by `test/branch_fade_test.dart`

P12's cross-fade wrapped each branch in `TickerMode(enabled: i ==
currentIndex)` + `AnimatedOpacity`. The mute is correct at rest and wrong in
the transition frame: the outgoing branch's fade-out runs on the ticker that
was muted in that same rebuild, so the animation never advanced and the
branch stayed at opacity 1. Branches paint in declaration order — Profile is
branch 5, topmost — so leaving Profile left its stale frame covering every
tab. Navigation kept working underneath (the stale layer ignores pointers);
only the pixels were stuck, which is why it read as "the app is stuck".
Switching low→high looked fine (the incoming branch fades in on top), which
is how it survived manual testing until Profile — the highest branch — was
visited.

Fix: the container is stateful; a branch's ticker stays enabled while it is
current *or* mid-exit, and `AnimatedOpacity.onEnd` mutes it once the fade
reports done — the battery contract (invisible branches do not animate)
holds at rest, without freezing the exit.
