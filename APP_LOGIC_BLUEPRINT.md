# FLOW — Application Logic Blueprint

**Purpose of this document.** A complete, implementation-independent specification of
what the FLOW app *does*. It is written to be the sole context for a ground-up UI/UX
redesign: every rule, flow, data shape, validation and edge case below must survive
that redesign, even though no layout or visual decision needs to.

Nothing here describes styling. Where a visual detail is mentioned, it is because it
carries meaning (e.g. "blocked hours are not tappable"), not because it should look
that way.

- **Codebase:** Flutter / Dart SDK ^3.12.2, Android only (`com.wlftech.flow`)
- **Backend:** Firebase — Auth, Firestore, Storage, Cloud Messaging (project `wlf-flow`)
- **Server code:** `functions/` (TypeScript, Firebase Functions v2) — push fan-out and
  scheduled session reminders
- **State:** Riverpod 3 · **Routing:** go_router 17 · **Local prefs:** shared_preferences
- **Source of truth:** `lib/`, 89 Dart files, ~22.5k lines

> **There is no AI integration.** No Gemini, no Google AI Studio, no LLM API, no prompt
> templates, no system instructions. The predecessor React app imported `GoogleGenAI`
> but never called it, and `geminiService.ts` was never imported by anything; both were
> intentionally dropped. Section 12 documents the complete set of external calls. If the
> redesign is expected to *add* AI, it is a new feature with no existing contract to honour.

> **Backend provisioning is incomplete, and it shapes what can be demonstrated.** Firebase
> Storage has never been initialised on `wlf-flow`, so every upload path fails — avatars,
> galleries, certificates and evidence attachments. The Cloud Functions API has never been
> enabled, so no push has ever been delivered. Firestore is in `nam5` (US), which adds a
> transatlantic round trip to every read and write for an Egyptian user base. None of these
> are app defects and none are fixed by a redesign, but a redesign that assumes rich imagery
> will be designing for data that cannot currently exist.

---

## Table of contents

