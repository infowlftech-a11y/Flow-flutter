# FLOW — Application Logic Blueprint

**Purpose of this document.** A complete, implementation-independent specification of
what the FLOW app *does*. It is written to be the sole context for a ground-up UI/UX
redesign: every rule, flow, data shape, validation and edge case below must survive
that redesign, even though no layout or visual decision needs to.

Nothing here describes styling. Where a visual detail is mentioned, it is because it
carries meaning (e.g. "blocked hours are not tappable"), not because it should look
that way.

- **Codebase:** Flutter 3.44+ / Dart 3.12, Android only (`com.kiteflow.app`)
- **Backend:** Firebase — Auth, Firestore, Storage, Cloud Messaging (project `go-kite-ccc33`)
- **State:** Riverpod 3 · **Routing:** go_router 17 · **Local prefs:** shared_preferences
- **Source of truth:** `lib/`, 56 Dart files, ~17k lines

> **There is no AI integration.** No Gemini, no Google AI Studio, no LLM API, no prompt
> templates, no system instructions. The predecessor React app imported `GoogleGenAI`
> but never called it, and `geminiService.ts` was never imported by anything; both were
> intentionally dropped. Section 12 documents the complete set of external calls. If the
> redesign is expected to *add* AI, it is a new feature with no existing contract to honour.

---

## Table of contents

