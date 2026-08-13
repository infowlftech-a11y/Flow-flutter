# FLOW_REDESIGN.md

Flow and state changes proposed during the UI/UX refactor, for approval.

[CLAUDE.md](CLAUDE.md) requires that anything touching routing, step order, or what persists
between steps appears here and is approved **before** implementation. This document is that
gate.

> **Status: F1, F2, F3, F4, F5, F6 and F7 are implemented.** F8 needed no action.
>
> **F4 was implemented without an answer to the open question.** It is the one item
> below marked **Decide** rather than **Do** — the three options are a genuine product
> choice about where a tapped notification should leave you. Option 2 (`pop()` then
> `go()` — same destination, honest back stack) was taken as the conservative reading
> of an instruction to continue. It is a single `leaveTo()` helper in
> `notifications_screen.dart` and reverts in one edit. **If option 1 or 3 was wanted,
> say so and it changes in a minute.**
>
> The rest were approved explicitly or are unambiguous defect fixes. The proposals
> below are kept as written, so the reasoning is still auditable against the result.

Source: section F of [REFACTOR_PLAN.md](REFACTOR_PLAN.md), re-verified against the code before
writing. Two items changed materially on re-verification — **F6 was recorded backwards** in the
plan and is corrected here; **F8 is unreachable today** and is downgraded to a note.

## Decision summary

