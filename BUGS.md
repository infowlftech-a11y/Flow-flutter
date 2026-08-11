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