1. [Core concept & value proposition](#1-core-concept--value-proposition)
2. [Roles, account lifecycle & the gate state machine](#2-roles-account-lifecycle--the-gate-state-machine)
3. [Complete feature catalogue](#3-complete-feature-catalogue)
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

## 3. Complete feature catalogue

### 3.1 Authentication (`features/auth/auth_screen.dart`)

- Single screen toggling between **Log in** and **Create account**.
- Sign-up collects: full name, email, password. Log-in: email, password.
- Password visibility toggle.
- **Forgot password** — sends a Firebase reset email. Requires a syntactically valid
  email in the field first; otherwise it errors and focuses the email field.
- Platform password-manager integration via `AutofillGroup` +
  `TextInput.finishAutofillContext()` on success.
- On sign-up, the Firebase `displayName` is set from the name field.
- **No "remember me" and no credential storage** — Firebase persists the session itself.
  (The predecessor web app wrote plaintext email/password into `localStorage`; this was
  removed deliberately.)
- **Silent fallback:** signing up with an already-registered email attempts a sign-in with
  the same credentials instead of erroring.

### 3.2 Onboarding

**Role selection** (`features/onboarding/role_select_screen.dart`)
- Two choices: "I'm a Kiter" / "I'm a Trainer". Sign-out lives in the app-bar *trailing*
  slot (never the back slot).
- States plainly that trainer accounts are reviewed before going live.

**Rider form** (`kiter_form_screen.dart`) — single page:
avatar (optional) · full name\* · nationality\* · age\* · kite level (default `Independent`)
· home spot · languages\* · quiver · short bio.
Writes `role: 'kiter'`, `status: 'active'`.

**Trainer form** (`trainer_form_screen.dart`) — 4 gated steps:
1. **Trainer profile** — photo\*, name\* (>2 chars), professional bio\*, languages\*, gallery (multi-image)
2. **Training spot** — spot from the fixed list\*, optional Google Maps link
3. **Your rate** — hourly rate\*, integer, €60–€110
4. **Verification** — IKO/VDWS ID\* (>3 chars), optional certificate image

Writes `role: 'business'`, `status: 'pending'`, `businessType: 'Instructor'`, and both
`priceList` (string) and `hourlyRate` (int) for web-client compatibility.

### 3.3 Rider — Explore (`features/explore/explore_screen.dart`)

- Grid of every **approved** trainer/station (`role == 'business' && status == 'active'`).
- **Free-text search** across name + location + bio (case-insensitive substring).
- **Filter sheet:** spot (single-select from the 10 spots) and languages (multi-select).
- **Quick toggles:** All trainers / Favourites; active spot and language filters appear as
  individually removable chips.
- Result count and a one-tap **RESET** for all filters + search.
- Per card: photo, favourite heart (optimistic), name, average rating, location, hourly
  rate, and a "Station" badge for stations.
- Notification bell with unread badge.
- Pull-to-refresh; skeleton grid on first load.

### 3.4 Rider — Trainer profile (`explore/trainer_profile_screen.dart`)

- Collapsing photo header — swipeable gallery (profile photo + gallery images), page dots,
  tap to open a full-screen zoomable viewer.
- Name, verified badge, average rating + review count, hourly rate.
- Info tiles: **Location** (tappable → opens Google Maps externally if `mapsLink` set) and
  **Certification** (`IKO {id}` or "Verified trainer").
- About (bio), Speaks (languages).
- **Reviews** — full list; each shows name, time-ago, stars, comment. You can delete your own.
- **Review composer** appears *only* if the rider has a completed, not-yet-reviewed booking
  with this trainer (checked before render, not just on submit).
- **Report trainer** — reason (from a fixed list) + free-text details + optional screenshot
  attachments.
- Favourite toggle.
- Sticky bottom bar: rate · **Message** · **Book now**.
- **Self-view:** when the viewer *is* this trainer, favourite/report/message/book are replaced
  by **Edit profile**, and a "Your public profile" marker is shown.

### 3.5 Rider — Station / safari profile (`explore/station_profile_screen.dart`)

Collapsing cover header, name, location pill, type pill, bio, and pinned tabs that differ
by operator type:

- **Safari operator** → one tab: **Expeditions**
- **Station** → three tabs: **Lessons**, **Rentals**, **Beach** (each tab shows its count)

**Lessons tab** — station instructors (name, level, rate, photo) each with a **BOOK** button
that opens the booking flow against the *station's* calendar with the instructor as `subTarget`.

**Rentals / Beach tabs** — services with name, description, price + unit, and a **BOOK** button
(`bookingType` `rental` or `beach_use`).

**Expeditions tab** — safari trips with title, duration pill, departure date, price per seat,
seats-left counter, a fill-ratio progress bar, description, and **Reserve my seat** (disabled
and labelled "Manifest full" when sold out). Reserving is **transactional** (see §8.6).

### 3.6 Rider — Booking flow (`features/booking/booking_sheet.dart`)

Full-screen flow, four conceptual stages on one scroll:

1. **Who** — provider card (avatar, name/sub-target, location, rate).
2. **Pick a day** — horizontal strip of the next **21 days** starting today; "TODAY" label
   on day 0.
3. **Available hours** — 3-column grid of the 10 bookable hours. Each tile shows its range
   (`09:00–10:00`) and a state word: `Free`, `Selected`, or a blocked reason (`Away`,
   `Too soon`, `Booked`, `Unavailable`). Free tiles are tappable; blocked ones are not.
   - Whole-day time off → a single "Away on this date" notice instead of the grid.
   - Every hour taken → "Fully booked" notice.
   - **CLEAR** appears once anything is selected.
4. **Summary** (appears only with a selection) — time range, hour count, total, a free-text
   message to the trainer, and an "I need gear" switch.

Sticky bottom bar: hour count + live total (a dash, not `€0`, before selection) and
**Review & confirm**.

**Review sheet** — Service, Date, Time, Duration, Gear rows; a total panel showing
`€rate × hours`, the total, and a "Pay at centre" marker; a note that the rider's level is
shared with the trainer; **Confirm booking**.

**Success dialog** — "Request sent!", not dismissible by tapping outside; the single **Done**
button closes the dialog and pops the booking screen.

### 3.7 Rider — My sessions (`features/sessions/sessions_screen.dart`)

Three tabs — **UPCOMING** (with a count), **ACTIVE** (with a live dot when non-empty),
**HISTORY** — over the rider's bookings.

Per booking card: date block (month + day), title, time range, total price, status pill,
and a sub-label explaining the status in words. Actions depend on status:

| Status | Actions |
|---|---|
| `pending` | Cancel |
| `confirmed` | **Check in** (QR ticket) · Cancel |
| `inProgress` | **Check in** (shows live ticket) |
| `completed` | **Rate** |
| `cancelled` / `rejected` | none |

- **QR ticket dialog** — renders a QR encoding `{"bookingId":…,"trainerId":…}`, always on a
  white background so scanners work in dark mode. It watches the booking live and flips to
  "Session started" the moment the trainer scans, with a haptic on that transition.
- **Rate** — inline review composer (stars + optional comment) without leaving the screen.
- **Cancel** — confirmation dialog naming the session and date; warns the trainer is notified.
- **Deep link:** `/sessions?highlight=<bookingId>` (from a booking notification) selects the
  tab that actually contains that booking, scrolls the card into view and tints it ~4s.
- Pull-to-refresh per tab.

### 3.8 Trainer — Command Center (`features/command_center/command_center_screen.dart`)

Two tabs: **TODAY** and **SCHEDULE**, plus a persistent **CHECK IN** floating action button
that opens the QR scanner from anywhere.

**TODAY tab**
- **Three stat tiles:** Requests (taps → scrolls to the requests section), Upcoming,
  Total earned (taps → opens the earnings ledger).
- **Action required** — pending requests. Each card shows rider avatar, name, level, price,
  date + time range, the rider's message, and a "Needs gear" pill.
  - **APPROVE** — busy-guarded, haptic, and an **UNDO** action in the confirmation toast.
  - **DECLINE** — opens a sheet for an optional reason, which is delivered to the rider.
- **Today · {date}** — today's manifest, sorted by start time. Each card shows the rider,
  time range, walk-in/gear pills, price, and:
  - `confirmed` → **SCAN TO START**
  - `inProgress` → **FINISH SESSION** (confirmation names the amount added to earnings)
  - Tapping the card opens read-only details (message, level, gear) + **Message rider**.
  - Empty state: "No sessions today — Enjoy the wind."
- **Coming up** — next 10 upcoming bookings (compact rows, tap for details).

**Earnings ledger** (sheet) — all-time and month-to-date totals, plus every completed session
with rider, date, hours and amount.

**First-run tour** — a 4-step dialog (Command Center / approve-decline / QR check-in /
calendar control) shown once per uid, persisted in SharedPreferences.

### 3.9 Trainer — Schedule (`command_center/schedule_tab.dart`)

- **Day navigator** — previous/next chevrons and a tappable date that opens a date picker
  (today → +1 year).
- **WALK-IN** and **TIME OFF** buttons kept above the timeline (time-critical beach tasks).
- **Day timeline** — one row per bookable hour showing either the booking that occupies it
  (rider name, walk-in marker) or its state: `Available`, `Blocked`, `Past`, `Away`.
  - Tap a free hour to block it; tap a blocked hour to release it. Booked, past and
    away hours are not tappable.
  - A "{n} blocked" counter, hidden while loading rather than showing a misleading `0`.
- **Whole-day-off banner** when a vacation covers the day.
- **Add walk-in** sheet — student name\*, start time (only genuinely free hours are offered)\*,
  duration (1/2/3/4h), total price (pre-filled with `rate × 1`). Creates a confirmed booking.
- **Time off** sheet — reason, from-date, to-date (the "to" picker cannot precede "from").
- **Scheduled time off** list with per-entry delete, and **UNDO** in the confirmation toast.
- Pull-to-refresh resyncs blocks, bookings and vacations.

### 3.10 Trainer — QR scanner (`command_center/qr_scanner_screen.dart`)

- Rear camera, `noDuplicates` detection, torch toggle whose icon reflects actual torch state.
- Scrimmed viewfinder cutout; the frame flashes emerald for 250 ms on a successful capture
  before popping.
- **Validation:** payload must be JSON containing `bookingId` and `trainerId`, and the
  `trainerId` must match the scanning trainer. Failures show an inline warning banner for
  3 s and **keep the camera open** rather than dismissing.
- Denied/unavailable camera renders an explanatory screen with a retry, never a black void.
- On success the caller calls `checkIn(bookingId)` and toasts "Session started 🤙".

### 3.11 Messaging (`features/chat/`)

**Inbox** — every thread the user participates in, newest first. Per row: partner avatar,
name, last message preview, time-ago, and **unread count**. Unread rows are tinted and
bolded. Search filters by partner name. The **Inbox tab carries a total unread badge**.

**Chat thread** — grouped bubbles (consecutive messages from one sender share a run),
absolute timestamps inserted only when there is a >10-minute gap, long-press any bubble to
copy, send button disabled while the input is empty.
- Sending is **fire-and-forget** — Firestore's local snapshot paints the bubble instantly;
  a failure restores the text to the composer and toasts.
- Scroll behaviour: jumps to the newest message on first load; afterwards follows new
  messages **only when already near the bottom** (within 120 px), so reading history is
  never interrupted.
- A **jump-to-latest** control appears once scrolled up, showing how many messages arrived
  while away.
- Opening a thread creates the thread document if needed and clears the unread counter.

### 3.12 Notifications (`features/notifications/notifications_screen.dart`)

- Chronological list; unread items are tinted and carry a dot.
- **Mark all read** (batched) appears only when something is unread.
- **Swipe to delete** with a confirming toast; also exposed to screen readers as a custom
  action.
- Tapping routes by kind — see §11.2.
- Broadcast/system notifications have no destination, so tapping opens a sheet with the
  full untruncated text.

### 3.13 Profile & settings (`features/profile/`)

- Identity block: avatar (tap → edit), name, email, and pills for role/level, nationality,
  location.
- **Account:** Personal details · *View my public profile* (trainers only) · Notifications · Help & support
- **Appearance:** Auto / Light / Dark, persisted locally
- **Privacy:** "Security & data" explainer sheet (session encryption, what trainers see,
  photo storage)
- **Sign out** (confirmed)
- **Danger zone → Delete my account** — placed last, behind two steps: a destructive
  confirmation, then a "why are you leaving?" sheet. Records the reason, deletes the
  Firestore profile, then deletes the auth user. If Firebase requires recent login, the
  user is told to sign out and back in.
- App version label.

**Edit personal details** — avatar, name\*, email (read-only), phone, nationality, age,
kite level (riders only), training spot (trainers, read-only), bio, languages\*, and a
gallery manager (trainers only) with "New" badges on not-yet-uploaded picks.
- Save is disabled until something actually changes.
- Leaving with unsaved changes prompts to discard.

### 3.14 Support & appeals (`features/support/`, `features/gates/blocked_screen.dart`)

**Support tickets** — list of the user's tickets with open/resolved state; open a new ticket
(subject\* + body\*); a thread view with a composer that locks when support resolves the
ticket, replaced by a **REOPEN** action.

**Appeals** (blocked users only) — submit an appeal with a written reason\* and optional
image evidence, then continue a conversation with admins in-thread. The appeal sheet
**stays open until the upload succeeds**, so a flaky connection can never discard a typed
appeal.

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
| `instantBooking` | bool | | Read but **never used** to skip approval |
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
`label`. `status` is `'host-blocked'` (calendar) or `'occupied'` (legacy toggle); both mean
unavailable, and **any other status is ignored**.

**`Vacation`** — `vacations/{id}`: `instructorId`, `startDate`, `endDate`, `label`.
`covers(date)` is an inclusive lexicographic string comparison — valid because dates are
zero-padded `YYYY-MM-DD`.

**`DayAvailability`** (computed, never stored): `date`, `blocked`, `booked`, `onVacation`,
`past`.
- `isFree(slot)` ⇔ not on vacation **and** not blocked **and** not booked **and** not past.
- `blockedReason(slot)` precedence: `Away` → `Too soon` → `Booked` → `Unavailable`.

### 5.4 Social

**`Review`** — `reviews/{id}`: `listingId` (**this is the trainer's uid**, misleadingly
named for historical reasons), `userId`, `userName`, `rating` (clamped 1–5), `comment`,
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
| Reviews for trainer | `listingId == trainerId` | client-side, newest first |
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

**Booking created by a rider** (`createBooking`) writes *both* legacy and modern field names:

```jsonc
{
  "id": "<docId>", "instructorId": "...", "instructorName": "...",
  "kiterId": "<riderUid>", "guestId": "<riderUid>",
  "studentName": "...", "studentLevel": "Rider",
  "listingTitle": "Trainer — SubTarget",   // or just the title
  "serviceName": "<subTarget or title>",
  "subTarget": "...",                       // only when present
  "date": "2026-08-14",
  "time": "09:00", "startTime": "09:00",    // both, for the web client
  "endTime": "11:00", "bufferedEndTime": "12:00",
  "selectedTimes": ["09:00","10:00"], "durationHours": 2,
  "price": 240, "totalPrice": 240,          // both
  "type": "lesson", "bookingType": "lesson",// both
  "gearNeeded": false, "message": "...",
  "status": "pending",
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

**Notification** — always writes **both** recipient fields:
```jsonc
{ "targetUserId": "<uid>", "userId": "<uid>", "title": "...", "message": "...",
  "type": "booking_request", "read": false, "createdAt": "<serverTimestamp>",
  "bookingId": "..." }
```

**Chat message** → `chats/{id}/messages`: `{senderId, receiverId, text, createdAt, read:false}`
Then the thread: `{lastMessage, lastMessageTimestamp, updatedAt, unreadCount: {<receiverId>: increment(1)}}`
**Mark read** → `{unreadCount: {<uid>: 0}}` (merge, so only that participant's entry changes).

**Availability block** — `{instructorId, date, startTime, endTime, status: 'host-blocked', label, createdAt}`
**Vacation** — `{instructorId, startDate, endDate, label, createdAt}`
**Review** — `{listingId, userId, userName, rating, comment, bookingId, createdAt}`
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
             ∧ slot ∉ blocked      (availability docs, status host-blocked|occupied)
             ∧ slot ∉ booked       (bookings whose status.isLive)
             ∧ slot ∉ past         (same-day lead time)
```
Cancelled, declined and completed bookings **release** their hours.
`expandBlock(start, end)` covers `[startHour, endHour)`; a block with no distinct end covers
only its start hour.

### 8.6 Collision handling

- **Hourly bookings are checked, not locked.** `createBooking` and `createWalkIn` re-query
  the day's bookings immediately before writing and throw `SlotTakenFailure` on a clash.
  Firestore transactions cannot read a *query*, only known documents, so with this schema a
  true lock is impossible without a per-slot document — a schema change the web client
  wouldn't respect. Two riders confirming the same hour in the same instant both land as
  pending requests, and the trainer declines one.
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
`listingId`.

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

Every notification is written by `NotificationRepository.notify()` with **both**
`targetUserId` and `userId` (the web client wrote only `userId` in places, and those
notifications were invisible to the listener, which queries `targetUserId`; writing both
keeps the query working *and* still triggers the `onNewNotification` Cloud Function, which
reads `data.userId || data.targetUserId`).

| Trigger | Recipient | `type` | Title | Body |
|---|---|---|---|---|
| Rider requests a booking | trainer | `booking_request` | "New booking request" | "{rider} requested {date} at {time}." |
| …with instant confirm | trainer | `booking_confirmed` | "New instant booking ⚡" | "{rider} booked {date} at {time}." |
| Trainer approves | rider | `booking_confirmed` | "Booking approved ✅" | "Your session on {date} is confirmed." |
| Trainer declines | rider | `booking_rejected` | "Booking declined" | "…was declined." + " Reason: {reason}" when given |
| Booking cancelled | rider | `booking_cancelled` | "Booking cancelled" | "Your session on {date} was cancelled." |
| Session completed | rider | `review` | "Session complete 🎉" | "Hope it was a good one. Tap to rate your trainer." |
| Rider cancels | trainer | `booking_cancelled` | "Rider cancelled ⚠️" | "{rider} cancelled {title} on {date}." |
| Safari seat reserved | host | `booking_confirmed` | "New safari booking 🛥️" | "{rider} reserved a seat on {trip}." |
| Chat message | recipient | `message` | "Message from {sender}" | body, truncated to 117 chars + "…" |

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

**There are no HTTP APIs, no REST endpoints, no GraphQL, no AI/LLM calls, and no prompt
templates anywhere in this application.** Every external interaction is a Firebase SDK call.

| Service | Package | Used for |
|---|---|---|
| Firebase Auth | `firebase_auth` | Email/password sign-in, sign-up, reset, delete, session stream |
| Cloud Firestore | `cloud_firestore` | All application data (§6) |
| Firebase Storage | `firebase_storage` | Profile photos, galleries, certificates, report/appeal evidence |
| Firebase Messaging | `firebase_messaging` | Push tokens, foreground messages, tap routing |
| Google Maps | `url_launcher` | Opens a trainer's `mapsLink` externally |
| Camera / gallery | `image_picker`, `mobile_scanner` | Photo picking, QR scanning |

**Firebase project:** `go-kite-ccc33` (Android app id `1:1046182479508:android:1861e99d8b1c408569d681`,
bucket `go-kite-ccc33.firebasestorage.app`). Config lives in `lib/firebase_options.dart` and
`android/app/google-services.json`. **`applicationId` must remain `com.kiteflow.app`** — changing
it breaks push and turns the app into an unrelated Play listing.

**Server-side (not in this repo):** a Cloud Function `onNewNotification` fires on new
`notifications` documents and sends the FCM push, reading the recipient as
`data.userId || data.targetUserId`.

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
| **`instantBooking` is dead** | Parsed from the profile and `createBooking` accepts an `instantConfirm` flag, but **no caller ever passes it** — every rider booking is created as `pending`. |
| **`rejected` accounts fall through to `ready`** | See §2.4. They get a Command Center but are absent from Explore. |
| **`listingId` means trainer uid** | On `reviews` documents, for historical reasons. |
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
- [ ] Dual-write legacy + modern field names on bookings (`time`/`startTime`, `price`/`totalPrice`, `type`/`bookingType`)
- [ ] Dual-write `targetUserId` + `userId` on notifications
- [ ] Tolerant readers for every Firestore field
- [ ] Collection names unchanged; client-side sorting retained
- [ ] `applicationId` stays `com.kiteflow.app`

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