1. [Core concept & value proposition](#1-core-concept--value-proposition)
2. [Roles, account lifecycle & the gate state machine](#2-roles-account-lifecycle--the-gate-state-machine)
3. [Capability catalogue](#3-capability-catalogue)
4. [Navigation map & user flows](#4-navigation-map--user-flows)
5. [Data models — field by field](#5-data-models--field-by-field)
6. [Firestore schema — every read and write](#6-firestore-schema--every-read-and-write)
7. [State management — the Riverpod graph](#7-state-management--the-riverpod-graph)
8. [Business logic rules](#8-business-logic-rules)
9. [Form validation rules](#9-form-validation-rules)
10. [Edge cases, loading, errors & micro-interactions](#10-edge-cases-loading-errors--micro-interactions)
11. [Notifications — in-app and push](#11-notifications--in-app-and-push)
12. [External services & API contracts](#12-external-services--api-contracts)
13. [Constants & configuration](#13-constants--configuration)
14. [Known limitations, quirks & deliberate behaviours](#14-known-limitations-quirks--deliberate-behaviours)
15. [Redesign checklist — what must not be lost](#15-redesign-checklist--what-must-not-be-lost)

---

## 1. Core concept & value proposition

FLOW is a **two-sided marketplace for kitesurfing instruction on the Egyptian Red Sea
coast**. Riders find certified trainers, book hours on the water, and check in on the
beach with a QR code. Trainers run their business from a dashboard: approve requests,
control their calendar, take walk-ins, and track earnings.

**Who it is for**

| Audience | Role value | What they do |
|---|---|---|
| **Riders ("kiters")** | Find and book trusted, certified instruction | Browse trainers, filter by spot/language, book hours, message, check in, review |
| **Trainers (individuals)** | Fill their calendar; run the day | Approve/decline requests, block hours, add walk-ins, scan riders in, finish sessions |
| **Stations & safari operators** | Sell multi-instructor lessons, rentals, beach passes, expeditions | Same as trainers, plus a catalogue of instructors/services/trips |
| **Admins & support** | Moderation | Approve trainers, handle reports/appeals — **web app only, not ported** |

**The core promises**

1. **Every trainer is vetted.** Trainers submit certification (IKO/VDWS ID + certificate
   upload) and stay invisible to riders until an admin approves them.
2. **Availability is truthful and live.** A trainer's bookable hours combine their own
   blocks, existing bookings, whole-day time off, and a same-day lead-time rule — streamed,
   so a slot disappearing mid-booking is reflected immediately.
3. **Nobody pays in the app.** Every price is settled in person at the centre. There is
   **no payment integration of any kind**. `paymentStatus: 'paid'` is written on safari
   bookings as a legacy field and means nothing operationally.
4. **Presence is proven, not claimed.** A session only starts when the trainer physically
   scans the rider's QR ticket.

**Money.** All prices are EUR, displayed as `€120` (or `€72.50` when fractional).
Trainer hourly rates are capped platform-wide at **€60–€110**.

**Geography & time.** Ten fixed Egyptian kite spots. Egypt is UTC+2/+3, so **every date
is a local `YYYY-MM-DD` string** — never an ISO timestamp — because `toISOString()` would
shift the calendar day. This is load-bearing across the entire schema.

---

## 2. Roles, account lifecycle & the gate state machine

### 2.1 Role values

`UserRole` (`lib/data/models/app_user.dart`) — stored in `users/{uid}.role`:

| Wire value | Enum | Notes |
|---|---|---|
| `kiter` | `kiter` | Rider |
| `business` | `business` | Trainer, station, or safari operator |
| `host`, `trainer` | `business` | Legacy aliases, read-only |
| `admin`, `owner` | `admin` | Staff |
| `support` | `support` | Staff |
| anything else / missing | `unknown` | Triggers onboarding |

- `isTrainer` ⇔ role is `business` (this alone drives the entire trainer UI).
- `isStaff` ⇔ role is `admin` or `support`.

**Business sub-types** are distinguished by `businessType`, not by role:
- `isStation` ⇔ `businessType == 'Station'` (exact match)
- `isSafariOperator` ⇔ `businessType` contains `'safari'` (case-insensitive)
- Individual trainers are written with `businessType: 'Instructor'`

### 2.2 Account status

`AccountStatus` — stored in `users/{uid}.status`: `active`, `pending`, `rejected`,
`blocked`, or `none` (missing).

### 2.3 The gate state machine

`sessionProvider` (`lib/providers/providers.dart`) collapses auth + profile into one
`AppStage`. **Evaluation order matters** — this is the exact precedence:

```
1. auth stream loading                        → AppStage.loading
2. no Firebase user                           → AppStage.signedOut
3. profile stream loading                     → AppStage.loading
4. profile missing OR role == unknown         → AppStage.chooseRole
5. status == blocked                          → AppStage.blocked
6. !isStaff && isTrainer && status == pending → AppStage.awaitingApproval
7. otherwise                                  → AppStage.ready
```

Because the profile document is **streamed, not fetched once**, a trainer being approved
or a user being blocked moves the app immediately, with no restart.

`Session` exposes: `stage`, `user` (`AppUser?`), `firebaseUser`, `isTrainer`, `isStaff`,
`uid` (profile uid, falling back to the Firebase uid), and `displayName` (profile name →
Firebase displayName → `'Rider'`).

### 2.4 Lifecycle by role

**Rider:** sign up → choose role → one-page form → `status: 'active'` → straight into the app.

**Trainer:** sign up → choose role → 4-step form → `status: 'pending'` → *Pending* gate →
admin approves in the web console → `status: 'active'` → Command Center.

**Blocked user:** *Blocked* gate. `blockedUntil` is either an ISO date string or the literal
`'forever'`. A one-minute ticker recomputes the countdown, and once the ban lapses it
invalidates the profile stream once so the router releases the user automatically.

> **Edge case worth noting in redesign:** `status == 'rejected'` is not handled by the gate
> machine — a rejected trainer falls through to `ready` and gets the full Command Center.
> They are invisible in Explore (which queries `status == 'active'`), so they can manage a
> calendar nobody can book. See §14.

---

## 3. Capability catalogue

This section describes **what the system does**, not where any of it appears. It is
deliberately organised by domain rather than by screen, because the screen inventory is
the thing a redesign is free to discard. Every rule below has to survive regardless of
how the app is laid out, how many screens it has, or what those screens are called.

Where a rule constrains presentation, it is stated as a constraint on *meaning* ("a
blocked hour must not be selectable"), never as a layout instruction.

### 3.1 Identity & access

**Credentials.** Email and password only. There is no social sign-in, no phone auth, no
magic link, no "remember me" and no credential storage of any kind — Firebase owns the
session. Password reset is by Firebase email; it requires a syntactically valid address
before it will send.

**Account creation is two acts, not one.** Creating credentials and creating a *profile*
are separate, and a user can exist in the first state without the second. This is what
makes onboarding resumable and what makes the gate machine (§2.3) necessary: a signed-in
user with no profile document is a legitimate, reachable state.

**Sign-up collects credentials only.** Name is collected once, on the profile form, because
the profile document is the only place it is ever read from.

**Recoverable failures are recovered, not reported.** Signing up with an address that
already exists offers sign-in rather than an error. Password managers are supported through
the platform autofill contract.

### 3.2 Identity of a provider — profiles & the catalogue

Two profile shapes exist behind one `users` document:

- **Rider** — nationality, age, kite level, home spot, languages, quiver, bio.
- **Business** — bio, languages, training spot, optional map link, hourly rate,
  certification id, optional certificate document, gallery. A `businessType` further
  splits businesses into **instructor**, **station** and **safari operator**, which changes
  what they can offer (§3.3) but not how they are governed.

**The catalogue is the set of businesses that are `active`.** Pending, rejected and blocked
businesses are not discoverable by anyone. This is a single rule with wide reach: approval
is what makes a provider exist commercially.

**Discovery supports** free-text matching across name, location and bio; filtering by spot
and by language; and a favourites-only view. Favourites are stored on the rider's own
profile and toggle optimistically — the rule is that a favourite must never block on the
network.

**Self-view is a distinct case.** When a provider views their own public listing, the
commercial actions (book, message, report, favourite) are meaningless and must be replaced
by an edit affordance. A redesign must keep this branch; without it a trainer can book
themselves.

### 3.3 What a provider sells

- **Instructor** — hourly lessons against their own calendar.
- **Station** — lessons delivered by named staff instructors, plus rentals and beach-use
  services priced per unit. A station booking targets the *station's* calendar with the
  chosen instructor recorded as a sub-target.
- **Safari operator** — multi-day expeditions sold by the seat, with capacity.

Seat sales are the only capacity-constrained product and are therefore the only one that
must be **transactional** (§8.6): two riders taking the last seat simultaneously must
resolve to one sale and one honest refusal.

### 3.4 Availability — what "free" means

Availability is **derived, never stored as truth**. A given hour is bookable only if all of
the following hold:

1. it falls inside the bookable window (§8.3),
2. it is not in the past, and clears the same-day lead time (§8.2),
3. the provider has not blocked it,
4. the provider is not on whole-day time off,
5. no existing booking occupies it, including the buffer that follows a session (§8.1).

Each failure has a **distinct reason** — away, too soon, booked, unavailable. Collapsing
them into one "not available" state is a regression: the rider's next action differs per
reason. An hour that is not bookable must not be selectable.

Multi-hour bookings must be **contiguous** (§8.4). Selecting a non-adjacent hour prunes the
prior selection rather than creating a gap.

### 3.5 The booking lifecycle

A booking is a small state machine, and every state below is reachable in production data:

`pending → confirmed → inProgress → completed`, with `cancelled` and `rejected` as terminal
exits from the early states.

- **pending** — requested by a rider, awaiting the provider. The rider may cancel.
- **confirmed** — the provider accepted. A check-in credential now exists.
- **inProgress** — the provider verified the rider's credential in person (§3.6). Started
  sessions cannot be cancelled by either party.
- **completed** — the provider ended the session. This is what makes the booking reviewable
  (§3.8) and what moves money into the earnings figure (§3.7).
- **rejected** — declined by the provider, optionally with a reason delivered to the rider.
- **cancelled** — withdrawn by the rider.

**Walk-ins** are provider-created bookings that skip `pending` — the rider is standing there.

A booking carries the rider's kite level to the provider, because it changes how the session
is prepared. It also carries an optional free-text message and a gear flag.

**Both parties can hide a booking from their own history independently.** Hiding is per-party
and never deletes.

### 3.6 Check-in — proving who turned up

Check-in exists to stop a session being marked started by mistake or by claim. The rider
holds a credential encoding the booking and the provider; the provider verifies it in
person, which is the transition into `inProgress`.

Two constraints are load-bearing and easy to lose in a redesign:

- The credential must render on a **light surface regardless of theme**, because it is read
  by a camera, not by a person.
- The rider's view must be **live**: the moment the provider verifies, the rider's screen
  must reflect it without a manual refresh.

The credential is only meaningful for a `confirmed` or `inProgress` booking.

### 3.7 Money

**FLOW moves no money.** The rider pays the provider directly, in person. What the system
does is *record* the obligation, so that neither party has to remember it.

Every booking records what was owed, in what currency, by what method, and whether it has
been collected. The states are `unknown`, `unpaid`, `processing`, `paid`, `refunded`,
`failed`. Three rules matter:

- **`unknown` is not `unpaid`.** Bookings written before payments were tracked have no
  payment information, and relabelling them as owing would tell every provider they are out
  of pocket for work already paid for. `unknown` must render as nothing at all.
- **Only the provider can say they were paid.** A rider who could mark their own lesson paid
  could walk off the beach owing for it with the app agreeing they did not.
- **Cash is one method among several, not an assumption.** Card, wallet and transfer are
  modelled but not offered; the vocabulary exists so a processor can be added without a
  data migration.

Earnings are the sum of completed sessions. Outstanding money is the sum of sessions that
are `unpaid` or `failed` — this is what drives a "still to collect" figure and a settle
action.

### 3.8 Reputation

A rider may review a provider **only** against a completed booking they have not already
reviewed. Eligibility is checked before the composer is offered, not merely on submit — an
ineligible rider must never be invited to write something that will be refused.

A review is a 1–5 rating plus optional text. Authors may delete their own. Reviews are
immutable once written; there is no edit. Ratings aggregate to an average and a count.

### 3.9 Conversations

Direct threads between a rider and a provider, created on first message. Messages are
**immutable once sent** — no edit, no delete. Unread state is tracked per participant.

Threads are also the delivery mechanism for two administrative conversations: **support
tickets** and **appeals**. All three are the same idea — an append-only thread between two
parties — and a redesign that unifies them should preserve their differing lifecycles:

- **Chat** — never closes.
- **Support ticket** — support can resolve it, which locks the composer; the user can reopen.
- **Appeal** — available only to blocked users, and must survive a flaky connection: a typed
  appeal is never discarded because an upload failed.

### 3.10 Notifications & reminders

The system notifies the *other* party on every state change that affects them: a request
arrives, a request is approved or declined, a session is cancelled, a message is sent, a
session is about to start.

Notifications exist in two layers that must stay consistent:

- **In-app** — a durable, readable list with unread state; tapping one navigates to the
  thing it is about.
- **Push** — delivered by a server-side function watching new notification documents. Push
  is best-effort: a device token can be stale, and a failed push must never fail the action
  that generated it.

Session reminders are generated on a schedule server-side, not by the client — a client
cannot be relied upon to be running.

**Push tokens are per-device, not per-account.** A token must be dropped on sign-out, or the
previous user's notifications arrive on the next user's handset.

### 3.11 Conditions

An eight-day wind forecast per spot, from a public weather API. It is advisory only and is
banded into rider-meaningful terms — too light, light, good, strong, too strong — rather
than raw numbers, because a forecast that far out does not support the precision.

**It never blocks a booking.** The provider decides on the day; a forecast is not an
authority. Failure is silent: no forecast simply means no forecast, never an error state.

### 3.12 Trust & safety

- **Reporting** — any user may report a provider with a reason and optional evidence.
  Reports are write-only for the reporter: you cannot read others' reports, or discover that
  you have been reported.
- **Blocking** — staff may block an account, with an expiry or permanently. A blocked user
  retains exactly one capability: appealing.
- **Approval** — business accounts are reviewed before becoming discoverable. This is the
  gate the whole catalogue depends on.
- **Privileged fields are staff-only.** Role, status and block state can never be written by
  the account they describe. This is enforced server-side, and it is why the first staff
  account must be promoted out-of-band.

### 3.13 Account & data

Profile editing covers presentational identity only. **Rate and training spot are
deliberately not self-editable** — they are commercial terms, changed through support.

Account deletion removes the profile and the credentials, and asks (optionally) why. It is
irreversible and must be presented as such.

Emptying an optional field must actually clear it. "Not editing this field" and "clearing
this field" are different intents and cannot share a representation.

### 3.14 Support (added 2026-08-12)

- **Tickets** — any signed-in user opens a ticket (subject + body) and replies on it; the
  thread is a sub-collection, readable and writable by its owner and staff, nobody else.
  Messages are immutable once sent — for everyone, staff included.
- **Staff answer as FLOW support** (`isAdmin: true` on the message), can close a ticket,
  and the owner reopens it simply by replying. Closing is staff-only; deleting the thread
  is not offered in the app at all.
- **Leave reasons** — the optional "why are you leaving?" on account deletion is written to
  a write-only collection carrying the author's name and email (the profile is deleted
  moments later, so the document must carry who it was). Staff read it in the console's
  FEEDBACK tab; nobody edits or deletes it, staff included.

### 3.15 Staff oversight (added 2026-08-12)

The console is the whole of the staff app, and staff see everything:

- **Every account** — the USERS directory lists all users whatever their role or status,
  searchable by name/email, filterable (riders / business / pending / suspended). From an
  account's sheet staff can suspend (7 days, same mechanics as a report's uphold), lift a
  suspension, and open a business account's public profile. Staff accounts themselves are
  managed out-of-band — the console does not offer staff-on-staff suspension.
- **Every session** — the SESSIONS view lists all bookings platform-wide, searchable by
  either party, filterable by status, each opening a detail sheet (parties, hours, price,
  payment state, check-in state, request message).
- **Authorisation shape** — the users list rides the open profile-read rule; the bookings
  list is provable only through the document-independent `isStaff()` arm of
  `isParty() || isStaff()`, so the same unfiltered query from anyone else is refused
  wholesale (pinned in `test_rules/booking_reads.test.mjs`).

---

## 4. Navigation map & user flows

### 4.1 Route table (`lib/router.dart`)

| Path | Screen | Navigator |
|---|---|---|
| `/` | Splash | root |
| `/auth` | Auth | root |
| `/onboarding/role` | Role select | root |
| `/onboarding/rider` | Rider form | root |
| `/onboarding/trainer` | Trainer form | root |
| `/pending` | Awaiting approval | root |
| `/blocked` | Suspended + appeal | root |
| `/home` | **Explore** (rider) or **Command Center** (trainer) | shell branch 0 |
| `/sessions` | My sessions — accepts `?highlight=<bookingId>` | shell branch 1 |
| `/inbox` | Messages | shell branch 2 |
| `/profile` | Profile | shell branch 3 |
| `/trainer/:id` | Trainer profile | root (push) |
| `/station/:id` | Station / safari profile | root (push) |
| `/chat/:id?name=<partnerName>` | Chat thread | root (push) |
| `/book/:id` | Booking flow (`extra: BookingTarget`) | root (push) |
| `/notifications` | Notifications | root (push) |
| `/support` | Support tickets | root (push) |
| `/profile/edit` | Edit personal details | root (push) |

Unknown routes render a themed "That page drifted offshore." screen with a route home.

### 4.2 Redirect logic

A single `redirect` driven by `sessionProvider`, re-evaluated whenever the session changes:

```
loading          → /                (unless already there)
signedOut        → /auth            (unless already there)
chooseRole       → /onboarding/role (unless already under /onboarding)
awaitingApproval → /pending
blocked          → /blocked
ready            → if on /, /auth, /pending, /blocked or /onboarding/* → /home
```

### 4.3 Tab shell

`StatefulShellRoute.indexedStack` with four branches. **Trainers do not get the Sessions
tab** — their bookings live in the Command Center — so their bar shows Dashboard / Inbox /
Profile. Tapping the already-active tab pops that branch to its root. Branch state is
fully retained across switches.

Branch 0 resolves its screen through a `Consumer`, so a role change swaps Explore ⇄ Command
Center without a restart.

### 4.4 Primary flows

**Rider: first launch → booked session**
```
Splash → Auth (sign up) → Role select → Rider form → Explore
  → tap trainer → Trainer profile → Book now
  → pick day → pick contiguous hours → message + gear → Review & confirm
  → Confirm → "Request sent!" → back to profile
  → (trainer approves) → notification → My sessions ▸ UPCOMING (highlighted)
  → Check in → QR ticket → (trainer scans) → ticket flips to "Session started"
  → session runs → (trainer finishes) → My sessions ▸ HISTORY → Rate
```

**Trainer: application → running the day**
```
Splash → Auth (sign up) → Role select → Trainer form (4 steps) → Pending gate
  → (admin approves in web console) → Command Center (first-run tour)
  → TODAY ▸ Action required → Approve / Decline (+reason)
  → SCHEDULE ▸ block hours / add walk-in / set time off
  → CHECK IN → scan rider QR → session in progress → FINISH SESSION
  → earnings updated → ledger via Total earned
```

**Blocked user**
```
any screen → (admin blocks) → profile stream emits → Blocked gate
  → Appeal this decision → reason + evidence → appeal thread with admins
  → (ban lapses or is lifted) → profile stream emits → back into the app
```

### 4.5 Modal & sheet inventory

| Surface | Where | Purpose |
|---|---|---|
| Filter sheet | Explore | Spot + languages |
| Report sheet | Trainer profile | Reason, details, attachments |
| Review sheet | Sessions, Trainer profile | Stars + comment |
| Booking review sheet | Booking | Final confirmation |
| Success dialog | Booking | Non-dismissible; single exit |
| QR ticket dialog | Sessions | Live check-in ticket |
| Decline sheet | Command Center | Optional reason |
| Booking details sheet | Command Center | Read-only + message rider |
| Earnings sheet | Command Center | Ledger |
| Walk-in sheet | Schedule | Manual booking |
| Time-off sheet | Schedule | Date range |
| Tour dialog | Command Center | 4-step first run |
| Privacy sheet | Profile | Data explainer |
| Delete-account sheet | Profile | Leave reason |
| New ticket sheet | Support | Subject + body |
| Appeal sheet | Blocked | Reason + evidence |
| Image source sheet | anywhere with a picker | Camera vs gallery |
| Confirm dialogs | throughout | Destructive/irreversible actions |
| Busy overlay | uploads | Blocking, non-dismissible |

---

## 5. Data models — field by field

All parsing is **deliberately tolerant** (`lib/core/utils/doc_x.dart`): the same logical
field arrives in several shapes because a loosely-typed web client wrote this database over
years. A single malformed document must never crash a screen.

**Tolerant readers:** `str`, `strAny([keys])`, `boolean` (accepts `"true"`), `integer`,
`decimal`, `money` (strips `€`, `EUR`, spaces), `moneyAny`, `strList` (accepts a bare
string, drops nulls/empties), `nested`, `nestedList`, `date`/`dateAny` (accepts
`Timestamp`, `DateTime`, epoch seconds *or* millis, ISO string, `{_seconds}` maps).
`compact()` strips nulls before `update()` so a null never overwrites a field the web
client still needs.

### 5.1 `AppUser` — `users/{uid}`

| Field | Type | Source keys | Notes |
|---|---|---|---|
| `uid` | String | doc id | |
| `name` | String | `name` → `businessName` | |
| `email` | String | `email` | |
| `role` | UserRole | `role` | §2.1 |
| `status` | AccountStatus | `status` | §2.2 |
| `level` | String? | `level` | Rider skill |
| `homeSpot` | String? | `homeSpot` | |
| `location` | String? | `location` → `trainingSpot` → `hostProfile.location` | |
| `bio` | String? | `bio` → `hostProfile.bio` | |
| `nationality`, `age`, `phoneNumber` | | | |
| `languages`, `quiver`, `gallery`, `favorites` | List\<String\> | | |
| `photoUrl` | String? | `photoURL` → `profileImage` → `hostProfile.profilePicture` | |
| `businessType` | String? | | `Instructor` / `Station` / `…Safari…` |
| `ikoId`, `certificateUrl`, `mapsLink` | String? | | Trainer verification |
| `hourlyRate` | double? | `priceList` → `hourlyRate` → `hostProfile.rate` | |
| `blockedUntilRaw` | String? | `blockedUntil` | ISO string or `'forever'` |
| `fcmToken` | String? | | Push target |
| `travelBufferMinutes` | int? | `travelBuffer` | |

**Derived:** `isSafariOperator`, `isStation`, `isPermanentlyBlocked`, `blockedUntil`,
`bufferMinutes` (default **60**), `displayRate` (default **€50**), `initial`.

### 5.2 `Booking` — `bookings/{id}`

| Field | Source keys | Notes |
|---|---|---|
| `date` | `date` | Local `YYYY-MM-DD` |
| `status` | `status` | see below |
| `instructorId` | `instructorId` → `stationId` | Calendar owner |
| `instructorName` | | |
| `kiterId` | `kiterId` → `guestId` | `'manual_entry'` for walk-ins |
| `studentName` | `studentName` → `guestName` → `userName` | |
| `studentLevel` | | |
| `listingTitle` | `listingTitle` → `serviceName` → `tripTitle` | |
| `subTarget` | | Instructor/service inside a station |
| `startTime` | `startTime` → `time` | `HH:mm` |
| `endTime`, `bufferedEndTime` | | |
| `selectedTimes` | | Hour slots held |
| `durationHours` | `durationHours` → `duration` | |
| `totalPrice` | `totalPrice` → `price` | money-parsed |
| `type` | `type` → `bookingType` | `lesson`/`manual`/`safari`/`rental`/`beach_use`/`station_lesson` |
| `gearNeeded`, `message`, `createdAt` | | |
| `hiddenByGuest`, `hiddenByInstructor` | | Per-side history hiding |
| `reminderSent`, `checkedIn`, `tripId` | | |

**`BookingStatus`** — wire ⇄ enum ⇄ label:

| Wire | Enum | Label | `isLive` | `isDead` |
|---|---|---|---|---|
| `pending` | pending | Pending | ✔ | |
| `confirmed` | confirmed | Confirmed | ✔ | |
| `in_progress`, `active` | inProgress | Active | ✔ | |
| `completed` | completed | Completed | | |
| `cancelled` | cancelled | Cancelled | | ✔ |
| `rejected` | rejected | Declined | | ✔ |
| *(unknown)* | unknown | Unknown | | |

`unknown` serialises back to `pending`.

**Derived:** `isManual`, `isSafari`, `title`, `occupiedSlots`, `hours`, `timeRange`,
`startsAt`, `endsAt`, `isPast`, `bucket()`, `subLabel` (see §8).

### 5.3 Scheduling

**`Availability`** — `availability/{id}`: `instructorId`, `date`, `startTime`, `endTime`,
`label`. `status` is `'host-blocked'` (the trainer's own calendar block) or `'occupied'`
(a live booking's shadow — see §8.5); both mean unavailable, and **any other status is
ignored**. An occupied doc is keyed by its booking's id, written in the same atomic commit
as the booking, and deleted in the same transaction that moves the booking to a terminal
status. It exists because bookings are readable only by their own parties: it carries the
hours and nothing else, so a stranger's grid can see the hour is gone without seeing whose
it is. In `DayAvailability` occupied docs land in `booked`, host blocks in `blocked` — the
schedule tab offers release only on `blocked`.

**`Vacation`** — `vacations/{id}`: `instructorId`, `startDate`, `endDate`, `label`.
`covers(date)` is an inclusive lexicographic string comparison — valid because dates are
zero-padded `YYYY-MM-DD`.

**`DayAvailability`** (computed, never stored): `date`, `blocked`, `booked`, `onVacation`,
`past`.
- `isFree(slot)` ⇔ not on vacation **and** not blocked **and** not booked **and** not past.
- `blockedReason(slot)` precedence: `Away` → `Too soon` → `Booked` → `Unavailable`.

### 5.4 Social

**`Review`** — `reviews/{id}`: `trainerId` (renamed from `listingId`, which
held the same value under a misleading name), `userId`, `userName`, `rating` (clamped 1–5), `comment`,
`bookingId`, `createdAt`.

**`RatingSummary`** — computed. `none` is **average 5.0, count 0** (so unrated trainers
display "5.0"). `display` is one decimal place.

**`ChatThread`** — `chats/{chatId}`: `participants` (2 uids), `participantNames` (map),
`lastMessage`, `lastMessageAt` (`lastMessageTimestamp` → `updatedAt`), `unreadCounts`
(map uid→int, parsed tolerantly; strings accepted, negatives clamped to 0).
`chatId` = the two uids **sorted and joined with `_`** — deterministic from either side.

**`ChatMessage`** — `chats/{chatId}/messages/{id}`: `senderId`, `text`, `createdAt`, `read`.

**`AppNotification`** — `notifications/{id}`: `title`, `message` (`message` → `body`),
`kind` (from `type`), `read`, `createdAt`, `bookingId`.

**`NotificationKind`** parsing:

| Wire `type` | Kind |
|---|---|
| `booking_request`, `booking_new` | bookingRequest |
| `booking_confirmed` | bookingConfirmed |
| `booking_rejected` | bookingRejected |
| `booking_cancelled` | bookingCancelled |
| `reminder` | reminder |
| `review` | review |
| `message` | message |
| `global_broadcast` | broadcast |
| *anything else* | system |

### 5.5 Catalogue

**`StationService`** — `users/{stationId}/station_services/{id}`: `name`, `price`,
`description`, `unit`, `kind` (`beach_use`/`beach` → beachUse, else rental).

**`StationInstructor`** — `users/{stationId}/station_instructors/{id}`: `name`, `level`,
`rate` (display default €50), `photoUrl`.

**`SafariTrip`** — `safari_trips/{id}`: `hostId`, `title`, `startDate`, `price`,
`capacity`, `bookedSeats`, `description`, `duration`. Derived: `seatsLeft`, `isSoldOut`,
`fillRatio`.

**`BookingTarget`** (transient, never persisted) — the funnel every bookable thing passes
through: `providerId` (the uid owning the calendar), `title`, `rate`, `subtitle`,
`imageUrl`, `unit` (default `'hour'`), `bookingType` (default `'lesson'`), `subTarget`.

### 5.6 Support

**`SupportTicket`** — `tickets/{id}`: `userId`, `userName`, `subject`, `isOpen`
(`status == 'open'`, defaulting to open), `lastMessageAt`.

**`TicketMessage`** — `tickets/{id}/messages/{id}`: `text`, `senderId`, `fromStaff`
(`isAdmin`), `createdAt`.

**`Appeal`** — `appeals/{id}`: `userId`, `userName`, `reason`, `status`
(`pending`/`reviewed`/`resolved`), `attachments`, `createdAt`, and **`messages` as an array
on the document** (not a sub-collection).

**`AppealMessage`** — `id`, `senderId`, `senderName`, `text`, `attachments`, `timestamp`
(written as an ISO string).

---

## 6. Firestore schema — every read and write

### 6.1 Collections (`lib/data/firestore_paths.dart`)

`users` · `bookings` · `listings`\* · `availability` · `vacations` · `reviews` · `chats`
(+ `messages`) · `notifications` · `tickets` (+ `messages`) · `appeals` · `reports` ·
`broadcasts`\* · `leave_reasons` · `safari_trips` · `users/{id}/station_instructors` ·
`users/{id}/station_services`

\* declared but not read/written by this client.

**Storage folders:** `profiles`, `galleries`, `listings`, `certificates`, `reports`, `appeals`.

> These names must match the web client exactly — both clients share one database, so a
> renamed collection means silently invisible data.

### 6.2 Queries

| Query | Filters | Ordering |
|---|---|---|
| Active trainers | `role == 'business'` ∧ `status == 'active'` | none |
| Rider bookings | `kiterId == uid` | client-side, `date` desc |
| Trainer bookings | `instructorId == uid` | client-side, `date` desc |
| Day blocks | `instructorId` ∧ `date` | — |
| Day bookings | `instructorId` ∧ `date` | — |
| Vacations | `instructorId` | client-side by `startDate` |
| Reviews for trainer | `trainerId == trainerId` | client-side, newest first |
| All ratings | *(entire collection)* | grouped client-side |
| Inbox | `participants array-contains uid` | client-side, `lastMessageAt` desc |
| Messages | — | `orderBy('createdAt')` |
| Notifications | `targetUserId == uid` | client-side, newest first |
| Tickets | `userId == uid` | client-side, `lastMessageAt` desc |
| Ticket messages | — | `orderBy('createdAt')` |
| My appeal | `userId == uid`, limit 1 | — |
| Safari trips | `hostId == hostId` | — |
| Station sub-collections | — | — |

**Sorting is deliberately client-side** wherever it accompanies an equality filter: doing it
server-side would require a composite index per query. **Preserve this** — moving sorts to
the server without creating indexes breaks those screens with a `failed-precondition` error.

### 6.3 Document writes

**Booking created by a rider** (`createBooking`) — one canonical name per
field. v2.6 dual-wrote `guestId`/`kiterId`, `time`/`startTime`,
`price`/`totalPrice` and `bookingType`/`type` for a web client that shared the
database; this app is the sole writer, so the legacy aliases are gone:

```jsonc
{
  "id": "<docId>", "instructorId": "...", "instructorName": "...",
  "kiterId": "<riderUid>",
  "studentName": "...", "studentLevel": "<the rider's level>",
  "listingTitle": "Trainer — SubTarget",   // or just the title
  "subTarget": "...",                       // only when present
  "date": "2026-08-14",
  "startTime": "09:00",
  "endTime": "11:00", "bufferedEndTime": "12:00",
  "selectedTimes": ["09:00","10:00"], "durationHours": 2,
  "totalPrice": 240,
  "type": "lesson",
  "gearNeeded": false, "message": "...",
  "status": "pending",
  // ...PaymentInfo.initialFields(amount:) — paymentStatus 'unpaid',
  // amountDue, currency. Payment is recorded from the first write, never
  // bolted on at the end.
  "createdAt": "<serverTimestamp>"
}
```

**Walk-in** — same shape with `kiterId: 'manual_entry'`, `studentLevel: 'Walk-in'`,
`listingTitle: 'Private lesson (walk-in)'`, `type: 'manual'`, `status: 'confirmed'`.

**Safari booking** (inside a transaction) — adds `tripId`, `tripTitle`,
`listingTitle: 'Expedition: …'`, `status: 'confirmed'`, `type: 'safari'`,
`paymentStatus: 'paid'` (legacy, meaningless), and increments the trip's `bookedSeats`,
setting `status` to `full` or `open`.

**Status change** — `{status, updatedAt}`.
**Rider cancel** — `{status: 'cancelled', cancelledAt, cancelledBy: 'user'}` (+ releases a
safari seat via `bookedSeats: -1`, `status: 'open'`).
**Check-in** — `{status: 'in_progress', checkedIn: true, startedAt}`.
**Hide** — `{hiddenByInstructor | hiddenByGuest: true}`.

**Notification** — `targetUserId` only. v2.6 also wrote `userId` as an alias for a web client that queried it; the `onNewNotification` Cloud Function reads `data.userId || data.targetUserId`, so dropping it still resolves the recipient:
```jsonc
{ "targetUserId": "<uid>", "title": "...", "message": "...",
  "type": "booking_request", "read": false, "createdAt": "<serverTimestamp>",
  "bookingId": "..." }
```

**Chat message** → `chats/{id}/messages`: `{senderId, receiverId, text, createdAt, read:false}`
Then the thread: `{lastMessage, lastMessageTimestamp, updatedAt, unreadCount: {<receiverId>: increment(1)}}`
**Mark read** → `{unreadCount: {<uid>: 0}}` (merge, so only that participant's entry changes).

**Availability block** — `{instructorId, date, startTime, endTime, status: 'host-blocked', label, createdAt}`
**Occupied doc** — `availability/{bookingId}`: `{instructorId, date, startTime, endTime, status: 'occupied', label: 'Booked', createdAt}` — written in `createBooking`/`createWalkIn`'s batch, deleted by the terminal-status transaction (§5.3, §8.5)
**Vacation** — `{instructorId, startDate, endDate, label, createdAt}`
**Review** — `{trainerId, userId, userName, rating, comment, bookingId, createdAt}`
**Report** — `{reporterId, reporterName, reportedUserId, reportedUserName, reason, details, attachments, status: 'pending', createdAt}`
**Leave reason** — `{userId, userName, userEmail, reason, createdAt}`
**Ticket** — `{userId, userName, subject, status: 'open', createdAt, lastMessageAt}` + a first message
**Appeal** — `{userId, userName, reason, attachments, status: 'pending', createdAt, messages: []}`;
replies use `arrayUnion` (a read-modify-write would drop concurrent admin replies).

---

## 7. State management — the Riverpod graph

All providers live in `lib/providers/providers.dart` unless noted. **Widgets never touch
Firestore** — they watch a provider; providers call repositories.

### 7.1 Infrastructure & repositories

`firebaseAuthProvider`, `firestoreProvider`, `firebaseStorageProvider` →
`authRepositoryProvider`, `userRepositoryProvider`, `notificationRepositoryProvider`,
`bookingRepositoryProvider` (depends on notifications), `scheduleRepositoryProvider`,
`reviewRepositoryProvider`, `chatRepositoryProvider` (depends on notifications),
`supportRepositoryProvider`, `storageRepositoryProvider`.

### 7.2 Session

```
authStateProvider (Stream<User?>)
  └→ currentUidProvider (String?)
       └→ currentUserProvider (Stream<AppUser?>)
            └→ sessionProvider (Session)  ← drives every redirect and role branch
```

### 7.3 Derived state

| Provider | Type | Derivation |
|---|---|---|
| `activeTrainersProvider` | Stream | Explore source |
| `ratingsProvider` | Stream | uid → RatingSummary, whole `reviews` collection |
| `trainerReviewsProvider(id)` | Stream.family | |
| `trainerProfileProvider(uid)` | Stream.family | Also used for stations |
| `stationInstructorsProvider(id)` / `stationServicesProvider(id)` / `safariTripsProvider(id)` | Stream.family | |
| `exploreFilterProvider` | Notifier | query, spot, languages, favouritesOnly |
| `filteredTrainersProvider` | Provider | active trainers ∩ filter ∩ favourites |
| `riderBookingsProvider` / `trainerBookingsProvider` | Stream | |
| `riderBucketsProvider` / `trainerBucketsProvider` | Provider | bucketed, hidden-filtered |
| `pendingRequestsProvider` | Provider | pending ∧ `date >= today` |
| `todayManifestProvider` | Provider | `date == today` ∧ `isLive`, by start time |
| `trainerCompletedProvider` | Provider | completed, newest first |
| `trainerRevenueProvider` | Provider | Σ completed `totalPrice` |
| `trainerMonthRevenueProvider` | Provider | Σ completed in current `YYYY-MM` |
| `dayAvailabilityProvider((instructorId, date))` | Stream.family | 3-stream combine |
| `myBlocksProvider` / `myVacationsProvider` | Stream | |
| `notificationsProvider` | Stream | |
| `unreadNotificationCountProvider` | Provider | count where `!read` |
| `inboxProvider` | Stream | |
| `unreadChatCountProvider` | Provider | Σ `unreadFor(me)` — badges the Inbox tab |
| `myTicketsProvider` / `ticketMessagesProvider(id)` / `myAppealProvider` | Stream | |

### 7.4 Local settings (`lib/providers/settings_provider.dart`)

- `sharedPreferencesProvider` — **overridden in `main()`** after prefs load, so theme reads
  are synchronous and the first frame has the correct brightness.
- `themeModeProvider` — persisted under `themeMode` (`light`/`dark`/absent → system).
- `onboardingFlagsProvider` — `trainerTourDone_{uid}` booleans.

### 7.5 Stream combination

`dayAvailabilityProvider` merges three Firestore streams (blocks, bookings, vacations) and
**emits only once all three have produced a value**, then on every change. Subscriptions
are cancelled and the "has value" flags reset on cancel, so a re-listen doesn't accumulate
dead subscriptions.

---

## 8. Business logic rules

### 8.1 Time slots (`lib/core/utils/date_x.dart`)

- Bookable start hours: **08:00 … 17:00 inclusive** (`firstHour = 8`, `lastHour = 18`,
  generated as `h < lastHour`) — **10 slots**. The last lesson ends at 18:00.
- `Slot` is an extension type over an `HH:mm` string with `hour`, `minute`,
  `minutesOfDay`, `plusMinutes`, `plusHours`, `overflowsDay`.
- `Slot.tryParse` accepts `H:mm` or `HH:mm` with trailing content; rejects hour > 23 or
  minute > 59.

### 8.2 Same-day lead time

`BookingMath.pastSlots(date)` returns `{}` unless `date` is today. For today, the cutoff is
`now.hour + 1` and **every slot with `hour <= cutoff` is unavailable**. At 09:30 the cutoff
is 10, so 08:00–10:00 are all closed and 11:00 is the first bookable hour.

### 8.3 Booking window & travel buffer

`BookingMath.window(start, durationHours, bufferMinutes = 60)` yields:
- `end` = start + duration
- `bufferedEnd` = start + duration + buffer
- `isValid = false` with the error "Booking extends past midnight" if `start + duration + buffer` crosses midnight.

> **Important:** `bufferedEndTime` is *written* to the booking document, but availability
> only ever subtracts `occupiedSlots`. **The travel buffer is stored, not enforced** — a
> back-to-back booking in the hour after a lesson is still offered. Preserve or fix
> deliberately; do not change by accident.

### 8.4 Contiguous hour selection

In the booking grid (`_tapSlot`):
1. Tapping an already-selected slot **clears the entire selection**.
2. With nothing selected, the tapped slot becomes the anchor.
3. Otherwise, extend from the **earliest currently-selected slot** to the tapped one,
   inclusive — but only if **every** hour in that range is free. If any is not, the
   selection resets to just the tapped slot.

Selection is cleared whenever the day changes. If a selected hour becomes unavailable while
the screen is open (someone else booked it), it is dropped from the selection on the next
frame — but only once real availability data has arrived.

### 8.5 Availability composition

```
isFree(slot) = !onVacation
             ∧ slot ∉ blocked      (availability docs, status host-blocked)
             ∧ slot ∉ booked       (bookings whose status.isLive, ∪ occupied docs)
             ∧ slot ∉ past         (same-day lead time)
```
Cancelled, declined and completed bookings **release** their hours — the terminal-status
transaction deletes the occupied doc alongside. For a viewer who cannot read the bookings
stream (anyone but the trainer or staff), `booked` is fed by the occupied docs alone;
`dayAvailabilityProvider` treats that stream's permission-denied as "no bookings visible"
rather than an error.
`expandBlock(start, end)` covers `[startHour, endHour)`; a block with no distinct end covers
only its start hour.

### 8.6 Collision handling

- **Hourly bookings are checked, not locked.** `createBooking` and `createWalkIn` re-query
  the day immediately before writing and throw `SlotTakenFailure` on a clash. The check
  reads both calendars: the day's bookings where the caller may (their own two-party reads;
  a rider's query is refused by design and degrades to the second source), and the
  `availability` docs — occupied docs *and* host blocks, so a block added between the grid
  snapshot and the confirm no longer slips through. An occupied doc whose booking was
  readable defers to the booking's own status. Firestore transactions cannot read a
  *query*, only known documents, so a true lock is impossible without a per-slot document.
  Two riders confirming the same hour in the same instant both land as pending requests,
  and the trainer declines one.
- **Safari seats *are* transactional**, because the seat count lives on one known document.
  The transaction re-reads capacity and throws `SlotTakenFailure(['seat'])` if full.

### 8.7 Booking bucketing

```
bucket(now):
  status == inProgress                    → active
  status.isDead || status == completed    → history
  now > endsAt                            → history   (unanswered request that expired)
  otherwise                               → upcoming
```
`endsAt` = `endTime`, else `startTime + hours`, else **23:59:59 of that day** (so a booking
with no usable time is never prematurely "expired").
Upcoming and active are sorted **soonest first**; history keeps the source order (newest first).
Rider buckets exclude `hiddenByGuest`; trainer buckets exclude `hiddenByInstructor`.

**`subLabel`** (the words under the status pill):

| Status | Sub-label |
|---|---|
| pending | "Expired — never confirmed" if past, else "Waiting for trainer" |
| confirmed | "Past session" if past, else "Approved" |
| inProgress | "In progress" |
| completed / cancelled / rejected | "Completed" / "Cancelled" / "Declined" |

### 8.8 Explore filtering

Applied in order, all must pass:
1. **Favourites** — if `favouritesOnly`, uid must be in the current user's `favorites`.
2. **Query** — lowercase substring of `"{name} {location} {bio}"`.
3. **Spot** — trainer's `location` (lowercased) must *contain* the selected spot.
4. **Languages** — the trainer must speak **at least one** selected language (OR, not AND).

`activeCount` (the filter badge) counts spot + each language + favourites — **not** the
search text, which has its own field.

### 8.9 Review eligibility

`findReviewableBooking(trainerId, riderId)`: fetch that rider's **completed** bookings with
that trainer, fetch every review the rider has written, and return the first completed
booking id not present in the reviewed set. The composer is only rendered when this returns
non-null. `submit()` independently re-checks for an existing review on that `bookingId` and
silently no-ops if found — so double submission is impossible even by race.

### 8.10 Ratings

`RatingSummary.from(reviews)` averages `rating`. With **no reviews the summary is 5.0/0**,
so an unrated trainer displays "5.0" next to "(0 reviews)". Ratings for the whole
marketplace come from one snapshot of the entire `reviews` collection grouped by
`trainerId`.

### 8.11 Unread messages

`send()` increments `unreadCount.{receiverId}`; opening a thread sets `unreadCount.{me} = 0`.
`unreadFor(uid)` reads that map (0 when absent); `unreadChatCountProvider` sums it across
threads to badge the Inbox tab.

---

## 9. Form validation rules

### 9.1 Auth

| Field | Rule | Message |
|---|---|---|
| Name (sign-up) | non-empty after trim | "Tell us your name" |
| Email | non-empty | "Enter your email" |
| Email | contains `@` **and** `.` | "That email doesn't look right" |
| Password | non-empty | "Enter your password" |
| Password (sign-up) | ≥ 6 characters | "Use at least 6 characters" |
| Reset | same email shape check before sending | "Enter your email first, then tap reset." |

Errors render in a banner at the top of the form; the reset error also focuses the email field.

### 9.2 Rider onboarding

| Field | Rule |
|---|---|
| Full name | required, non-empty |
| Nationality | required, non-empty |
| Age | required integer, **8–99** ("8–99" on failure) |
| Languages | at least one, shown inline under the chips |
| Level | defaults to `Independent` |
| Photo, home spot, quiver, bio | optional |

On failure the first unmet field is **scrolled into view** (name → nationality/age row → languages).

### 9.3 Trainer onboarding (per-step gates)

| Step | Requirement |
|---|---|
| 1 | photo present **and** name > 2 chars **and** bio non-empty **and** ≥1 language |
| 2 | spot selected |
| 3 | rate parses as an integer within **60–110** |
| 4 | IKO/VDWS ID > 3 chars |

The Next button is **always tappable**; tapping on an incomplete step marks it "attempted",
reveals the inline hints (which stay quiet until then) and scrolls to the first problem.
Rate input is digits-only, max 3 characters. Certificate is optional.

### 9.4 Edit profile

Name required. Languages ≥ 1 (inline, scrolls into view). Age digits-only, max 2 chars.
Email and, for trainers, training spot are **read-only** with explanatory helper text.
**Save is disabled until the form differs from its loaded snapshot**, and leaving dirty
prompts to discard.

### 9.5 Booking

At least one hour must be selected before "Review & confirm" enables. Server-side,
`createBooking` throws `ArgumentError` on an empty slot list and `SlotTakenFailure` on a clash.

### 9.6 Walk-in

Student name non-empty **and** a start time chosen. Only genuinely free hours are offered.
Price is digits-only, defaulting to the trainer's rate; falls back to `rate × hours` if unparseable.

### 9.7 Support & appeals

Ticket: subject required ("Add a short subject"), body required ("Tell us what happened so
we can help"). Appeal: reason required ("Please explain your appeal"). Report: reason
required (submit disabled until chosen); details and attachments optional.

---

## 10. Edge cases, loading, errors & micro-interactions

### 10.1 The three async states

`AsyncView<T>` (`lib/core/widgets/feedback.dart`) is the single place loading/error/data is
rendered. **`onRetry` is a required parameter** — it is impossible to ship an error dead end
by forgetting it. Optional `skeleton` and `onRefresh` (pull-to-refresh). Previous data stays
visible while a stream re-subscribes, so lists don't flash empty on navigation.

### 10.2 Loading must not lie

Two places previously rendered a *confident wrong answer* while still connecting; both now
distinguish "loading" from "empty":

- **Command Center** showed `0 / 0 / €0` and "No sessions today" on every cold start.
- **Booking grid** defaulted every hour to *free* before availability arrived, so the first
  thing a rider saw was a fully-available day that then filled in — and hours could be
  selected that were about to vanish.

Skeletons are shaped like the content that's coming (grid, list, timeline, chat, slot grid),
so nothing jumps on arrival. `SkeletonPulse` holds a static opacity when the OS reports
reduce-motion, and all skeletons are excluded from semantics.

### 10.3 Error message mapping

**Firestore//generic** (`ErrorView._friendly`):

| Contains | Message |
|---|---|
| `permission-denied` | "You don't have access to this yet." |
| `unavailable` / `network` | "No connection. Check your internet and try again." |
| `failed-precondition` + `index` | "This view needs a database index that hasn't been created yet." |
| anything else | "Something went wrong. Please try again." |

**Auth** (`AuthRepository._message`):

| Code | Message |
|---|---|
| `user-not-found`, `wrong-password`, `invalid-credential` | "Incorrect email or password." |
| `invalid-email` | "That email address doesn't look right." |
| `email-already-in-use` | "An account with this email already exists." |
| `weak-password` | "Password should be at least 6 characters." |
| `user-disabled` | "This account has been disabled." |
| `too-many-requests` | "Too many attempts. Please wait a moment and try again." |
| `network-request-failed` | "No connection. Check your internet and try again." |
| `requires-recent-login` (delete) | "For your security, sign out and sign back in before deleting your account." |

### 10.4 Destructive vs reversible

The rule: **destructive things are harder than reversible things.**

| Action | Guard |
|---|---|
| Cancel booking | Confirm dialog naming session + date; warns the trainer is notified |
| Decline request | Sheet with an optional reason delivered to the rider |
| Delete account | Destructive confirm → leave-reason sheet → heavy haptic → blocking overlay |
| Delete review | Confirm dialog |
| Discard profile edits | Confirm dialog (also intercepts predictive back) |
| Finish session | Confirm naming the amount added to earnings |
| Sign out | Confirm; on the role picker it lives in the *trailing* app-bar slot, never the back slot |
| **Approve booking** | No dialog — busy guard + **UNDO** in the toast (happy path, many times a day) |
| **Remove time off** | No dialog — **UNDO** in the toast |
| **Mark all read** | **UNDO** available |
| **Delete notification** | Swipe + confirming toast |

### 10.5 In-flight and failure handling

- Every submit sets a busy flag; `PrimaryButton` swaps its label for a spinner and **keeps
  its brand fill** while busy (a disabled grey pill reads as dead).
- `withBusyOverlay` blocks interaction and back-navigation during multi-second uploads.
- **Sheets that own an upload do not close until it succeeds** (appeal, ticket) — a flaky
  connection must never cost the user their typed text.
- Failed chat/ticket sends **restore the text** to the composer.
- Double-tap protection on approve/decline via a `_busy` guard.
- Back-navigation is blocked while onboarding forms are saving, so an abandoned upload can't
  double-submit from stale state.

### 10.6 Offline & fire-and-forget

Two writes deliberately do **not** await the server, because Firestore's write future only
resolves on server ack and would hang forever offline while the local cache is already correct:

- **Sending a chat message** — latency compensation paints the bubble instantly.
- **Marking a notification read** — navigation must not wait on the network.

### 10.7 Data-quality fallbacks

- Dead image URLs (several Unsplash links in the live DB) → `FlowImage` renders a tinted
  placeholder icon, never a broken-image glyph.
- Missing avatar → first initial of the name; empty name → `?`.
- Missing hourly rate → **€50**. Missing station instructor rate → €50.
- Missing/unparseable date → `--` in date blocks, `—` in time ranges.
- Missing booking end time → treated as running to end of day.
- Firestore ids are assumed 20 chars but the ticket header clamps the substring anyway.
- A malformed QR payload or one belonging to another trainer shows an inline warning and
  **keeps the camera open**.

### 10.8 Accessibility

- Text scaling is **clamped to 0.9–1.3** app-wide (`lib/app.dart`) so dense uppercase labels
  don't overflow their pills.
- Touch targets ≥ 48 dp (stars, chips, scrim buttons, gallery removes, timeline rows).
- Icon-only buttons carry tooltips, which double as TalkBack labels.
- Badge counts are surfaced as spoken sentences ("3 unread messages"), not bare digits.
- Unread state, selection state and swipe-to-delete are exposed semantically, not by colour
  or gesture alone.
- Portrait orientation only; edge-to-edge with transparent system bars.

### 10.9 Motion (functional only, 150–320 ms)

Gate routes cross-fade (260 ms) · tab switches fade (220 ms) · list state swaps cross-fade
(200 ms) · notification tiles tween unread→read (220 ms) · booking total slides on change
(150 ms) · slot tiles animate selection (150 ms) · sections collapse with `AnimatedSize`
rather than jumping · onboarding steps slide in the direction of travel · QR viewfinder
flashes emerald for 250 ms on capture.

### 10.10 Haptics

Selection clicks on slot/day/chip/star taps; light impact on favourite, chat send, appeal
reply, and every toast; medium impact on booking confirm, approve, decline, check-in,
onboarding completion, and the rider's ticket flipping to "started"; heavy impact at the
point of no return on account deletion; vibrate on a bad QR scan.

---

## 11. Notifications — in-app and push

### 11.1 Generated notifications

Every notification is written by `NotificationRepository.notify()` with `targetUserId`
only. (v2.6 dual-wrote a `userId` alias for a web client that queried it; with this app as
the sole writer the alias is dead weight, and the `onNewNotification` Cloud Function reads
`data.userId || data.targetUserId`, so it still resolves — see §6.3.)

| Trigger | Recipient | `type` | Title | Body |
|---|---|---|---|---|
| Rider requests a booking | trainer | `booking_request` | "New booking request" | "{rider} requested {date} at {time}." |
| Trainer approves | rider | `booking_confirmed` | "Booking approved ✅" | "Your session on {date} is confirmed." |
| Trainer declines | rider | `booking_rejected` | "Booking declined" | "…was declined." + " Reason: {reason}" when given |
| Booking cancelled | rider | `booking_cancelled` | "Booking cancelled" | "Your session on {date} was cancelled." |
| Session completed | rider | `review` | "Session complete 🎉" | "Hope it was a good one. Tap to rate your trainer." |
| Rider cancels | trainer | `booking_cancelled` | "Rider cancelled ⚠️" | "{rider} cancelled {title} on {date}." |
| Safari seat reserved | host | `booking_confirmed` | "New safari booking 🛥️" | "{rider} reserved a seat on {trip}." |
| Chat message | recipient | `message` | "Message from {sender}" | body, truncated to 117 chars + "…" |
| Admin approves a trainer | trainer | `account_approved` | "You're live on Flow 🤙" | "Your trainer profile is approved…" |
| Admin declines an application | trainer | `account_rejected` | "Application not approved" | "We could not verify…" + " Reason: {reason}" when given |
| Admin lifts a suspension | user | `account_restored` | "Your account is active again" | "Welcome back. Your suspension has been lifted." |

> The three `account_*` types resolve to `NotificationKind.account`: their own
> icon on the tile, and deliberately the full-text sheet as destination — a
> rejection carries its reason in full, and the account state the message
> announces is already wherever the gate routed the user (was BUG-011, when
> they fell through to `system` by accident).

Walk-ins never notify (`kiterId == 'manual_entry'` has no account behind it), and
`setStatus` returns early for manual bookings or an empty `kiterId`.

### 11.2 In-app tap routing (`notifications_screen.dart`)

| Kind | Destination |
|---|---|
| bookingRequest / bookingConfirmed / bookingRejected / bookingCancelled / reminder | trainer → `/home`; rider → `/sessions?highlight={bookingId}` (or plain `/sessions`) |
| message | `/inbox` |
| review | `/sessions` |
| broadcast / system | no route — opens a sheet with the full text |

Tapping also marks the item read (fire-and-forget).

### 11.3 Push (FCM)

`PushService` + `PushController` (`lib/services/`):

- A **background handler is registered before `runApp`** so pushes arriving while the app is
  killed are handled. It is intentionally empty — the Cloud Function sends a `notification`
  payload that Android renders itself; the handler exists so the plugin is registered and
  tap-through data survives.
- **Permission** is requested (required on Android 13+) the first time a uid appears; the
  FCM token is then written to `users/{uid}.fcmToken`, and re-written on every token refresh.
  A failure (e.g. mid-onboarding, no profile document yet) is swallowed and retried next launch.
- **Foreground pushes** are shown as an in-app snackbar with title, body and a **VIEW**
  action, because Android suppresses the system notification while the app is focused.
- **Tap routing** (`_handleTap`) — from a running app, and from a cold start via
  `getInitialMessage()`:
  ```
  type startsWith "booking" OR data.bookingId present → trainer: /home, rider: /sessions
  type == "message"                                   → /inbox
  otherwise                                           → push /notifications
  ```

> **Gap worth closing in the redesign:** the push tap routes to a bare `/sessions`, while the
> in-app list routes to `/sessions?highlight={bookingId}`. The push carries `bookingId` in
> its data payload, so it could use the same deep link and land on the right booking.

---

## 12. External services & API contracts

**There are no AI/LLM calls and no prompt templates anywhere in this application.** There is
exactly **one** non-Firebase HTTP call: the wind forecast.

| Service | Package | Used for |
|---|---|---|
| Firebase Auth | `firebase_auth` | Email/password sign-in, sign-up, reset, delete, session stream |
| Cloud Firestore | `cloud_firestore` | All application data (§6) |
| Firebase Storage | `firebase_storage` | Profile photos, galleries, certificates, report/appeal evidence |
| Firebase Messaging | `firebase_messaging` | Push tokens, foreground messages, tap routing |
| Open-Meteo | `dart:io` `HttpClient` | 8-day wind forecast per spot (§3.11) |
| Google Maps | `url_launcher` | Opens a trainer's `mapsLink` externally |
| Camera / gallery | `image_picker`, `mobile_scanner` | Photo picking, QR scanning |

**Wind contract.** `GET https://api.open-meteo.com/v1/forecast`, keyless and unauthenticated,
called directly through `HttpClient` rather than adding `package:http` for one request. Every
error path — offline, DNS failure, timeout, malformed body — returns an empty forecast rather
than throwing, so a dead connection degrades to "no forecast" and never to an error state.

**Firebase project:** `wlf-flow` (Android app id
`1:194435155894:android:6751bfee6f9b0b3c82e317`). Config lives in `lib/firebase_options.dart`
and `android/app/google-services.json`. **`applicationId` must remain `com.wlftech.flow`** —
changing it breaks push and turns the app into an unrelated Play listing.

**Server-side — `functions/`, in this repo** (TypeScript, Firebase Functions v2):

| Function | Trigger | Does |
|---|---|---|
| `onNewNotification` | new `notifications/{id}` document | Sends the FCM push to the recipient's token; prunes tokens the messaging API reports as dead |
| `sendSessionReminders` | schedule | Generates reminder notifications for imminent sessions |

Neither has ever run: the Cloud Functions API is not enabled on the project, so nothing is
deployed. Push is therefore specified but not operational.

### 12.1 Upload contract

`ImageService` downscales before upload: **max 1600 px on the long edge, JPEG quality 82**.
`StorageRepository.upload` names files `{ownerId|anon}_{millisSinceEpoch}_{base36 random}{ext}`
and sets a content type from the extension (`.png`, `.webp`, `.heic`, `.pdf`, else `image/jpeg`).
Multi-file uploads are sequential. There is no client-side timeout race — the task's own
retry handles slow beach connections.

### 12.2 QR payload contract

The only serialised interchange format in the app.

```json
{ "bookingId": "<firestore booking id>", "trainerId": "<trainer uid>" }
```

Produced by the rider's ticket dialog (`qr_flutter`), consumed by the trainer's scanner
(`mobile_scanner`). The scanner rejects non-JSON, non-object payloads, payloads missing
either key, and any `trainerId` that doesn't match the scanning trainer.

---

## 13. Constants & configuration

**Kite spots** (`lib/core/constants.dart`) — the fixed, closed list used by filters and both
onboarding forms:
El Gouna · Abu Soma Bay · Safaga · LahamiBay · Dahab · Hurghada-Magawish ·
Marsa Alam Tulip · Soma Bay · Marsa Alam El Naaba · Ras Soma Bay

**Suggested languages** (users may add their own): English, Arabic, German, French, Spanish,
Italian, Russian, Polish, Dutch, Portuguese, Czech, Turkish, Mandarin, Hindi, Japanese, Korean

**Rider levels** (closed list): New · Independent · Advanced · PRO

**Report reasons** (closed list): Inappropriate behavior · Fake profile / Scam ·
Unprofessional conduct · Safety concerns · Other

**Quiver suggestions:** 7m, 9m, 10m, 12m, 14m, 17m, Twin tip, Surfboard, Foil

**Numeric constants**

| Constant | Value | Where |
|---|---|---|
| Min / max hourly rate | €60 / €110 | Trainer onboarding |
| Default display rate | €50 | `AppUser.displayRate` |
| Bookable hours | 08:00–17:00 start, ends by 18:00 | `BookingMath` |
| Default travel buffer | 60 min | `AppUser.bufferMinutes` |
| Same-day lead time | `now.hour + 1` | `pastSlots` |
| Day-strip length | 21 days | Booking |
| Walk-in durations | 1, 2, 3, 4 h | Schedule |
| "Coming up" limit | 10 | Command Center |
| Chat follow threshold | 120 px from bottom | Chat |
| Chat timestamp gap | 10 min | Chat |
| Message preview truncation | 117 chars + "…" | Notifications |
| Image max dimension / quality | 1600 px / 82 | Uploads |
| Text scale clamp | 0.9 – 1.3 | `app.dart` |
| Version label | `FLOW 2.6.0` | Profile |

**Persisted local keys:** `themeMode`, `trainerTourDone_{uid}`

---

## 14. Known limitations, quirks & deliberate behaviours

### 14.1 Deliberate divergences from the predecessor web app

- **Passwords are never stored.** Firebase persists sessions; password reset replaced
  "remember me".
- **Notifications write both recipient fields** (see §11.1).
- **Appeal replies use `arrayUnion`** — the web version read-modify-wrote the array and lost
  concurrent replies.
- **Chat unread counts use `FieldValue.increment`** instead of a hardcoded `1`.
- **Dark mode is a real designed theme**, not a CSS `invert()` filter (which inverted photos).
- **Uploads are downscaled** rather than sent at full resolution.
- **Reviews require a completed, unreviewed booking** — enforced before the form renders.
- **The auth wave is drawn with a `CustomPainter`**, not loaded: `public/new-wave.png` is
  corrupt at source (starts `EF BF BD 50 4E 47` instead of the PNG magic; 12,567 of its
  58,938 bytes are the UTF-8 encoding of U+FFFD). It never rendered in the web app either.
- **`PartnerPortal`'s manifest query was dropped** — it filtered on `stationId` while
  bookings are written with `instructorId`, so it was always empty.

### 14.2 Structural limitations

- **Booking collisions are checked, not locked** (§8.6).
- **The admin panel is not ported.** Trainer approvals, report handling, appeal moderation,
  broadcasts and trainer-spot management all still happen in the web build. The
  *rider-facing* half of appeals is here.
- **Android only.** `firebase_options.dart` throws for other platforms.
- **No payments.** Everything is settled in person.

### 14.3 Quirks a redesign should be aware of

| Quirk | Detail |
|---|---|
| **Trainers cannot change their rate in-app** | Edit profile writes name, phone, bio, nationality, age, level, languages, photo and gallery — *not* `hourlyRate`/`priceList`. The rate is set once during onboarding. |
| **Trainers cannot change their spot in-app** | `location` is rendered read-only with "Message support if you've moved". |
| **Unrated trainers show "5.0"** | `RatingSummary.none` is `average: 5.0, count: 0`. |
| **Travel buffer is stored but not enforced** | See §8.3. |
| **`instantBooking` is gone** | Removed from `AppUser`: it was parsed from the profile and no caller ever used it. Every rider booking is created `pending`. |
| **`rejected` accounts fall through to `ready`** | See §2.4. They get a Command Center but are absent from Explore. |
| **`paymentStatus: 'paid'`** | Written on safari bookings; means nothing. |
| **`Col.listings` / `Col.broadcasts`** | Declared but never read or written by this client. |
| **All ratings load as one collection snapshot** | `ratingsProvider` streams the entire `reviews` collection to compute Explore's averages. Fine at current scale; a scaling risk. |
| **Sorting is client-side by design** | Moving it server-side requires composite indexes (§6.2). |
| **Trainers have no Sessions tab** | Navigating a trainer to `/sessions` leaves the nav bar highlighting Dashboard while showing a rider screen. Do not route trainers there. |
| **Chat has no read receipts or typing indicators** | `ChatMessage.read` exists on the model and is written `false`, but is never updated or displayed. |
| **Push tap ignores `bookingId`** | See §11.3. |

### 14.4 Not carried over from the web app

Roughly 4,500 lines were unreachable (imported but never rendered, or never imported) and
intentionally left behind: `geminiService.ts`, `ForecastTool`, `SafetyRescueTool`,
`CoachingTool`, `CoachingPage`, `CoachesList`, `SafariGuide`, `BecomeHost`,
`AdminDashboard`, `SafariDashboard`. Safari/expedition booking **is** live and was ported.

---

## 15. Redesign checklist — what must not be lost

Treat every item here as a functional requirement, not a stylistic one.

**Data & compatibility**
- [ ] Local `YYYY-MM-DD` date strings everywhere — never `toISOString()`
- [x] ~~Dual-write legacy + modern field names on bookings~~ — deliberately dropped; this
  app is the sole writer, one canonical name each (§6.3, booking_repository.dart)
- [x] ~~Dual-write `targetUserId` + `userId` on notifications~~ — deliberately dropped
  (§11.1, notification_repository.dart)
- [ ] Tolerant readers for every Firestore field
- [ ] Collection names unchanged; client-side sorting retained
- [ ] `applicationId` stays `com.wlftech.flow`

**Correctness**
- [ ] Availability composition and same-day lead-time rule (§8.2, §8.5)
- [ ] Contiguous-only hour selection, cleared on day change (§8.4)
- [ ] Pre-write slot re-check; transactional safari seats (§8.6)
- [ ] Bucketing rules including the end-of-day fallback (§8.7)
- [ ] Review eligibility gate + repository double-submit guard (§8.9)
- [ ] Chat id derivation (sorted uids joined by `_`)
- [ ] QR payload shape and trainer-match validation (§12.2)

**Experience guarantees**
- [ ] Loading never renders a confident wrong answer (§10.2)
- [ ] Every async surface has a retry; no error dead ends (§10.1)
- [ ] Destructive actions confirmed; frequent reversible ones get undo instead (§10.4)
- [ ] Sheets owning an upload stay open until it succeeds (§10.5)
- [ ] Chat never steals scroll position from someone reading history (§3.11)
- [ ] Unread messages visible in the inbox *and* on the tab (§8.11)
- [ ] Booking notifications land on the specific booking, in the right tab (§3.7)
- [ ] Trainers are never routed to the Sessions branch (§14.3)
- [ ] Text-scale clamp, 48 dp targets, tooltips-as-labels, semantic state (§10.8)

**Role gating**
- [ ] The `AppStage` precedence order (§2.3)
- [ ] Trainers pending approval are held at the gate and released live
- [ ] Staff bypass the approval gate
- [ ] Explore shows only `role == 'business' && status == 'active'`

---

*Generated from a full read of `lib/` at version 2.6.0. Every claim above is traceable to a
source file; section headings name the file where the logic lives.*
