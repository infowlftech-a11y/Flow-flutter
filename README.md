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

## Before you run — required

**The app will not start until Firebase is configured.** `lib/firebase_options.dart`
ships the live project ids for `go-kite-ccc33` but a **placeholder apiKey**, and
`android/app/google-services.json` is not in the repo. Until both are supplied,
`main()` short-circuits to a "Setup required" screen rather than booting into an
app where every call fails with `API_KEY_INVALID`.

1. Copy **`google-services.json`** from the FLOW 2.6 repo into `android/app/`.
   The Gradle plugin picks it up automatically once present (it is applied
   conditionally, so builds still succeed without it — minus push).
2. Supply the **API key**: run `flutterfire configure --project=go-kite-ccc33`
   to regenerate `firebase_options.dart`, or paste that file's `current_key`
   into the `apiKey` field by hand.
3. Delete the guard test in `test/auth_test.dart` ("startup configuration
   guard") — it asserts the placeholder is still present and is *designed* to
   fail once you configure the app properly.
4. `flutter pub get`, then `flutter run` on an Android device.

## Identity migration

The app ships as **`com.wlftech.flow`**, migrated from `com.kiteflow.app`.
An Android application id is the app's primary key on both Google Play and
Firebase, so this is not a cosmetic rename:

| Consequence | What it means |
|---|---|
| **New Play listing** | Play treats a changed application id as a different app. Existing `com.kiteflow.app` installs cannot update to it — they keep running the old build. Ratings, reviews and install counts do not carry over. |
| **New Firebase Android app** | A Firebase Android app is bound to one package name. `com.wlftech.flow` must be registered in the `go-kite-ccc33` console; that yields a new `appId` and a `google-services.json` whose client matches. |
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
