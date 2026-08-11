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
**Status:** fix written, awaiting approval to deploy

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

**Severity:** major (unverified — awaiting a decision on intent)
**Found:** rules suite, while scoping BUG-001
**File:** [firestore.rules:120-123](firestore.rules#L120-L123)
**Status:** not fixed — needs a decision, see COVERAGE.md

`isProvider()` is checked first and carries no field restriction at all, so
the trainer on a booking may write `instructorId` and hand the session to
someone else, who then has a booking on their calendar they never accepted.

Not fixed with BUG-001 because, unlike the rider case, I cannot tell from
the blueprint whether this is intended (a station reassigning between its
instructors is a plausible real feature). §6.3 lists no write that changes
`instructorId`, which suggests it is not intended — but absence from a
write list is not the same as a stated prohibition.

**Question for you:** should a trainer be able to move a booking to another
trainer? If no, the same `hasOnly` treatment applies to the provider branch.

---

## BUG-004 — Review eligibility is unenforceable outside the app

**Severity:** major (by design, but worth a decision)
**Found:** rules suite, `test_rules/reviews.test.mjs`
**File:** [firestore.rules:151-161](firestore.rules#L151-L161)
**Status:** not fixed — needs a decision

The rules pin authorship and the 1-5 range. Everything §8.9 specifies —
a **completed**, **unreviewed** booking with **that** trainer — lives in
`ReviewRepository`, which a direct Firestore client simply does not run.
Four writes the rules accept today:

- a review whose `bookingId` refers to no booking at all
- two reviews for the same `bookingId` (the repository's no-op guard is
  client-side only)
- a trainer reviewing themselves
- a blocked user writing a review

The rules comment states the split deliberately, so this is documented
behaviour rather than an oversight. It is listed because BUG-001 made it
reachable: a rider could self-complete a booking and then review it. With
BUG-001 fixed the escalation path is closed, but direct fabrication is not.

Closing it properly needs a rule that reads the booking
(`get(/bookings/$(bookingId)).data.status == 'completed'` and
`.kiterId == uid()`), which costs one extra document read per review write.
Not applied unilaterally: it changes the enforcement model.

---

## BUG-005 — Any signed-in user can send any user a notification

**Severity:** major (by design; spoofing and spam surface)
**Found:** rules suite, `test_rules/misc.test.mjs`
**File:** [firestore.rules:196-200](firestore.rules#L196-L200)
**Status:** not fixed — needs a decision

`allow create: if signedIn()` with no constraint on `targetUserId`, title,
body or `type`. The comment explains why it is open — the app notifies the
*other* party, so the writer is never the recipient — but the consequence
is that any account can write a convincing "Booking cancelled" or "Booking
approved ✅" notification to any user, and it will render identically to a
genuine one and route into their sessions list (§11.2).

A tighter rule cannot simply require `targetUserId != uid()`; it would need
to tie the notification to a booking or chat the sender is party to.

---

## BUG-006 — Any signed-in user can rewrite any safari trip

**Severity:** major
**Found:** rules suite, `test_rules/misc.test.mjs`
**File:** [firestore.rules:261-268](firestore.rules#L261-L268)
**Status:** not fixed — needs a decision

`allow update: if signedIn()` is justified in the comment for one field:
`bookedSeats`, incremented by the reserving rider inside the transaction.
It authorises every other field too, so any signed-in user can set a trip's
`price` to 0, its `capacity` to 999, or its `status` to `full` — closing a
competitor's trip.

The same `hasOnly` treatment as BUG-001 fits: a non-host may change only
`bookedSeats` and `status`. Not applied unilaterally because the safari
flow is outside the six flows in scope and I have not traced its writes.

---

## BUG-007 — Suspension is a client-side gate only

**Severity:** major
**Found:** rules suite, `test_rules/misc.test.mjs`
**File:** [firestore.rules](firestore.rules) (absence of a rule)
**Status:** not fixed — needs a decision

No rule anywhere reads `status`. A blocked account keeps a valid Firebase
token and, at the API, retains the ability to read profiles, create
bookings, send chat messages, write reviews and file reports. The block is
enforced entirely by the client's gate routing (§2.3), which stops the app's
own UI from offering those actions and nothing else.

Filing an appeal *must* stay available (§3.12, and the rules comment on
appeals says so). The rest arguably should not be.

The fix is one function — `notBlocked()` reading `selfProfile().status` —
added to the write rules for bookings, chats, reviews and reports. It costs
one `get()` per write on rules that mostly already pay for one.

---

## BUG-008 — A chat participant can rewrite the participants array

**Severity:** critical (privacy breach + denial of access)
**Found:** rules suite, `test_rules/chats.test.mjs`
**File:** [firestore.rules:164-189](firestore.rules#L164-L189)
**Status:** fix written, awaiting approval to deploy

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
**Status:** not fixed — blueprint edit, needs your say-so

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
**File:** [APP_LOGIC_BLUEPRINT.md](APP_LOGIC_BLUEPRINT.md) §6.3, §11.1
**Status:** not fixed — blueprint edit, needs your say-so

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
[social.dart:157-167](lib/data/models/social.dart#L157-L167)
**Status:** not fixed — reported only

`AdminRepository` writes `type: 'account_approved'` and
`type: 'account_rejected'`. `NotificationKind.parse` has a case for neither,
so both fall through to `_ => system` and route to a plain text sheet
(§11.2) rather than anywhere useful. §11.1's table does not list them
either, so all three places were written independently.

Harmless as it stands — a text sheet is a reasonable destination for "your
application was reviewed" — but it is unintended rather than chosen, and
the approval notification arguably belongs on the trainer's own profile.

---

## BUG-012 — Approving a blocked account silently voids the suspension, and a later unblock then demotes them

**Severity:** major (latent — not reachable from today's UI)
**Found:** `test/flow_approval_test.dart`, adversarial pass
**File:** [admin_repository.dart](lib/data/repositories/admin_repository.dart)
**Status:** not fixed — needs a decision

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

The fix is to clear `blockedUntil` and `statusBeforeBlock` in
`approveTrainer`, `rejectTrainer` and `restoreToPending` — a change to a
frozen repository, so it needs your approval, and I would want the
blocked-users UI decided first since that is what determines the intended
semantics.

---

## BUG-013 / BUG-014 — Booking status writes have no preconditions

**Severity:** BUG-013 major · BUG-014 **critical** (money)
**Found:** `test/flow_booking_test.dart`, adversarial pass
**File:** [booking_repository.dart:319-323](lib/data/repositories/booking_repository.dart#L319-L323),
[booking_repository.dart:444-449](lib/data/repositories/booking_repository.dart#L444-L449)
**Status:** not fixed — frozen repository, needs your approval

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
**File:** [booking_repository.dart:140-160](lib/data/repositories/booking_repository.dart#L140-L160)
**Status:** not fixed — reported only

Booking `['10:00', '15:00']` succeeds. Duration is the *count* of selected
hours, so the window is cut as start + 2h: the booking claims 10:00 and
15:00 on the calendar but records `endTime: '12:00'`, and any consumer
reading the range rather than `selectedTimes` sees a two-hour 10:00-12:00
session that does not match the hours actually held.

§8.4's contiguous-run rule lives in the booking grid's `_tapSlot`, so this
selection cannot be produced by the app. `createBooking` itself does not
re-check it, which makes the invariant a property of one widget rather than
of the write.

Left alone because the guard belongs next to the rule it enforces, and
deciding where that is — the repository, or `BookingMath` beside
`leadingRun` — is a design call rather than a fix.

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
**Files:** [support_repository.dart:109-124](lib/data/repositories/support_repository.dart#L109-L124),
§6.2 (`My appeal` — `userId == uid`, limit 1)
**Status:** not fixed — reported only

`submitAppeal` always `add`s a new document, with no check for an existing
one. `watchMyAppeal` reads `where('userId', ==, uid).limit(1)`.

So a user who submits twice creates two appeals; their own screen shows
whichever the limit-1 query returns, while the admin queue shows both. If
staff answer the one the user is not looking at, the reply is invisible to
them and the thread appears dead from both ends.

Whether the fix is "refuse a second appeal while one is pending" or "show
them all" is a product decision.