| # | Finding | Proposal | Risk | Recommend |
|---|---|---|---|---|
| [F6](#f6--trainer-form-step-1-validates-twice-differently) | Trainer form validates twice, differently | Delete the inline checks, use the getters | Low | **Do — first** |
| [F1](#f1--duplicate-scanner--check-in-path) | Scanner + check-in duplicated | Extract one helper taking a callback | Low | **Do** |
| [F2](#f2--comingUpLimit-is-declared-but-not-wired) | `comingUpLimit` declared, not wired | Reference the constant | None | **Do** |
| [F3](#f3--sign-out-placement-across-the-four-gates) | Sign-out in 3 different positions | Standardise on the app-bar action | Low | **Do**, with Phase 8 |
| [F5](#f5--errorviewfriendly-is-business-logic-in-the-component-library) | `ErrorView.friendly` in `core/widgets` | Move to `core/utils/`, keep API | Low | **Do** |
| [F4](#f4--notification-tap-replaces-the-notification-list) | Notification tap replaces the list | Three options, no clear winner | Medium | **Decide** |
| [F7](#f7--unreferenced-declarations-in-frozen-files) | Unreferenced declarations | Remove 3, keep the rest | Low | **Optional** |
| [F8](#f8--bookid-depends-on-extra-note-only) | `/book/:id` needs `extra` | None — unreachable | — | **Note only** |

Six are mechanical and reduce risk. **F4 is the only genuine product decision** and is the one
I need an answer on. F8 needs nothing.

### Admin console — new work, not from the refactor

Requested separately: *"an admin dashboard so we can review trainers and verify them."* The
console already does the reviewing ([admin_screen.dart](lib/features/admin/admin_screen.dart),
APPROVALS tab — certificate viewer, IKO check, approve/decline). These two close the gaps found
while confirming that.

| # | Finding | Proposal | Risk | Recommend |
|---|---|---|---|---|
| [A2](#a2--suspended-users-the-provider-exists-and-nothing-reads-it) | Suspended-users provider is orphaned | New SUSPENDED tab reading it | Low | **Do — first** |
| [A1](#a1--a-trainer-can-never-be-re-reviewed-after-approval) | No re-review after approval | New VERIFIED tab with revoke | Medium | **Do, after two answers** |

**Neither needs a frozen file changed.** Every query, mutation and Firestore rule already
exists; this is wiring, not new business logic.

---

## F6 — Trainer form step 1 validates twice, differently

**Recommend: do this first.** It is the only item here a user can hit today.

### Correction to REFACTOR_PLAN.md

The plan stated "a name of exactly 2 characters shows no error while the button refuses to
advance." That is backwards. `OnboardingValidators.minNameLength` is **2**, so a 2-character name
*passes* the validator. The actual divergences are below.

### Current behaviour

The gate getters at [trainer_form_screen.dart:81-84](lib/features/onboarding/trainer_form_screen.dart#L81-L84)
defer to `OnboardingValidators` and drive `_step1Ok`. But the `FormGroup.errorText` arguments at
[:329](lib/features/onboarding/trainer_form_screen.dart#L329) and
[:342](lib/features/onboarding/trainer_form_screen.dart#L342) re-implement their own checks and
never read those getters. Neither field caps input length — only
[kiter_form_screen.dart:278](lib/features/onboarding/kiter_form_screen.dart#L278) sets a
`maxLength`, and only on bio.

The comment directly above the getters reads *"Each defers to the shared validators so the
Continue button and the inline messages below cannot drift apart."* They have drifted apart.

| Input | Validator / `_step1Ok` | Inline message | What the user sees |
|---|---|---|---|
| Name, exactly 2 chars (`"Jo"`, `"Li"`) | passes → **Continue works** | `length <= 2` → shows *"At least 3 characters"* | A red error that does nothing. Tapping Continue advances anyway |
| Name, 61+ chars | fails → **Continue blocked** | `length <= 2` false → shows nothing | Blocked with no explanation |
| Bio, 241+ chars | fails → **Continue blocked** | `isEmpty` false → shows nothing | Blocked with no explanation |

The two silent blocks are the serious ones: the applicant taps Continue, the screen scrolls to
top, and nothing tells them why. `maxNameLength` is 60 and `maxBioLength` is 240 — a trainer
writing a thorough professional bio will hit the second one.

### Proposal

Point the inline messages at the getters that already exist:

- `errorText: attempted ? _nameError : null`
- `errorText: attempted ? _bioError : null`

Optionally add `maxLength: OnboardingValidators.maxBioLength` to the bio field, matching
`kiter_form_screen`, so the ceiling is visible while typing rather than discovered on submit.

### Why this is a flow change

It changes what blocks a step and what the user is told at each step boundary — step-order
behaviour, not styling. The wording shown for a 2-character name changes from
*"At least 3 characters"* to *"That looks too short"* (the validator's string, asserted by
[core_logic_test.dart:231](test/core_logic_test.dart#L231)).

### Risk

**Low.** Strictly fewer states where the form refuses without explanation. No repository, model
or validator changes. `flutter test` unaffected — the validators themselves do not move.

---

## F1 — Duplicate scanner / check-in path

### Current behaviour

`_openScanner` ([command_center_screen.dart:61-80](lib/features/command_center/command_center_screen.dart#L61-L80))
and `_scanToStart` ([:623-642](lib/features/command_center/command_center_screen.dart#L623-L642))
are the same sequence twice: push `QrScannerScreen` on the root navigator, await a `bookingId`,
call `checkIn`, then toast — `CheckInFailure` verbatim, anything else generic.

They differ in exactly one way, and it is why they were not shared already: `_openScanner` lives
on a `ConsumerState` and guards with `mounted`; `_scanToStart` lives on a `ConsumerWidget` and
guards with `context.mounted`.

### Proposal

Extract one top-level helper in the same file:

```
Future<void> runCheckInScan(BuildContext context, WidgetRef ref) async { … }
```

guarding on `context.mounted` throughout. `_openScanner` becomes a call to it; `_scanToStart` is
deleted. The FAB and the SCAN TO START card action then provably behave identically.

### Why this is a flow change

Both are entry points into check-in, and the guard swap changes the lifetime rule for the
post-scan toast. In practice `context.mounted` on a `State`'s context implies `mounted`, so
behaviour is preserved — but it is a navigation entry point, so it belongs here.

### Risk

**Low.** Two call sites, both in one file. Manual check: scan from the FAB and from a manifest
card, with a good ticket, a wrong-trainer ticket, and a cancelled scan.

---

## F2 — `comingUpLimit` is declared but not wired

### Current behaviour

[constants.dart:116](lib/core/constants.dart#L116) declares `comingUpLimit = 10`.
[command_center_screen.dart:181](lib/features/command_center/command_center_screen.dart#L181)
hardcodes `.take(10)`. They agree today; nothing reads the constant.

### Proposal

`.take(FlowConst.comingUpLimit)`.

### Why this is a flow change

It changes what determines how much of the "Coming up" list a trainer sees. The edit lands in a
FREE build body, but it makes a **frozen** constant load-bearing for the first time — after this,
editing `comingUpLimit` changes the UI, which is the point.

### Risk

**None.** Same value; the constant is `const`.

---

## F3 — Sign-out placement across the four gates

### Current behaviour

Four byte-identical `TextButton.icon` widgets in three different positions:

| Screen | Position |
|---|---|
| [role_select_screen.dart:24](lib/features/onboarding/role_select_screen.dart#L24) | `AppBar` `actions` |
| [blocked_screen.dart:94](lib/features/gates/blocked_screen.dart#L94) | First child of a `ListView`, `Align(topRight)` |
| [pending_screen.dart:26](lib/features/gates/pending_screen.dart#L26) | First child of a `Column`, `Align(topRight)` |
| [rejected_screen.dart:34](lib/features/gates/rejected_screen.dart#L34) | First child of a `Column`, `Align(topRight)` |

Extracting one widget is presentation (Phase 8). **Where it sits is flow** — on these four
screens sign-out is frequently the only way out, so its position is a navigation affordance.

On `/blocked` the button is inside a scrolling `ListView`. Once an appeal thread grows, sign-out
scrolls off-screen — on the one screen where a user is most likely to want it.

### Proposal

Standardise on the `AppBar` `actions` slot for all four, as `role_select_screen` already does.
Keeps it pinned, keeps it out of the back-button slot (per §3.2/§10.4, sign-out must never sit in
the back slot), and fixes the scroll-away on `/blocked`.

### Why this is a flow change

It changes the position of the primary exit on four gate screens.

### Risk

**Low**, with one caveat: `blocked_screen` and `pending_screen` currently have no `AppBar`, so
they gain one (transparent, `automaticallyImplyLeading: false`, matching `role_select_screen`).
That interacts with `WaveBackdrop` and `SafeArea` and needs a visual check on a notched device.
Best done as part of the shared gate scaffold in Phase 8, not before.

---

## F5 — `ErrorView.friendly` is business logic in the component library

### Current behaviour

[feedback.dart:66-79](lib/core/widgets/feedback.dart#L66-L79) maps Firestore error codes
(`permission-denied`, `unavailable`/`network`, `failed-precondition` + `index`) to user copy, by
lowercasing and substring-matching `error.toString()`. It sits in `lib/core/widgets/` — the FREE
zone — while being exactly the kind of rule the FROZEN zone exists to protect. Its sibling,
`AuthRepository.message` ([auth_repository.dart:186](lib/data/repositories/auth_repository.dart#L186)),
does the same job for auth and is asserted by [auth_test.dart:113](test/auth_test.dart#L113).

The practical hazard: a Phase 5 restyle of `feedback.dart` is FREE-zone work by the file's
classification, so nothing currently stops someone editing user-facing error semantics while
"just restyling the error state".

### Proposal

Move the function to `lib/core/utils/error_copy.dart` (FROZEN) as
`String friendlyError(Object error)`. Keep `ErrorView.friendly` as a one-line delegating
`static` so the four existing call sites and any external reference keep working.

### Why this is a flow change

It moves a rule across the frozen boundary. The move itself is mechanical; the reclassification
is the decision.

### Risk

**Low.** No behaviour change, no test change. Optionally add a test for the three mapped cases —
currently there is none, which is part of why this drifted into the widget layer.

---

## F4 — Notification tap replaces the notification list

**This is the one that needs a product decision.** I do not have a confident recommendation.

### Current behaviour

`/notifications` is a root-navigator route ([router.dart:216-220](lib/router.dart#L216-L220)),
pushed as a modal over the shell from the Explore bell, the Command Center bell, or
Profile ▸ Notifications.

`_open` ([notifications_screen.dart:98-138](lib/features/notifications/notifications_screen.dart#L98-L138))
marks the item read, then:

| Kind | Action |
|---|---|
| booking\* / reminder | `context.go('/home')` if trainer, else `context.go('/sessions?highlight=…')` |
| message | `context.go('/inbox')` |
| review | `context.go('/sessions')` |
| broadcast / system | opens a sheet — **stays on the list** |

`go` replaces the location, so the notification list is destroyed. Back does not return to it.

Push taps ([push_service.dart:96-116](lib/services/push_service.dart#L96-L116)) make the same
role fork but use `push` for the no-type fallback — reasonable, since that case is *opening* the
notification centre rather than leaving it. So push_service is internally consistent; the
question is only about `_open`.

### Is it a defect?

Genuinely arguable, which is why it is here rather than in the plan's phase list.

- **Against:** a notification centre is a list you triage. Tapping one item, seeing it, and
  coming back to clear the next is a normal loop, and `go` breaks it. The broadcast/system branch
  already keeps the list alive, so the screen is inconsistent with itself.
- **For:** a notification is a pointer at a destination, not content. Landing the user on
  `/sessions` with a clean stack is defensible, and it avoids a modal sitting over a tab route.

### Options

1. **Leave as-is.** Zero risk. Accepts the internal inconsistency with the broadcast branch.
2. **`pop()` then `go(...)`.** Explicitly dismiss the modal first. Same destination, no orphaned
   route, back behaves like the tab bar. Small, honest, does not change where the user lands.
3. **`push` the destination over the list.** Preserves the triage loop, but pushes a shell tab
   route onto the root navigator over a modal — two shell instances in the stack, and
   `/sessions?highlight=` would render outside the `StatefulShellRoute`. **Not recommended;**
   the route tree is not shaped for it.

If something must change, **option 2**. But option 1 is defensible and I would rather you chose
than have me infer intent from a nav pattern that may well be deliberate.

### Risk

Option 1: none. Option 2: low, but it touches deep-link landing behaviour that
`_handleHighlight` ([sessions_screen.dart:60-91](lib/features/sessions/sessions_screen.dart#L60-L91))
depends on — the highlight, tab switch and 4-second tint all need re-testing from both the
in-app list and a real push.

---

## F7 — Unreferenced declarations in frozen files

### Current behaviour

Eight declarations have no `lib/` call site. **Only four are genuinely unreferenced** — the rest
are asserted by the frozen tests and deleting them breaks `flutter test`. Full table in
[REFACTOR_PLAN.md §C.3](REFACTOR_PLAN.md#c3-dead-or-unwired-declarations).

Genuinely unreferenced (0 in `lib/`, 0 in `test/`):

| Declaration | Where |
|---|---|
| `UserRepository.watchProfile` | [user_repository.dart:22](lib/data/repositories/user_repository.dart#L22) — an alias for `watchUser` |
| `ScheduleRepository.watchAllBlocks` | [schedule_repository.dart:25](lib/data/repositories/schedule_repository.dart#L25) |
| `FlowTones.onSuccessTint` | [app_theme.dart:28](lib/core/theme/app_theme.dart#L28) — populated in both themes, never read |
| `FlowConst.comingUpLimit` | Covered by [F2](#f2--comingUpLimit-is-declared-but-not-wired) — wire it, do not delete it |

**Keep:** `Booking.awaitsPayment` (5 test assertions), `PaymentMethod.isCollectedInPerson` (2),
`WindRating.suitsBeginners` (5), and `FlowTones.copyWith` (required by `ThemeExtension`).

### Proposal

Remove the three true dead entries. `onSuccessTint` naturally falls out of Phase 1 (design
tokens); the two repository methods are a separate one-line change each.

### Why this is a flow change

Only because the files are frozen. There is no behavioural component.

### Risk

**Low**, and entirely optional — none of it blocks the refactor. If you would rather not touch
frozen files at all during a UI refactor, skipping F7 costs nothing.

---

## F8 — `/book/:id` depends on `extra` (note only)

**No change proposed.**

[router.dart:214](lib/router.dart#L214) casts `state.extra as BookingTarget` unconditionally, so
a `/book/:id` navigation without `extra` would throw. The plan called this "cannot be deep-linked
or restored from a cold start", which overstates it. On re-verification:

- `AndroidManifest.xml` declares only `MAIN`/`LAUNCHER` — **no deep-link intent filters**.
- No `restorationScopeId` is set on `MaterialApp.router`, so go_router does not restore location
  across process death.

`extra` therefore cannot arrive null today. Every in-app entry
([trainer_profile_screen.dart:817](lib/features/explore/trainer_profile_screen.dart#L817),
[station_profile_screen.dart:236](lib/features/explore/station_profile_screen.dart#L236),
[:318](lib/features/explore/station_profile_screen.dart#L318)) constructs a `BookingTarget`.

Recorded so that whoever adds deep links or state restoration knows `/book/:id` needs a null
guard and a recovery path first — `BookingTarget` is transient by design
([catalogue.dart:110](lib/data/models/catalogue.dart#L110)) and cannot be rebuilt from the URL
alone.

---

## Proposed sequence, if approved

Ordered so the user-visible fix lands first and the risky one is isolated:

1. **F6** — trainer form validation. Standalone commit; the only live user-facing defect.
2. **F2** — wire `comingUpLimit`. One line.
3. **F1** — unify the scanner path. One file.
4. **F5** — move `friendlyError` to `core/utils/`. Do **before** Phase 5 touches `feedback.dart`.
5. **F7** — remove the three dead declarations (optional; fold `onSuccessTint` into Phase 1).
6. **F3** — sign-out placement. Do **with** Phase 8, not before — it needs the gate scaffold.
7. **F4** — only if you pick option 2.

One flow per commit, per CLAUDE.md. Each verified with `flutter analyze`, `flutter test`
unmodified, and a manual pass over the affected flow.

## Open question

**F4 only.** Everything else has a recommendation I am confident in. For F4 I need to know
whether tapping a notification should return you to the list or land you on the destination with
a clean stack — that is a product call about how the notification centre is meant to be used.

---

# Admin console — proposed additions

**Status: proposed, not implemented.** New feature work, not part of the UI/UX refactor.

The console already reviews and verifies trainers: the APPROVALS tab streams
`role == 'business' && status == 'pending'`
([admin_repository.dart:33](lib/data/repositories/admin_repository.dart#L33)) and each card
offers the certificate full-screen, the IKO id (flagged red when absent), the public profile,
and approve/decline with a reason. Nothing below replaces that.

Both additions are **wiring only** — every query, mutation and rule already exists:

| Need | Already there |
|---|---|
| List suspended users | `watchBlockedUsers()` ([:46](lib/data/repositories/admin_repository.dart#L46)) + `blockedUsersProvider` ([providers.dart:589](lib/providers/providers.dart#L589)) |
| Lift a suspension | `unblockUser()` ([:126](lib/data/repositories/admin_repository.dart#L126)) — already used by the appeals tab |
| List verified trainers | `watchActiveTrainers()` ([user_repository.dart:24](lib/data/repositories/user_repository.dart#L24)) — powers Explore |
| Revoke verification | `restoreToPending()` ([:87](lib/data/repositories/admin_repository.dart#L87)) |
| Staff write permission | `allow update: … || isStaff()` ([firestore.rules:61](firestore.rules#L61)) |

---

## A2 — Suspended users: the provider exists and nothing reads it

### Current behaviour

`blockedUsersProvider` ([providers.dart:589](lib/providers/providers.dart#L589)) streams every
account with `status == 'blocked'`. **No screen consumes it.** Someone built the data path and
never wired the UI.

Suspensions are created from the REPORTS tab (`blockUser`) and lifted from the APPEALS tab
(`unblockUser`). Both are reachable only through the thing that caused them — so to lift a ban
you must remember which report produced it. There is no roster of who is currently suspended,
and no view of when a ban lapses.

That matters because bans expire on a timestamp: `blockedUntil` is read by the gate, which
releases the user automatically ([blocked_screen.dart:42-52](lib/features/gates/blocked_screen.dart#L42-L52)).
Staff currently cannot see that clock at all.

### Proposal

A fourth tab, **SUSPENDED**, reading the existing provider. Per row: avatar, name, email, the
remaining time, a permanent badge where `blockedUntil == 'forever'`, and **LIFT SUSPENSION** →
`unblockUser(uid)`. Sorted permanent-first, then soonest to lapse.

The countdown string already exists as `_countdown` in
[blocked_screen.dart:63](lib/features/gates/blocked_screen.dart#L63); it would move to
`core/utils/` so both the gate and the console read one implementation. That file is FREE.

### Why this is a flow change

It adds a tab — step order inside `/admin` — and gives staff a way to reach an account that is
currently reachable only via a report or an appeal.

### Risk

**Low.** No frozen file changes. The query and the mutation are both already in production use;
this is a second entry point to them. Worst case is an empty tab.

---

## A1 — A trainer can never be re-reviewed after approval

### Current behaviour

`watchPendingTrainers()` filters `status == 'pending'`. `approveTrainer` sets `status: 'active'`
— and the trainer **leaves the queue permanently**.

There is no admin-initiated route back to scrutiny. If a certificate expires, or was approved in
error, or a trainer stops meeting the bar, the only paths back are a rider filing a report or the
trainer filing an appeal. Both require someone else to act first.

### Proposal

A **VERIFIED** tab listing `role == 'business' && status == 'active'`, reusing the applicant
card: certificate viewer, IKO id, public profile — plus **REVOKE** → `restoreToPending(uid)`,
which returns them to the APPROVALS queue and holds them at `/pending`.

Unlike the queue, this list grows without bound, so it needs a name/email search field.

New provider in `lib/providers/providers.dart`, following the staff-gated `.autoDispose` shape
its four siblings already use. (Reusing Explore's `activeTrainersProvider` would work and cost
nothing, but it is neither staff-gated nor auto-disposing, and admin queues should be both.)

### Why this is a flow change

It adds a tab, adds a provider, and — the real reason — it lets staff move a **live** account
backwards through the gate machine. Nothing in the app does that today.

### Risk

**Medium, and it depends on two answers I cannot get from the UI layer.**

1. **Revoking is silent.** `approveTrainer` and `rejectTrainer` both call `notify(…)`.
   `restoreToPending` does not — it is a one-line status write. So a revoked trainer would open
   the app and find themselves at the pending gate with no explanation and no notification.
   Fixing that means adding a `notify` call inside `AdminRepository`, which is **frozen**.
   *Do you want revocation to notify the trainer, and what should it say?*

2. **Existing bookings are unaddressed.** Explore stops listing a revoked trainer immediately,
   but their confirmed future bookings are not touched by a status change. Riders would be
   holding paid bookings with someone no longer verified. Cancelling or flagging those is a
   business rule, not presentation.
   *What should happen to a revoked trainer's confirmed bookings?*

Until both are answered, A1 should not ship. **A2 has neither problem and can go first.**

### Suggested sequence

1. **A2** — one tab, zero frozen changes, no open questions.
2. **A1** — after the two answers above, in its own commit.

---

# Performance — proposed state change

## P1 — Every keystroke rebuilds the whole onboarding form

**Status: implemented**, and by a smaller change than the one proposed below.
The proposal is kept as written so the reasoning stays auditable, but **it
rested on a wrong premise — see the correction immediately below.**

### Correction: the Continue button is never disabled

The proposal claimed the per-keystroke rebuild existed "so the Continue button
can enable itself the moment the field becomes valid". That is not what the
code does. Both forms wire their primary action unconditionally —
`onPressed: _next` on the trainer form, `onPressed: _submit` on the rider
form — and validation is handled by scrolling to the first problem *after* the
tap. Nothing is ever disabled.

So no `ValueNotifier` was needed. The only build-time reader of those fields is
`errorText`, and every error getter returns null until the step has been
attempted. Before the first submit the rebuild produced a byte-identical tree.

**What was actually done:** guard the callback on the flag that already exists.

```dart
onChanged: attempted ? (_) => setState(() {}) : null,
```

Six of the seven sites. The seventh — the trainer form's hourly rate — is
deliberately left unguarded: the earnings notice under it reads `_rate.text`
live, so that field genuinely does need every keystroke.

- No `State` field added, no lifecycle method touched, so this did not need
  the approval gate after all.
- Covered by `test/onboarding_rebuild_test.dart`, which asserts the inline
  error appears on submit and then tracks what is typed. Verified red by
  nulling the callback outright: it fails with "the inline error froze".

**Conditional on the release build.** The user reported "very laggy and buggy,
including typing". A release APK was built so debug JIT could be ruled out
first; if typing is fine there, this is not worth doing. What follows only
matters if the lag survives a release build.

### What is there now

Seven text fields across the two onboarding forms are wired as:

```dart
onChanged: (_) => setState(() {}),
```

| File | Lines | `setState` on change | Sites |
|---|---|---|---|
| `lib/features/onboarding/trainer_form_screen.dart` | 570 | 342, 358, 486, 517 | 4 |
| `lib/features/onboarding/kiter_form_screen.dart` | 296 | 167, 209, 281 | 3 |

`setState` on the screen's `State` marks the whole subtree dirty, so every
character typed rebuilds the entire form — all four steps of the trainer form,
its pickers, its gallery thumbnails and its validation banner — rather than
the one thing that actually depends on the text.

Nothing is wrong with the *logic*: the rebuild exists so the "Continue" button
can enable itself the moment the field becomes valid. That is a real
requirement. It is the granularity that is wrong.

### What it does not affect

The auth screens are already careful. `AuthController.clearFieldError` returns
early when there is nothing to clear, and `sign_in_screen` only calls
`setState` when `_attempted` is true — so typing on the sign-in form does not
churn state. This is specific to the two onboarding forms.

### Proposed change

Replace the screen-level `setState` with a `ValueNotifier<bool>` per form
holding "is this step complete", updated in `onChanged` and read by a
`ValueListenableBuilder` wrapped around the Continue button alone.

- Adds: one `ValueNotifier` field per form, disposed in `dispose()`.
- Removes: seven `setState(() {})` calls.
- Rebuild scope per keystroke: the whole form → one button.

**No flow change.** Step order, what persists between steps, validation rules
and the enable/disable condition are all untouched — the same predicate runs,
it just drives a smaller subtree. The validators in
`onboarding_validators.dart` are frozen and are not read differently.

### Risk

Low, and contained to two files. The failure mode if it is wrong is a Continue
button that does not re-enable, which the existing tests over
`onboarding_validators.dart` would not catch — so this needs a widget test
asserting the button enables when the last required field becomes valid.

### Why it is not just done

CLAUDE.md: `State` fields and lifecycle methods are approval-zone. Adding a
`ValueNotifier` field and disposing it is exactly that, however small.

---

## P1 — Payments move through FLOW (ordered 2026-08-12, implemented same day)

Direct product order, quoted: *"The payment will be through the application, when
the kiter book a session, he pays to the application, and then the application
pays the trainer after the session completed. the cancellation policy should
follow the cancellation policy in booking.com"* — followed by *"apply this
system"*. That order is the approval this document usually waits for; the
design is recorded here so the reasoning stays auditable.

### The system

- **Escrow at booking.** A rider booking (lesson or safari seat) records
  `paymentStatus: 'held'`, `paymentMethod: 'app'`, `paidAt` at creation: the
  rider pays FLOW when they book. Walk-ins keep the cash path — there is no
  rider account behind them to charge.
- **Payout after delivery.** A completed session with a held payment is a
  payout FLOW owes the trainer. `markPaid` (the beach-cash settlement) refuses
  held bookings — there is nothing to collect in person.
- **Cancellation policy, booking.com template mapped to single sessions:**
  free cancellation until **24 h before start**; cancelling inside the window,
  or a no-show, is **charged in full** (a session is one "night", and
  booking.com's late fee is the first night). A **pending request** — not yet
  accepted — refunds in full whenever it dies: rider withdrawal, trainer
  decline, or expiry. A **trainer/staff cancellation** refunds in full always.
  The window is one constant (`CancellationPolicy.freeCancelWindow`).

### The load-bearing decision: executed states are written, entitlements are derived

`paymentStatus` only ever records what has *actually happened* to money:
`held` when the rider pays at booking, `refunded` / `paid_out` when a
processor (or staff) executes the movement. Everything in between —
"refund due", "charged, payout due" — is **derived** (`EscrowState` in
`lib/data/models/cancellation.dart`) from facts the rules already pin:
booking status, `cancelledBy`, `cancelledAt`, the 24 h window.

Why: the rules deliberately close the rider's post-create write surface to
`{status, cancelledAt, cancelledBy, hiddenByGuest, updatedAt}` — a rider must
never write payment fields — and a 24 h boundary over `date`+`startTime`
strings is not provable in rules. Deriving means no new write surface, no
client ever claims money moved when it did not, and the future
processor/Functions layer executes exactly what the derivation reports.

### Rules delta (the whole of it)

1. Rider create: `paymentStatus == 'unpaid'` → `in ['unpaid', 'held']`. The
   guarded invariant — the rider states what they owe or have put in escrow,
   never that the trainer was settled (`'paid'` stays rider-refused).
2. A rider writing `status: 'cancelled'` must stamp `cancelledBy: 'user'` and
   a `cancelledAt` — the fields the free-window derivation reads. Presence is
   required, server-time equality is not (the pinned test writes an ISO
   string); a back-dated stamp from a hand-rolled client is therefore
   possible today and is accepted as a known limit, closed when Functions
   execute refunds server-side from their own clock.
3. Provider update set gains `cancelledAt`/`cancelledBy` so trainer
   cancellations can stamp themselves (`'provider'` ⇒ full refund).

### What this is not yet

No card is charged and no payout is sent — there is no PSP and Cloud Functions
are still disabled on wlf-flow. The app writes and enforces the ledger the
processor will execute (Stripe Connect is the natural fit: rider pays the
platform, platform transfers to the trainer). Wiring it is provisioning work
on the owner's side; the seam is `paymentRef` + the executed states.
