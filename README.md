# Flow 3.0 — Own the Wind

> **Identity:** display name `Flow` · application id `com.wlftech.flow`.
> This **overrides** `APP_LOGIC_BLUEPRINT.md` §12/§15, which froze the id at
> `com.kiteflow.app`. See [Identity migration](#identity-migration) for the
> Firebase and Play consequences — they are not optional.

A ground-up Flutter redesign of the FLOW kitesurfing marketplace for the
Egyptian Red Sea coast. Riders find certified trainers, book hours on the
water and check in on the beach with a QR ticket; trainers run their whole
day from a Command Center.

Built against **`APP_LOGIC_BLUEPRINT.md`** — every rule, data shape,
validation and edge case in that document is preserved (see §15's checklist),
while the UI/UX is entirely new.

## Design language

The theme is derived from the brand logo (`assets/brand/logo.png`):

| Token | Value | Source |
|---|---|---|
| Ink navy | `#020F2B` | logo background |
| Azure | `#1DB0FE` | logo swoosh |
| White | `#FFFFFF` | logo wordmark |

- **Dark theme** is the brand-native look (deep navy surfaces, azure accents);
  light theme uses a cool off-white with a deepened azure (`#0077C9`) for
  AA contrast. Both are fully designed — no inversion tricks.
- **Typography:** Sora (display) + Inter (UI/body), bundled as variable
  fonts — weights via `FontVariation`, tabular numerals for money and timers.
- Motion is functional only (150–320 ms), haptics follow a small vocabulary
  (`lib/core/utils/haptics.dart`), and every async surface goes through
  `AsyncView` — a retry is structurally required, so error dead ends can't
  ship.

## Project layout

```
lib/
  core/        theme, constants, slot/date math, tolerant Firestore readers,
               shared widgets (AsyncView, skeletons, sheets, buttons…)
  data/        models (field-by-field per blueprint §5) + repositories
               (every read/write per §6 — dual-writes, arrayUnion appeals,
               transactional safari seats, pre-write slot re-checks)
  providers/   the Riverpod graph (§7) — session gate machine, explore
               filters, booking buckets, 3-stream day availability
  services/    push (FCM token + tap routing), image picking (1600px/q82)
  features/    auth, onboarding, gates, explore, booking, sessions,
               command_center, chat, notifications, profile, support
```

## Standing up a fresh Firebase project

This app is the **sole reader and writer** of its database — there is no web
client sharing it. Steps 1–3 are not optional; the app cannot function
without them.

**1. Create the project and configure the app**

```bash
flutterfire configure --project=<your-new-project-id>
```

Register the Android package **`com.wlftech.flow`** when prompted. This writes
`lib/firebase_options.dart` and `android/app/google-services.json`. Then enable
**Authentication → Sign-in method → Email/Password** in the console, or every
registration fails with `configuration-not-found`.

**2. Deploy the rules** — shipped in this repo:

```bash
firebase deploy --only firestore:rules,storage
```

A new project starts either deny-all or in an expiring test mode. Neither is
correct: [firestore.rules](firestore.rules) pins the fields that decide *who
someone is* (`role`, `status`, `blockedUntil`) to staff-only writes, so a
rider cannot self-approve as a trainer or lift their own suspension.

**3. Make yourself an admin — nothing works until you do**

With an empty database nobody is staff, and the app has no way to promote
anyone (deliberately — see the rules above). The first admin is created by
hand, once:

1. Sign up in the app as a normal user.
2. In the Firebase console open `users/{your-uid}` and set `role` to `admin`.
3. Reopen the app — the profile is streamed, so **Profile → Admin console**
   appears without a restart.

Skip this and no trainer can ever be approved: Explore only lists
`role == 'business' && status == 'active'`, so the marketplace stays empty
forever no matter how many trainers sign up.

**4. Deploy the `onNewNotification` Cloud Function.** It is not in this repo
— it fires on new `notifications` documents and sends the FCM push. Without
it, in-app notifications work and push does not.

## Before you run

The Firebase wiring is **already in the repo** and points at project
**`wlf-flow`**: `lib/firebase_options.dart` carries live keys and
`android/app/google-services.json` is committed with `package_name`
`com.wlftech.flow`. A fresh clone builds and runs as-is:

```bash
flutter pub get
flutter run          # Android device or emulator
```

Android is the only platform checked in — there is no `ios/` or `web/`
directory, so `flutter run` needs an Android target.

**The guard.** `main()` short-circuits to a "Setup required" screen instead of
booting when `FlowFirebase.isConfigured` is false — Firebase accepts a bogus
API key at init and only rejects it on the first real call, which is how a
build problem ends up surfacing to a user as "Something went wrong" under a
registration form. The matching tests in `test/auth_test.dart` ("startup
configuration guard") assert the *real* config is present and that the package
name still matches `google-services.json`. **Do not delete them** — they are
what catches `firebase_options.dart` being regenerated empty or against the
wrong project.

To point the app at a different Firebase project, re-run
`flutterfire configure --project=<id>` and register the Android package
`com.wlftech.flow`; the guard tests keep passing as long as the result is real.

## Backend (`functions/`)

Two Cloud Functions — the parts of FLOW that cannot live in the client.

| Function | Trigger | Does |
|---|---|---|
| `onNewNotification` | `notifications/{id}` created | Sends the FCM push |
| `sendSessionReminders` | Daily, 18:00 Africa/Cairo | Writes "Session tomorrow" for tomorrow's confirmed bookings |

They compose and neither knows about the other: the reminder job writes
notification documents, and the push trigger delivers them. Until they existed
the push half of §11 was inert — the app wrote a notification document for
every event worth announcing and stored each device's token at
`users/{uid}.fcmToken`, but **nothing read either**, so no push was ever
delivered and every stored token was dead weight.

**Session reminders** finish something that was designed and never built:
`NotificationKind.reminder` was already rendered with an alarm icon and routed
to the right booking, and `Booking.reminderSent` was already read by the model
— but nothing ever wrote either. The job runs once a day rather than "24 hours
before each start" on purpose: bookings store a local `YYYY-MM-DD` plus `HH:mm`
with no offset, so per-booking instant math on a UTC server means hard-coding
Egypt's offset, which is +2 except when it is +3 (DST returned in 2023).
Getting that wrong sends reminders an hour out twice a year in opposite
directions. Cloud Scheduler owns the timezone instead, and the only date
arithmetic left is "add one calendar day". Walk-ins are skipped (no account
behind them, §11.1) and `reminderSent` makes the job safe to re-run.

```bash
cd functions && npm install     # once
npm run build                   # tsc → lib/
npm run deploy                  # firebase deploy --only functions
npm run logs                    # tail this function's logs
```

TypeScript, Firebase Functions **v2**, Node 22 runtime. `firebase.json` runs
the build as a predeploy step, so `firebase deploy` alone is also correct.

**What it does.** Fires on `notifications/{id}`, resolves the recipient as
`data.userId || data.targetUserId` (the contract §12 pins), reads their
`fcmToken`, and sends a push carrying `type` and `bookingId` in its data
payload — which is what lets a tapped push land on the specific booking via
`/sessions?highlight={bookingId}` instead of a bare list.

**What it deliberately skips**, because each is a document that exists for
some reason other than "tell this person something just happened":

| Condition | Why |
|---|---|
| `seeded: true` | Seeded history is backdated. Pushing "your session starts at 10:00" for a lesson placed 30 hours in the past is worse than silence. |
| `read: true` at creation | Written as history, not as news. |
| `pushSentAt` already set | Cloud Functions are at-least-once; this stamp is what makes a redelivery send at most one push. |
| No recipient / no profile | Logged and dropped rather than thrown. |
| No `fcmToken` | Normal — permission declined, or signed out. Stamps `pushSkipped: 'no-token'`; the in-app notification is already written and waiting. |

**Dead tokens are deleted, not retried.** A token dies when the app is
uninstalled or its data cleared, and nothing makes it deliverable again. On
`registration-token-not-registered` (and friends) the field is removed, so
`fcmToken` does not slowly fill with garbage and every later notification
does not pay for a failed send.

**Retries are bounded.** `retry: true` is what makes a transient FCM outage
recoverable, but on its own it is a known way to burn money — the platform
redelivers a permanently-failing event for *seven days*. Permanent
**token** errors are swallowed above; a permanent **project** error (Messaging
API disabled, broken service account) would otherwise throw on every
notification and retry all week. So the handler gives up on any event older
than 10 minutes.

**Two things to know before deploying:**

1. **Region.** Left unset, so it deploys to `us-central1`. A v2 Firestore
   trigger must be in a region compatible with the database's location; if
   deploy fails with a location mismatch, set `region` in `setGlobalOptions`
   (there is a comment at the call site). Guessing costs a failed deploy,
   which is why it is documented rather than assumed.
2. **Notification icon.** `AndroidManifest.xml` declares no
   `default_notification_icon`, so Android falls back to the launcher icon and
   may render it as a white square. Fixing that needs a real monochrome
   silhouette drawable, which is a design asset, not a code change. No channel
   is declared either — that is deliberate: naming a channel the device has
   not created silently suppresses the notification on Android 8+, and FCM's
   own default channel works.

**Multi-device is out of scope.** The schema stores a single `fcmToken` string
per user, so signing in on a second device takes push with it. Changing that
means an array plus matching client and rules work — a schema change, not a
backend one.

## Payments

FLOW takes no money. A rider books, and pays the trainer at the centre. What
changed is that the app now **records** that instead of assuming it.

v2.6 wrote `paymentStatus: 'paid'` on safari bookings — a no-op that nothing
read and nothing could act on. That is worse than an empty field, because a
database that *looks* like it tracks payment invites people to trust it. It
was dropped in 3.0, leaving nothing at all. This puts something honest in its
place, shaped so a real processor drops in without a migration.

Every booking now records what is owed (`amountDue`, `currency`), how it will
be settled (`paymentMethod`), and whether it has been (`paymentStatus`,
`paidAt`, `paymentRef`). See `lib/data/models/payment.dart`.

**Three states matter more than the rest:**

| Status | Means |
|---|---|
| `unknown` | No payment information was ever recorded — every booking written before this existed |
| `unpaid` | Owed |
| `paid` | Settled |

`unknown` is a separate state from `unpaid` on purpose, and it is the whole
reason this rollout is safe. A session from last month whose cash changed
hands on the beach is not money owing. Folding the two together would have
opened every trainer's ledger on a debt that does not exist and put an
"Unpaid" badge on their entire history. `unknown` renders **no pill** and
counts toward **nothing owed**.

`processing`, `failed`, `refunded` and the `card` / `wallet` / `transfer`
methods are modelled but not offered — `PaymentMethod.isAvailable` gates the
UI so the enum can be complete without the app claiming something works. The
asynchronous states exist now because retrofitting them onto a two-state
`paid`/`unpaid` field later is the migration this design is meant to avoid.

**Who can say a booking is paid.** The trainer, and only the trainer — they
are the one who is owed. `firestore.rules` blocks riders from writing
`paymentStatus`, `paidAt`, `paymentRef`, `paymentMethod`, `amountDue`,
`currency` or `totalPrice` on an existing booking, and from *creating* one
already marked paid. A rider who could set their own booking to `paid` could
walk off the beach owing for the lesson with the app agreeing they did not.
Riders can still cancel and hide bookings — the guard is on the money fields,
not the document.

**In the app:** finishing a session asks "did you take the €160?" in the same
sheet, because on a beach that is one decision and two dialogs is one that
gets dismissed unread. Settlement is a *second* write — if it fails the
session is still finished, and the trainer settles it later from the earnings
ledger, which grows a "still to collect" band and a MARK PAID button per row.
Riders see a payment pill on completed sessions only; "Unpaid" on a lesson you
have not had yet is true and useless.

**What is deliberately not here:** no Stripe, no RevenueCat, no card capture.
Who is merchant of record, who holds the float, what happens on a no-show —
those are product and compliance decisions, and guessing at them in code
produces a payment system nobody agreed to. What exists is the seam.
`PaymentMethod.isCollectedInPerson` is the single branch that changes when a
processor arrives.

## Wind forecast

The booking day strip shows the forecast max wind in knots on each day, and a
summary row under it explains the selected day — `Good · 17kt NW · gusts 32`.
Riders were previously choosing between next Tuesday and next Thursday by
leaving the app to check a forecast, which is a step in someone else's flow.

Source is **Open-Meteo**, in `lib/services/wind_service.dart`.

**This is the app's only HTTP call**, and it breaks the invariant §12 states
plainly — "no HTTP APIs, no REST endpoints... every external interaction is a
Firebase SDK call". Deliberate, and the cost is contained:

- **No API key, no account, no billing.** Open-Meteo's non-commercial tier
  needs no credentials, so there is no secret to leak from a client binary —
  which is what would otherwise make a weather API a bad idea here.
- **No new dependency.** `dart:io`'s `HttpClient` is enough; adding
  `package:http` for one GET would not have earned its place.
- **Failure is silent.** Every error path returns an empty forecast and the UI
  renders nothing where wind would have been. Booking works on a dead
  connection exactly as it did before. A stale cached forecast is preferred
  over a blank strip when the beach wifi drops.
- **30-minute cache**, far shorter than the forecast's own resolution.

Wind is requested in knots (`wind_speed_unit=kn`) so nothing downstream
converts — and nothing can convert *twice*. Daily buckets are pinned to
`Africa/Cairo` so a "Thursday" forecast cannot land on Wednesday's tile.

Two limits worth knowing: the free tier caps at **16 days** while the strip
runs to 21, so the last days carry no wind rather than a guess; and
`FlowConst.spotCoordinates` is approximate launch-area coordinates, which is
well inside a forecast whose native resolution is kilometres. A test asserts
every spot has coordinates and that none of them leave the Egyptian Red Sea.

**There is deliberately no "gusty" badge.** There was one, thresholded at
gusts 8kt above sustained. Checked against sixteen real days at El Gouna the
gust delta ranged 11–18 knots — the badge would have been lit every single
day. The gust number is shown instead and the reader draws their own
conclusion.

## Test data

A second entry point seeds a populated marketplace into `wlf-flow`:

```bash
flutter run -t lib/dev/seed_app.dart
```

**25 accounts** — 9 riders, 13 coaches and operators, 2 left pending, 1 admin
— all sharing the password **`FlowTest!2026`** at `@flowtest.dev`, plus the
activity that makes the screens worth looking at: bookings in every status
(pending, confirmed, in progress, completed, cancelled, declined), reviews
with ratings spread 3.0–5.0, conversations with unread counts, read and unread
notifications, blocked hours, time off, station rentals and beach passes, and
four expeditions including one sold out.

**The cast is built to stress the UI, not to look plausible.** All ten spots
have at least one bookable business, so no filter comes back empty. Both ends
of the €60–110 band are occupied. Deliberate layout cases: a 30-character
name, names in Arabic script (RTL, and avatar initials for non-Latin text), a
two-character name, an empty bio, a bio near the 240 ceiling, six languages
against one, and an unrated coach so the 5.0 default is visible. All three
operator kinds exist — solo instructor, station (three-tab profile with
instructors, rentals and beach passes) and safari operator (expeditions only)
— plus a second station with no services, so the station tabs can be seen
empty. Marta (`rider3@`) has nothing at all: she is the first-run experience.

A test asserts the cast holds its shape — unique emails, real spots, every
spot covered, rates in band, all three operator kinds, the stress cases
present, and every seeded name and bio being a value the app's own validators
would accept. That last one immediately caught a "max length" bio that was
actually 10 characters over the limit.

Everything it writes carries `seeded: true`, so the Firestore console can find
and delete it all. Every document has a fixed id and is written only if absent,
so re-running never duplicates and never overwrites.

**It obeys `firestore.rules` like any other client**, which leaves exactly one
step that cannot be automated:

**Promote the admin.** Console → Firestore → `users` → the doc for
`admin@flowtest.dev` → set `role: "admin"`. The rules refuse `role: "admin"`
from every client write — that is the check stopping a rider promoting
themselves, so it stops the seeder too.

Then tap **"Approve all coaches (as admin)"** in the seeder. `allow create`
forces a business account to start `pending` and only staff can change
`status`, so the button signs in *as the admin* and takes the same path the
admin console takes — the rule is respected, not bypassed. It touches only
accounts carrying `seeded: true`, and skips Karim and Greg so the Approvals
queue always has something in it. Approving 13 businesses by hand is the kind
of setup step people skip.

Files: `lib/dev/seed_data.dart` (the cast), `lib/dev/seed_content.dart` (the
activity), `lib/dev/seed_app.dart` (the accounts and the UI). None of it is in
`main.dart`'s import graph, so nothing here is compiled into a normal build.

## Identity migration

The app ships as **`com.wlftech.flow`**, migrated from `com.kiteflow.app`.
An Android application id is the app's primary key on both Google Play and
Firebase, so this is not a cosmetic rename. The migration is **already done**
in this repo — the section below records what it cost, and what to redo if the
app is ever pointed at another project:

| Consequence | What it means |
|---|---|
| **New Play listing** | Play treats a changed application id as a different app. Existing `com.kiteflow.app` installs cannot update to it — they keep running the old build. Ratings, reviews and install counts do not carry over. |
| **New Firebase Android app** | A Firebase Android app is bound to one package name. `com.wlftech.flow` must be registered in the `wlf-flow` console; that yields a new `appId` and a `google-services.json` whose client matches. |
| **FCM re-registration** | Push tokens are per-package. Tokens issued to the old package are dead; devices re-register on first launch of the new one. |
| **SHA fingerprints** | Re-add the debug and release signing certificate fingerprints under the new Android app, or Firebase rejects it with `app-not-authorized`. |

Firestore data, Storage objects and Auth accounts are **unaffected** — they
belong to the project, not the package.

Until the new registration exists, the Google Services Gradle plugin fails
with *"No matching client found for package name 'com.wlftech.flow'"*. The
plugin is applied conditionally, so builds without `google-services.json`
still succeed (without push).

Email/password sign-in must also be enabled under **Firebase console →
Authentication → Sign-in method**; if it isn't, registration fails with
`configuration-not-found`, which the app now reports in those words.

`flutter analyze` is clean; `flutter test` covers the load-bearing logic
(slot math, lead-time rule, bucketing, tolerant parsing, vacation ranges).

## Deliberate quirks preserved (blueprint §14)

- Unrated trainers display **5.0** (`RatingSummary.none`).
- The travel buffer is **stored but not enforced** on availability.
- `instantBooking` is parsed but never used — every booking starts `pending`.
- Rate & training spot are not editable in-app after onboarding.
- Collection names, dual field names (`time`/`startTime`, `price`/`totalPrice`,
  `type`/`bookingType`), and `targetUserId`+`userId` on notifications all
  match the shared web-client database exactly.
- Sorting stays client-side — no composite indexes required.

## Enhancements over v2.6 (allowed by the blueprint)

- **Push taps deep-link to the exact booking** (`/sessions?highlight=…`) —
  closing the gap called out in §11.3.
- Trainers can never land on the rider Sessions branch — the router
  redirects them home (§14.3 asked for this).
- Mark-all-read has an UNDO; approve/decline flows are busy-guarded with
  optimistic toasts; the booking grid prunes a selected hour live if someone
  else takes it, with a toast explaining why.
