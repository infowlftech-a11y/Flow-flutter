# FLOW 1.0 — Own the Wind

Kitesurfing lessons on the Egyptian Red Sea. Riders find certified coaches, book
hours on the water and check in on the beach with a QR ticket; coaches run their
whole day from a Command Center; staff run the marketplace from a nine-tab
console.

> **Identity:** display name `Flow` · application id `com.wlftech.flow` ·
> version `1.0.0+1` · Firebase project `wlf-flow` · Android only.

**Status — first public release.** `flutter analyze` clean; **813 Dart tests**
and **389 security-rules tests** green; `firestore.rules` and `storage.rules`
deployed to `wlf-flow`. Cloud Functions are written but **not deployed**, so
push notifications are not delivered yet — see [Backend](#backend-functions).

Scale: 110 Dart files / ~32,000 lines under [lib/](lib/), 51 test files /
~11,400 lines under [test/](test/). Release APK is 29.6 MB
(`--split-per-abi`, arm64).

---

## Contents

- [What shipped in 1.0](#what-shipped-in-10)
- [Money](#money) — escrow, commission, cancellation
- [Security model](#security-model)
- [Design language](#design-language)
- [Project layout](#project-layout)
- [Navigation and gates](#navigation-and-gates)
- [Conditions forecast](#conditions-forecast)
- [Backend (`functions/`)](#backend-functions)
- [Running it](#running-it)
- [Standing up a fresh Firebase project](#standing-up-a-fresh-firebase-project)
- [Test data](#test-data)
- [Testing](#testing)
- [Deliberate behaviours](#deliberate-behaviours)
- [Known limits](#known-limits)
- [Document map](#document-map)

---

## What shipped in 1.0

The app was rebuilt from [APP_LOGIC_BLUEPRINT.md](APP_LOGIC_BLUEPRINT.md) —
every rule, data shape and edge case in that document survives — and then grew
fifteen numbered product changes, each proposed, approved and recorded in
[FLOW_REDESIGN.md](FLOW_REDESIGN.md) before it was built.

| # | Change |
|---|---|
| P1 | **Payments move through FLOW** — escrow at booking, payout after delivery, a booking.com-shaped cancellation policy |
| P2 | **Every event notifies**, and every notification deep-links somewhere real |
| P3 | **Member IDs** (`FLW-R-7X8K`) and a console dossier behind every person |
| P5 | **Instant Book** — per-coach opt-in, enforced by the database, not just the UI |
| P6 | **Security hardening** — App Check, email verification before paying, append-only staff audit log |
| P7 | **Free-cancellation deadline reminder** |
| P8 | **The booking record PDF** — a session you can hand to someone who was not there |
| P9 | **Ticket topics** — a support ticket says what it is about before anyone opens it |
| P10 | **Every ID in the console is a door** — ticket → booking → person → history |
| P11 | **Coach profiles say more**, and every coach name leads to one |
| P12 | **Motion with one accent** — branch cross-fades, a single rise-in push transition |
| P13 | **One top bar** across every top-level destination |
| P14 | **FLOW takes 20%, the coach takes 80%** |
| P15 | Two latent ledger bugs closed (refunds excluded from earnings, DST-safe week chart) |

P4 is the unbuilt backlog — a Booking.com parity review kept as a menu of
costed, unordered options.

---

## Money

**FLOW holds the money.** A rider pays FLOW when they book; FLOW pays the coach
after the session is delivered. This is the single biggest thing to understand
about the app, and it is enforced in three places: the repository writes it, the
providers derive from it, and `firestore.rules` refuses anything else.

### The escrow ledger

Every rider booking is written `paymentStatus: 'held'`, `paymentMethod: 'app'`
with a server `paidAt` ([booking_repository.dart:326](lib/data/repositories/booking_repository.dart#L326)).
Walk-ins a coach books in person are the one cash path.

| Status | Means |
|---|---|
| `unknown` | No payment information was ever recorded — history from before tracking existed. **Not the same as unpaid** |
| `unpaid` | Cash owing (walk-ins) |
| `held` | The rider paid FLOW. The normal state of every new booking |
| `paid` | Cash collected in person |
| `refunded` / `paid_out` | Executed by FLOW — the states a processor will write |
| `processing` / `failed` | Modelled for an async processor; nothing writes them yet |

What a booking is *entitled* to — refund due, payout due — is **derived, never
stored** (`EscrowState`, [cancellation.dart](lib/data/models/cancellation.dart)).
Executed statuses win over the derivation, so once money actually moves the
record stops arguing with itself.

### The 20% platform commission

`FlowConst.platformCommissionRate = 0.20`
([constants.dart:306](lib/core/constants.dart#L306)), and the derivation lives in
exactly one place:

```dart
double get trainerEarning => amountDue * FlowConst.trainerShareRate;  // 80%
```

Derived, never stored, so no client can forge a coach's cut. **The rider always
sees the full rate** — profile price, booking, receipt, the escrow hold. **Only
coach-facing figures are net**: the dashboard's Earned tile, the earnings week
chart, all-time, owed-to-you, and each completed-session row.

### Cancellation

One window, disclosed before paying: **free until 24 hours before the start**
([cancellation.dart:31](lib/data/models/cancellation.dart#L31)).

- A `pending` request refunds in full at any time — nothing was agreed yet.
- Inside the window, a rider cancellation is **charged in full** and the hours
  are paid out to the coach. It protects committed time, which is the whole
  point of a deadline.
- A coach cancellation or decline always refunds the rider, whenever it happens.

Authorship is authenticated: a rider cancel must be signed `cancelledBy: 'user'`
by the rider's own uid, a coach cancel `'provider'` — neither party can sign the
other's cancellation and bend the outcome.

### What is deliberately not here

No PSP. No card capture, no Stripe, no payouts actually executing. The app
writes and enforces the ledger a processor will one day execute; the seam is
`paymentRef` plus the executed states. Two gaps are named rather than hidden: a
back-dated `cancelledAt` from a hand-rolled client is provable-but-not-honest
until refunds run server-side, and a cash walk-in has no mechanism for FLOW to
collect its 20%.

---

## Security model

The app is the sole reader and writer of its database, so
[firestore.rules](firestore.rules) is the only authority a hand-rolled client
obeys. Two audits were run against it; both are recorded in
[BUGS.md](BUGS.md) (BUG-001…029) and [FINAL_AUDIT_REPORT.md](FINAL_AUDIT_REPORT.md).

What the rules enforce, beyond ordinary ownership:

- **Identity fields are staff-only.** `role`, `status`, `blockedUntil` cannot be
  written by the account they describe, so a rider cannot self-approve as a
  coach or lift their own suspension.
- **The booking state machine.** A write that *moves* `status` out of
  `completed` / `cancelled` / `rejected` is refused. Settlement and
  history-hiding on a delivered booking still land.
- **The money fields.** A rider can never write payment fields; a coach can
  never forge `paid_out` or convert a held escrow booking to cash-paid.
- **Instant Book.** A rider may only create a `confirmed` booking when the
  coach's flag really is on — the rules re-read the coach's profile rather than
  trusting the client.
- **Suspension bites at the API**, not only in the app's routing.
- **`audit_log` is append-only**, so every staff decision stays attributable.

On the client, **App Check (Play Integrity)** attests every Firebase call
([main.dart:64](lib/main.dart#L64)). Debug builds use the debug provider and
print a token to logcat on first run — register it under *App Check → Apps →
Manage debug tokens* before enabling enforcement, or dev builds lose Firestore.

---

## Design language

Derived from the brand logo (`assets/brand/logo.png`):

| Token | Value | Source |
|---|---|---|
| Ink navy | `#020F2B` | logo background |
| Azure | `#1DB0FE` | logo swoosh |
| Azure deep | `#0077C9` | light-theme primary, for AA contrast |

**Both themes are fully designed and the user picks** — System / Light / Dark,
in Profile → Appearance, persisted across launches. Neither is an inversion of
the other, and a contrast suite fails the build if a token reads twice as well
in one brightness as the other. Switching themes cross-fades the *pixels* of the
old frame rather than lerping every `ThemeData` per tick
([theme_swap.dart](lib/core/widgets/theme_swap.dart)).

- **Typography:** Space Grotesk (display) + Inter (text), bundled as variable
  fonts — weights via `FontVariation`, tabular figures so money and timers never
  jitter.
- **Tokens, not literals.** Radii come from
  [radii.dart](lib/core/theme/radii.dart) (pill 8 → sheet 28); durations from
  [motion.dart](lib/core/theme/motion.dart) (fast 150 / base 200 / slow 300 /
  pulse 1100, all on `easeOutCubic`); colours from `context.tones`, never raw
  pigment. Spacing sits on a 4pt grid.
- **Route transitions are deliberately outside the motion scale** (gate fade
  260ms, push 300/240) — they are tuned to travel with a finger, not to a token.
- Every async surface goes through `AsyncView`, whose `onRetry` is *required*,
  so an error dead end cannot ship. Every tappable is ≥48×48 with a semantic
  label.

The conventions are written down in [CLAUDE.md](CLAUDE.md) and enforced by the
guard-rail suites listed under [Testing](#testing).

---

## Project layout

```
lib/
  core/        theme tokens, constants, slot/date math, tolerant Firestore
               readers, member/session ref derivation, and the shared widget
               library (FlowCard, AsyncView, FlowTopBar, thread, ticket…)
  data/        models (field-by-field per blueprint §5) + repositories —
               every read and write, with transactional safari seats,
               pre-write slot re-checks and terminal-state guards
  providers/   the Riverpod graph — session gate machine, explore filters,
               booking buckets, 3-stream day availability, the money ledger
  services/    push (FCM token + tap routing), image picking, conditions
  features/    admin, auth, booking, chat, command_center, explore, gates,
               media, notifications, onboarding, profile, sessions, shell,
               splash, support
  dev/         the seeder — a second entry point, not in main.dart's graph
functions/     TypeScript Cloud Functions (push fan-out, two nightly jobs)
test/          813 widget/unit tests
test_rules/    389 tests against the real rules on the Firestore emulator
```

**Zones, not folders.** A Flutter screen holds its own controller, so
[CLAUDE.md](CLAUDE.md) classifies code by *layer* — business rules are frozen,
flow and state need approval, presentation is free — and
[REFACTOR_PLAN.md](REFACTOR_PLAN.md) §B maps that onto individual line ranges.

---

## Navigation and gates

A six-branch tab shell shows **four destinations per role**:

- **Rider:** Discover · Sessions · Ticket · Profile
- **Coach:** Dashboard · Calendar · Earnings · Profile

Branch state survives switching, tapping the active tab pops it to root, and
Android back returns to the home tab before it offers to leave the app. Branch
paths are single-sourced in `ShellBranch.paths` so the router and the bar cannot
drift apart.

Everything else is a pushed route: coach and station profiles, booking, chat,
inbox, notifications, support and its ticket threads, the admin console, and
profile editing.

**The gate table** is a pure function, `gateRedirect()`
([router.dart:97](lib/router.dart#L97)), pinned row by row in
`test/gate_redirect_test.dart` — it is security-relevant, so it is unit-testable
in one place rather than buried in a router closure:

| Stage | Where the user is allowed to be |
|---|---|
| `loading` | the splash |
| `signedOut` | `/auth` and its three children |
| `chooseRole` | onboarding |
| `awaitingApproval` | `/pending` |
| `blocked` | `/blocked` (with an appeals thread) |
| `rejected` | `/rejected`, **all of `/support`**, and the reapply form |
| `staff` | the console, plus the profiles and threads it opens |
| `ready` | the app |

---

## Conditions forecast

The booking day strip shows each day's max wind in knots, and a summary row
explains the selected day — `Good · 17kt NW · gusts 32` — plus air and sea
temperature. Riders were otherwise leaving the app to check a forecast, which is
a step in someone else's flow.

Source is **Open-Meteo** ([wind_service.dart](lib/services/wind_service.dart)):
the forecast API for wind and air, and the marine API for sea-surface
temperature. These are the app's only HTTP calls, and the cost is contained — no
API key or account on the non-commercial tier, no new dependency (`dart:io`'s
`HttpClient` is enough), a 30-minute cache, and **silent failure**: every error
path returns an empty forecast and the UI renders nothing where wind would have
been. Each strand degrades independently, so a missing sea temperature does not
take the wind with it.

Wind is requested in knots so nothing downstream converts — and nothing can
convert twice. Daily buckets are pinned to `Africa/Cairo` so a Thursday forecast
cannot land on Wednesday's tile.

Two limits worth knowing: the free tier caps at 16 days while the strip runs to
21, so the last days carry no wind rather than a guess; and spot coordinates are
approximate launch areas, well inside a forecast whose native resolution is
kilometres. **There is deliberately no "gusty" badge** — thresholded at +8kt it
lit on all sixteen sample days at El Gouna, so the gust number is shown and the
reader draws their own conclusion.

---

## Backend (`functions/`)

Three functions — the parts of FLOW that cannot live in the client. They
compose, and none knows about the others: the nightly jobs write notification
documents, and the push trigger delivers them.

| Function | Trigger | Does |
|---|---|---|
| `onNewNotification` | `notifications/{id}` created | Sends the FCM push |
| `sendSessionReminders` | Daily 18:00 Africa/Cairo | "Session tomorrow" for tomorrow's confirmed bookings |
| `sendCancelWindowReminders` | Daily 18:00 Africa/Cairo | "Free cancellation ends tomorrow" for held bookings |

> **None of them is deployed.** Cloud Functions are disabled on `wlf-flow`, so
> **no push notification is delivered today**. In-app notifications are written
> and read normally; only delivery is inert, and every stored FCM token is
> currently dead weight.

```bash
cd functions && npm install     # once
npm run build                   # tsc → lib/
npm run deploy                  # firebase deploy --only functions
npm run logs
```

TypeScript, Firebase Functions **v2**, Node 22, capped at `maxInstances: 10` —
a cap, not a target: a bad loop writing notifications in a tight cycle bills
before anyone notices.

**Why the jobs run nightly** rather than "24 hours before each start": bookings
store a local `YYYY-MM-DD` plus `HH:mm` with no offset, so per-booking instant
maths on a UTC server means hard-coding Egypt's offset — which is +2 except when
it is +3. Cloud Scheduler owns the timezone instead, and the only arithmetic
left is "add one calendar day".

**What the push trigger skips**, each for a reason:

| Condition | Why |
|---|---|
| `seeded: true` | Seeded history is backdated. Pushing "your session starts at 10:00" for a lesson 30 hours in the past is worse than silence |
| `read: true` at creation | Written as history, not as news |
| `pushSentAt` already set | Cloud Functions are at-least-once; this stamp makes a redelivery send at most one push |
| No recipient or profile | Logged, stamped `pushSkipped`, dropped rather than thrown |
| No `fcmToken` | Normal — permission declined, or signed out |

**Dead tokens are deleted, not retried** — a token dies when the app is
uninstalled, and nothing makes it deliverable again. **Retries are bounded**: a
permanent project-level error would otherwise be redelivered for seven days, so
the handler gives up on any event older than 10 minutes.

Two deployment notes: the **region** is deliberately unset (deploys to
`us-central1`) — if deploy fails with a location mismatch, set it in
`setGlobalOptions`, and only there. And `AndroidManifest.xml` declares no
notification icon, so Android falls back to the launcher icon and may render a
white square; fixing that needs a monochrome silhouette drawable, which is a
design asset rather than a code change.

**Multi-device is out of scope** — the schema stores one `fcmToken` per user, so
signing in on a second device takes push with it.

---

## Running it

The Firebase wiring is already in the repo and points at `wlf-flow`. A fresh
clone builds and runs as-is:

```bash
flutter pub get
flutter run                              # Android device or emulator
flutter build apk --split-per-abi        # release: ~30 MB per ABI, not 77
```

Android is the only platform checked in — there is no `ios/` or `web/`
directory. Always ship the split APKs; the fat one carries three CPU
architectures and is two and a half times the size for no benefit.

**The startup guard.** `main()` short-circuits to a *Setup required* screen when
`FlowFirebase.isConfigured` is false — Firebase accepts a bogus API key at init
and only rejects it on the first real call, which is how a build problem
surfaces to a user as "Something went wrong" under a registration form. The
matching tests in `test/auth_test.dart` assert the real config is present and
that the package name still matches `google-services.json`. **Do not delete
them** — they catch `firebase_options.dart` being regenerated empty or against
the wrong project.

---

## Standing up a fresh Firebase project

Steps 1–3 are not optional; the app cannot function without them.

**1. Create the project and configure the app**

```bash
flutterfire configure --project=<your-new-project-id>
```

Register the Android package **`com.wlftech.flow`** when prompted. This writes
`lib/firebase_options.dart` and `android/app/google-services.json`. Then enable
**Authentication → Sign-in method → Email/Password**, or every registration
fails with `configuration-not-found`.

**2. Deploy the rules** — both files ship in this repo:

```bash
firebase deploy --only firestore:rules,storage
```

A new project starts either deny-all or in an expiring test mode, and neither is
correct. Redeploy after *any* change to `firestore.rules`: the file in the repo
is inert until it is pushed, and the gap between "the app won't let you" and
"the database won't let you" is exactly where the audits found their worst bugs.

**3. Make yourself an admin — nothing works until you do**

With an empty database nobody is staff, and the app has no way to promote
anyone (deliberately — that is the rule stopping a rider promoting themselves).
The first admin is made by hand, once:

1. Sign up in the app as a normal user.
2. In the console open `users/{your-uid}` and set `role` to `admin`.
3. Reopen the app — the profile is streamed, so the console appears without a
   restart.

Skip this and no coach can ever be approved: Explore only lists
`role == 'business' && status == 'active'`, so the marketplace stays empty
forever no matter how many coaches sign up.

**4. Register the app under App Check** (*Build → App Check → Apps*) with Play
Integrity, and add your debug token before switching enforcement on. Enforcing
first and registering second locks every installed copy out of Firestore.

**5. Deploy the functions** if you want push delivery — see
[Backend](#backend-functions). Also re-add the debug and release **SHA
fingerprints** under the Android app, or Firebase rejects it with
`app-not-authorized`.

---

## Test data

A second entry point seeds a populated marketplace:

```bash
flutter run -t lib/dev/seed_app.dart
```

**25 accounts** — 9 riders, 13 coaches and operators, 2 left pending, 1 admin —
all sharing the password **`FlowTest!2026`** at `@flowtest.dev`, plus the
activity that makes the screens worth looking at: bookings in every status,
reviews spread 3.0–5.0, conversations with unread counts, blocked hours, time
off, station rentals, beach passes, and four expeditions including one sold out.

**The cast is built to stress the UI, not to look plausible.** Every spot has at
least one bookable business, so no filter comes back empty. Deliberate layout
cases: a 30-character name, names in Arabic script (RTL, and avatar initials for
non-Latin text), a two-character name, an empty bio, a bio near the 240 ceiling,
six languages against one, and an unrated coach so the 5.0 default is visible.
All three operator kinds exist, plus a second station with no services so the
station tabs can be seen empty. Marta (`rider3@`) has nothing at all: she is the
first-run experience.

A test asserts the cast holds its shape — unique emails, real spots, every spot
covered, all three operator kinds, the stress cases present, and every seeded
name and bio being a value the app's own validators would accept. That last one
immediately caught a "max length" bio that was 10 characters over the limit.

Everything carries `seeded: true` so the console can find and delete it all, and
every document has a fixed id written only if absent, so re-running never
duplicates. **The seeder obeys the rules like any other client**, which leaves
one manual step: promote the admin as above, then tap **"Approve all coaches"**
— it signs in *as* that admin and takes the same path the console does.

---

## Testing

Two suites, and they answer different questions.

| Suite | Runs against | Count |
|---|---|---|
| `flutter test` | `fake_cloud_firestore` — **rules are not evaluated** | **813** |
| `npm test` in `test_rules/` | Firestore emulator — **the real `firestore.rules`** | **389** |

`test/` covers the load-bearing logic (slot maths, lead time, bucketing,
tolerant parsing, vacation ranges, the commission, the cancellation policy, the
gate table) and renders every screen. `test_rules/` holds every "X cannot do Y"
claim in this README — they are the only place authorization is really proven.
There is also an `integration_test/` walkthrough with frame percentiles, driven
on a real device.

Nine suites exist to catch a specific class of mistake, and each explains itself
in its header — read it before editing:

| Suite | Catches |
|---|---|
| `component_render_test` | Every shared component, both themes, text scale 0.9 and 1.3 — fails on overflow |
| `text_contrast_test` | WCAG AA over the *real render*, including text on a tint on a card |
| `theme_contrast_test` | A token that reads twice as well in one brightness as the other |
| `screen_overlap_test` | Text painted over text — born from a defect 494 passing tests walked past |
| `tap_target_test` | Flutter's own iOS/Android tap-target and labelled-tappable guidelines |
| `image_decode_size_test` | An image decoded at source size instead of display size |
| `wave_backdrop_test` | The backdrop moving when the keyboard opens |
| `auth_layout_test` | The auth CTA going unreachable with the keyboard up at 1.3x |
| `onboarding_rebuild_test` | Inline validation going stale after the first submit |

**No existing test was ever modified to accommodate a fix.**

---

## Deliberate behaviours

Kept on purpose. Each looks like a bug from one angle and is a decision from
another:

- **Unrated coaches display 5.0** (`RatingSummary.none`) — a marketplace
  behaviour from the blueprint, not a computed average.
- **`unknown` payment status is not `unpaid`.** A lesson from last month whose
  cash changed hands on the beach is not money owing; folding the two together
  would open every coach's ledger on a debt that does not exist.
- **A delta against a week that earned nothing is blank, not +100%** — a
  percentage change from zero is undefined, and "+100%" on a first week of
  trading is a flattering lie.
- **Rate and training spot are not editable in-app** after onboarding; changing
  them is a support conversation.
- **The travel buffer** is written on every booking and enforced against the
  end of the day, but is still not subtracted from *other* riders' availability.
- **Sorting is client-side**, so no composite indexes are required.
- **A booking's hours must be one unbroken run** — enforced in the grid *and*
  re-enforced at the write, because the availability document behind it is a
  single range.
- **The QR ticket stays light in dark mode**, because scanners read it.

---

## Known limits

Named rather than hidden:

- **Push is not delivered** — the functions are written and undeployed.
- **No PSP.** No card is charged and no payout is executed; the ledger records
  what a processor will settle.
- **A back-dated `cancelledAt`** from a hand-rolled client is provable but not
  honest until refunds run server-side. App Check narrows the door; a server
  clock closes it.
- **A cash walk-in has no mechanism** for FLOW to collect its 20%.
- **No test runs the real Dart repositories against the real rules.**
  `test_rules/` transcribes the repositories' payloads — close, not identical.
  Closing this needs an `integration_test` pointed at the emulator.
- **Multi-device push** is out of scope (one token per user).
- **Deep-linking `/book/:id`** requires `extra` and would throw without it. It is
  unreachable today — the manifest declares no deep-link intent filters — and is
  recorded as a constraint on any future deep-linking work.

---

## Document map

| Document | What it is |
|---|---|
| [CLAUDE.md](CLAUDE.md) | The working rules: frozen zones, conventions, which tests exist to catch what |
| [APP_LOGIC_BLUEPRINT.md](APP_LOGIC_BLUEPRINT.md) | The implementation-independent spec every rule descends from |
| [FLOW_REDESIGN.md](FLOW_REDESIGN.md) | Every flow/state change proposed, approved and implemented — P1–P15 |
| [REFACTOR_PLAN.md](REFACTOR_PLAN.md) | The UI/UX refactor: file classification, line-range zone map, phase record |
| [BUGS.md](BUGS.md) | Every defect found, fixed or deliberately not — BUG-001…029 |
| [AUDIT_PLAN.md](AUDIT_PLAN.md) · [FINAL_AUDIT_REPORT.md](FINAL_AUDIT_REPORT.md) | The full-application audit: protocol, findings, residual risk |
| [COVERAGE.md](COVERAGE.md) | Blueprint section → test, including the rows that say "not covered" |

---

## Identity migration

The app ships as **`com.wlftech.flow`**, migrated from `com.kiteflow.app`. An
Android application id is the app's primary key on both Google Play and
Firebase, so this was not a cosmetic rename. It is **already done**; this record
exists for anyone pointing the app at another project.

| Consequence | What it means |
|---|---|
| **New Play listing** | Play treats a changed application id as a different app. Old installs cannot update to it; ratings and install counts do not carry over |
| **New Firebase Android app** | A Firebase Android app is bound to one package name — that means a new `appId` and a matching `google-services.json` |
| **FCM re-registration** | Push tokens are per-package; devices re-register on first launch |
| **SHA fingerprints** | Re-add debug and release fingerprints, or Firebase returns `app-not-authorized` |

Firestore data, Storage objects and Auth accounts are unaffected — they belong
to the project, not the package.
