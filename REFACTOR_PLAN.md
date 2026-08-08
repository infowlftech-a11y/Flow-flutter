# REFACTOR_PLAN.md

Classification map for the UI/UX refactor declared in [CLAUDE.md](CLAUDE.md).

**This document changes no code.** It exists because CLAUDE.md's zone paths
(`/src/lib`, `/src/api`, `/src/components`) describe a JS/TS tree that does not exist —
FLOW is a Flutter app: **82 Dart files, ~21,000 lines under [lib/](lib/)**, plus 3 test
files (~1,076 lines) that must pass unmodified.

Contents:

- [0. Zone map](#0-zone-map) — how CLAUDE.md's rules land on this tree
- [A. File classification](#a-file-classification) — all 85 files
- [B. Mixed files, line by line](#b-mixed-files-line-by-line) — 34 files
- [C. Component inventory](#c-component-inventory) — shared components, 22 duplicate clusters, dead declarations
- [D. User flows](#d-user-flows) — 13 flows: routes, steps, state, entry/exit
- [E. Proposed phase order](#e-proposed-phase-order) — 9 presentation-only phases
- [F. Deferred](#f-deferred--requires-flow_redesignmd) — flow/state findings, unscheduled

---

## Status

**Phases 1–9 are implemented; §F items 1, 2, 4, 5, 6, 7 are resolved.** Sections 0–D
below describe the codebase **as it was when this document was written** and are kept
as the record the work was planned against — the `file:line` citations in §B and §C no
longer resolve. Sections E and F carry per-item status.

Seven shared files now exist that did not before: `lib/core/theme/radii.dart`,
`lib/core/utils/error_copy.dart`, and `lib/core/widgets/{surfaces,media,thread,gate}.dart`.
Net effect across `lib/`: **−700 lines**, with `flutter analyze` clean and all 100 tests
passing unmodified.

Eight defects were fixed along the way. None were the duplication itself; each was
something the duplication had been hiding:

| Defect | Where |
|---|---|
| Pull-to-refresh dead on every empty state — the wrapper dropped `AlwaysScrollableScrollPhysics` | 7 screens |
| Sign-out scrolled off-screen with the appeal thread on a locked account | blocked gate |
| Back button had no size box — smaller tap target than the identical control a screen away | station profile |
| Send button 40 px, under the minimum tap target | appeal thread |
| Remove-photo button announced nothing to screen readers | appeal sheet |
| Bubble width capped at a literal 280 px, so it stayed 280 px on a tablet | appeal thread |
| Date fields with no visual indication they were tappable | time-off sheet |
| Card ripple painted square, underneath the card, on some screens and not others | 11 call sites |

**Not verified:** appearance. Every phase was checked with `flutter analyze` and
`flutter test`, but the visual pass — both themes, text scale 0.9 and 1.3, a notched
device — has not happened. Radii moved on many screens.

---

## 0. Zone map

CLAUDE.md's zones map onto this codebase **by layer, not by path**. A Flutter screen
is not a route file with JSX inside it; it is a class whose `build()` method is the JSX
and whose `State` fields and callbacks are the controller. The zone therefore often
changes *within* a file — which is what [section B](#b-mixed-files-line-by-line) is for.

| CLAUDE.md zone | This codebase |
|---|---|
| **FROZEN** — business rules, schema, env, tests | [lib/data/models/](lib/data/models/) · [lib/data/repositories/](lib/data/repositories/) · [lib/data/firestore_paths.dart](lib/data/firestore_paths.dart) · [lib/services/](lib/services/) · [lib/core/utils/date_x.dart](lib/core/utils/date_x.dart) · [lib/core/utils/doc_x.dart](lib/core/utils/doc_x.dart) · [lib/core/constants.dart](lib/core/constants.dart) · [lib/core/firebase_config.dart](lib/core/firebase_config.dart) · [lib/firebase_options.dart](lib/firebase_options.dart) · [lib/features/auth/auth_validators.dart](lib/features/auth/auth_validators.dart) · [lib/features/onboarding/onboarding_validators.dart](lib/features/onboarding/onboarding_validators.dart) · `firestore.rules` · `storage.rules` · [test/](test/) |
| **CHANGEABLE WITH APPROVAL** — flow & state | [lib/router.dart](lib/router.dart) · [lib/providers/](lib/providers/) · [lib/features/auth/auth_controller.dart](lib/features/auth/auth_controller.dart) · [lib/features/shell/app_shell.dart](lib/features/shell/app_shell.dart) · [lib/main.dart](lib/main.dart) · [lib/app.dart](lib/app.dart) · every `State` class's fields, `initState`, `dispose`, and any callback that writes to a repository |
| **FREE** — presentation | [lib/core/theme/](lib/core/theme/) · [lib/core/widgets/](lib/core/widgets/) · [lib/core/utils/haptics.dart](lib/core/utils/haptics.dart) · [lib/features/auth/auth_widgets.dart](lib/features/auth/auth_widgets.dart) · [lib/features/onboarding/onboarding_widgets.dart](lib/features/onboarding/onboarding_widgets.dart) · every `build()` body and private `StatelessWidget`/`CustomPainter` inside [lib/features/](lib/features/) |
| **OUT OF SCOPE** | [lib/dev/](lib/dev/) — 3 files, 1,950 lines, reached only via `flutter run -t lib/dev/seed_app.dart`; not in `main.dart`'s import graph |

**Two rulings worth stating explicitly.**

The validators live under `lib/features/` but are **frozen**: they are pure business
rules and [test/auth_test.dart](test/auth_test.dart) and
[test/core_logic_test.dart](test/core_logic_test.dart) assert their exact user-facing
strings and thresholds. Folder location is not the criterion; test coverage and rule
content are.

[lib/dev/seed_data.dart](lib/dev/seed_data.dart) is imported by
[test/core_logic_test.dart](test/core_logic_test.dart#L10) ("seed cast" group), so
although `lib/dev/` is out of scope for the refactor it is not free to delete.

---

## A. File classification

Five classes are used:

- **BUSINESS** — rules, parsing, arithmetic, persistence. Frozen.
- **FLOW** — routing, step order, what persists between steps. Approval required.
- **PRESENTATION** — layout, colour, type, motion. Free.
- **MIXED** — two or more of the above in one file. See [section B](#b-mixed-files-line-by-line).
- **TOOLING** — out of scope.

Totals: **20 BUSINESS · 3 FLOW · 21 PRESENTATION · 34 MIXED · 3 TOOLING · 4 TEST/FROZEN**

### Root

| File | Lines | Class | Why |
|---|---:|---|---|
| [lib/main.dart](lib/main.dart) | 45 | MIXED | Startup ordering is flow; the config-guard branch renders a screen |
| [lib/app.dart](lib/app.dart) | 69 | MIXED | Push wiring + uid listener are flow; `MaterialApp.router` config is presentation |
| [lib/router.dart](lib/router.dart) | 258 | MIXED | The redirect table is the app's spine; `_NotFoundScreen` and the fade transition are presentation |
| [lib/firebase_options.dart](lib/firebase_options.dart) | 68 | BUSINESS | Generated by `flutterfire configure`; overwritten wholesale — never hand-edit |

### lib/core (15)

| File | Lines | Class | Why |
|---|---:|---|---|
| [core/constants.dart](lib/core/constants.dart) | 128 | BUSINESS | Closed lists (spots, coordinates, levels, rate band) asserted by tests |
| [core/firebase_config.dart](lib/core/firebase_config.dart) | 28 | BUSINESS | Startup guard; asserted by [auth_test.dart:246](test/auth_test.dart#L246) |
| [core/theme/app_theme.dart](lib/core/theme/app_theme.dart) | 375 | PRESENTATION | `FlowTones` + all Material component themes |
| [core/theme/palette.dart](lib/core/theme/palette.dart) | 44 | PRESENTATION | Brand colour ramps |
| [core/theme/typography.dart](lib/core/theme/typography.dart) | 66 | PRESENTATION | `sora` / `inter` / `interNum` / `microLabel` |
| [core/utils/date_x.dart](lib/core/utils/date_x.dart) | 168 | BUSINESS | `Slot`, `BookingMath`, `ymd`, `euro` — the booking arithmetic |
| [core/utils/doc_x.dart](lib/core/utils/doc_x.dart) | 143 | BUSINESS | Tolerant Firestore readers |
| [core/utils/haptics.dart](lib/core/utils/haptics.dart) | 21 | PRESENTATION | Named haptic vocabulary |
| [core/widgets/brand.dart](lib/core/widgets/brand.dart) | 106 | PRESENTATION | `FlowLogo`, `FlowWordmark`, `WaveBackdrop` |
| [core/widgets/buttons.dart](lib/core/widgets/buttons.dart) | 122 | PRESENTATION | `PrimaryButton`, `MicroAction` |
| [core/widgets/feedback.dart](lib/core/widgets/feedback.dart) | 356 | MIXED | `ErrorView.friendly` maps Firestore codes to copy — business logic in the component library |
| [core/widgets/flow_image.dart](lib/core/widgets/flow_image.dart) | 111 | PRESENTATION | `FlowImage`, `FlowAvatar` |
| [core/widgets/misc.dart](lib/core/widgets/misc.dart) | 271 | MIXED | `PaymentPill` switches on `PaymentStatus` — the only domain coupling in `core/widgets` |
| [core/widgets/picker_field.dart](lib/core/widgets/picker_field.dart) | 385 | MIXED | Search filtering + prefix-first ranking is logic |
| [core/widgets/sheets.dart](lib/core/widgets/sheets.dart) | 124 | PRESENTATION | `showFlowSheet`, `confirmAction`, `showImageSourceSheet` |

### lib/data (20) — all BUSINESS, all frozen

| File | Lines | Note |
|---|---:|---|
| [data/firestore_paths.dart](lib/data/firestore_paths.dart) | 34 | Collection names — `firestore.rules` is written against these |
| [data/models/app_user.dart](lib/data/models/app_user.dart) | 161 | `isBlockInForce` fails closed — [admin_test.dart:49](test/admin_test.dart#L49) |
| [data/models/booking.dart](lib/data/models/booking.dart) | 242 | Lifecycle, bucketing, slot occupancy |
| [data/models/catalogue.dart](lib/data/models/catalogue.dart) | 134 | Station services, safari trips, `BookingTarget` |
| [data/models/payment.dart](lib/data/models/payment.dart) | 183 | Payment vocabulary; `unknown ≠ unpaid` is load-bearing |
| [data/models/report.dart](lib/data/models/report.dart) | 51 | |
| [data/models/schedule.dart](lib/data/models/schedule.dart) | 134 | `DayAvailability.compose`, reason precedence |
| [data/models/social.dart](lib/data/models/social.dart) | 199 | Reviews, chat threads, notifications |
| [data/models/support.dart](lib/data/models/support.dart) | 131 | Tickets, appeals (array-on-document) |
| [data/models/wind.dart](lib/data/models/wind.dart) | 148 | Wind bands, Open-Meteo parsing |
| [data/repositories/admin_repository.dart](lib/data/repositories/admin_repository.dart) | 197 | `unblockUser` restores prior status — do not simplify |
| [data/repositories/auth_repository.dart](lib/data/repositories/auth_repository.dart) | 232 | Error translation; heavily asserted by tests |
| [data/repositories/booking_repository.dart](lib/data/repositories/booking_repository.dart) | 530 | Slot clash re-check, lead time, check-in, settlement |
| [data/repositories/chat_repository.dart](lib/data/repositories/chat_repository.dart) | 139 | Client-side message sort (pending = newest) |
| [data/repositories/notification_repository.dart](lib/data/repositories/notification_repository.dart) | 83 | Per-document mark-read, deliberately not batched |
| [data/repositories/review_repository.dart](lib/data/repositories/review_repository.dart) | 97 | Double-submit guard |
| [data/repositories/schedule_repository.dart](lib/data/repositories/schedule_repository.dart) | 92 | Blocks, vacations |
| [data/repositories/storage_repository.dart](lib/data/repositories/storage_repository.dart) | 64 | Upload naming contract |
| [data/repositories/support_repository.dart](lib/data/repositories/support_repository.dart) | 172 | Tickets, appeals, reports, leave reasons |
| [data/repositories/user_repository.dart](lib/data/repositories/user_repository.dart) | 201 | Profile creation/update; `clear` set semantics |

### lib/providers (2) · lib/services (3)

| File | Lines | Class | Why |
|---|---:|---|---|
| [providers/providers.dart](lib/providers/providers.dart) | 615 | MIXED | Infra wiring (flow) wrapped around the gate state machine and the booking/revenue derivations (business) |
| [providers/settings_provider.dart](lib/providers/settings_provider.dart) | 60 | FLOW | Theme mode + first-run flags, persisted to prefs |
| [services/image_service.dart](lib/services/image_service.dart) | 81 | MIXED | Picking is a service; opening a sheet and pushing the cropper is presentation/flow |
| [services/push_service.dart](lib/services/push_service.dart) | 138 | MIXED | Token lifecycle is a service; `_onForeground` builds a SnackBar; `handleTap` makes route decisions |
| [services/wind_service.dart](lib/services/wind_service.dart) | 109 | BUSINESS | The app's only HTTP call; caching and silent failure |

### lib/features (35)

| File | Lines | Class | Why |
|---|---:|---|---|
| [features/admin/admin_screen.dart](lib/features/admin/admin_screen.dart) | 775 | MIXED | Moderation orchestration (block+close, reply+status, lift) inside the tab UI |
| [features/auth/auth_controller.dart](lib/features/auth/auth_controller.dart) | 262 | FLOW | Submit lifecycle, error placement, recovery offers |
| [features/auth/auth_validators.dart](lib/features/auth/auth_validators.dart) | 95 | BUSINESS | **Frozen** — [auth_test.dart](test/auth_test.dart) asserts exact strings |
| [features/auth/auth_widgets.dart](lib/features/auth/auth_widgets.dart) | 257 | PRESENTATION | `AuthScaffold`, `AuthBanner`, `AuthRecoveryCard`, `AuthTextField` |
| [features/auth/reset_password_screen.dart](lib/features/auth/reset_password_screen.dart) | 169 | MIXED | Local validation + send lifecycle + `_sent` branch |
| [features/auth/sign_in_screen.dart](lib/features/auth/sign_in_screen.dart) | 178 | MIXED | `_attempted` gating, focus routing, email hand-off |
| [features/auth/sign_up_screen.dart](lib/features/auth/sign_up_screen.dart) | 304 | MIXED | Three-field validation orchestration + strength meter |
| [features/auth/welcome_screen.dart](lib/features/auth/welcome_screen.dart) | 95 | MIXED | Mostly presentation; two navigation callbacks reset controller state |
| [features/booking/booking_screen.dart](lib/features/booking/booking_screen.dart) | 1060 | MIXED | Contiguity rule, stale-slot pruning and submit sit inside the screen |
| [features/chat/chat_screen.dart](lib/features/chat/chat_screen.dart) | 435 | MIXED | Scroll-follow contract, read-marking, run/timestamp grouping |
| [features/chat/inbox_screen.dart](lib/features/chat/inbox_screen.dart) | 189 | MIXED | Client-side search filter |
| [features/command_center/command_center_screen.dart](lib/features/command_center/command_center_screen.dart) | 1141 | MIXED | Largest file; tour gating, scanner, finish+settle, earnings ledger |
| [features/command_center/qr_scanner_screen.dart](lib/features/command_center/qr_scanner_screen.dart) | 288 | MIXED | Ticket payload validation is a security check inside a camera screen |
| [features/command_center/schedule_tab.dart](lib/features/command_center/schedule_tab.dart) | 773 | MIXED | Day rollover, block toggling, walk-in range validation |
| [features/explore/explore_screen.dart](lib/features/explore/explore_screen.dart) | 596 | MIXED | Search debounce + filter reset ordering |
| [features/explore/station_profile_screen.dart](lib/features/explore/station_profile_screen.dart) | 492 | MIXED | Tab-set derivation by operator type; safari reservation |
| [features/explore/trainer_profile_screen.dart](lib/features/explore/trainer_profile_screen.dart) | 833 | MIXED | Review-eligibility pre-check; report submission |
| [features/gates/blocked_screen.dart](lib/features/gates/blocked_screen.dart) | 452 | MIXED | One-minute ticker that releases a lapsed ban; appeal submission + thread |
| [features/gates/pending_screen.dart](lib/features/gates/pending_screen.dart) | 96 | PRESENTATION | One flow touchpoint: sign-out at [:28](lib/features/gates/pending_screen.dart#L28) |
| [features/gates/rejected_screen.dart](lib/features/gates/rejected_screen.dart) | 92 | PRESENTATION | Flow touchpoints: sign-out [:36](lib/features/gates/rejected_screen.dart#L36), `/support` [:80](lib/features/gates/rejected_screen.dart#L80) |
| [features/gates/setup_required_screen.dart](lib/features/gates/setup_required_screen.dart) | 153 | PRESENTATION | Build-failure explainer; own `MaterialApp` |
| [features/media/crop_screen.dart](lib/features/media/crop_screen.dart) | 402 | MIXED | Crop geometry and PNG export are business logic in a screen |
| [features/notifications/notifications_screen.dart](lib/features/notifications/notifications_screen.dart) | 249 | MIXED | Tap routing forks on role; mark-all-read batching |
| [features/onboarding/kiter_form_screen.dart](lib/features/onboarding/kiter_form_screen.dart) | 296 | MIXED | Field gating, first-problem scroll target, profile write |
| [features/onboarding/onboarding_validators.dart](lib/features/onboarding/onboarding_validators.dart) | 89 | BUSINESS | **Frozen** — [core_logic_test.dart:230](test/core_logic_test.dart#L230) |
| [features/onboarding/onboarding_widgets.dart](lib/features/onboarding/onboarding_widgets.dart) | 145 | PRESENTATION | `AvatarPicker`, `FormGroup` |
| [features/onboarding/role_select_screen.dart](lib/features/onboarding/role_select_screen.dart) | 172 | MIXED | `push` vs `go` choice is deliberate flow; rest is presentation |
| [features/onboarding/trainer_form_screen.dart](lib/features/onboarding/trainer_form_screen.dart) | 613 | MIXED | 4-step gate machine + sequential upload submit |
| [features/profile/edit_profile_screen.dart](lib/features/profile/edit_profile_screen.dart) | 473 | MIXED | Dirty tracking and the `clear` set are business rules |
| [features/profile/profile_screen.dart](lib/features/profile/profile_screen.dart) | 413 | MIXED | Account-deletion flow: reauth check, ordered deletes |
| [features/sessions/review_composer.dart](lib/features/sessions/review_composer.dart) | 130 | MIXED | Submit lifecycle inside a card |
| [features/sessions/sessions_screen.dart](lib/features/sessions/sessions_screen.dart) | 626 | MIXED | Deep-link highlight resolution; QR payload construction |
| [features/shell/app_shell.dart](lib/features/shell/app_shell.dart) | 105 | MIXED | Role→branch index mapping is flow; the nav bar is presentation |
| [features/splash/splash_screen.dart](lib/features/splash/splash_screen.dart) | 38 | PRESENTATION | |
| [features/support/support_screen.dart](lib/features/support/support_screen.dart) | 394 | MIXED | Ticket open/reply lifecycle; composer lock on resolved |

### lib/dev (3) — TOOLING, out of scope

| File | Lines | Note |
|---|---:|---|
| [dev/seed_app.dart](lib/dev/seed_app.dart) | 512 | Second entry point; creates accounts one at a time under real security rules |
| [dev/seed_content.dart](lib/dev/seed_content.dart) | 1002 | Activity pass; deterministic ids make it re-runnable |
| [dev/seed_data.dart](lib/dev/seed_data.dart) | 436 | The cast. **Imported by [core_logic_test.dart:10](test/core_logic_test.dart#L10)** — not deletable |

### test (3) — frozen, must pass unmodified

| File | Lines | Covers |
|---|---:|---|
| [test/core_logic_test.dart](test/core_logic_test.dart) | 633 | `Slot`, `BookingMath`, `Booking`, `DayAvailability`, `euro`, `OnboardingValidators`, nationality list, `DocX.date`, seed cast, wind |
| [test/auth_test.dart](test/auth_test.dart) | 274 | Email/password/confirm validation, strength, error placement + wording, translation, recovery, startup guard |
| [test/admin_test.dart](test/admin_test.dart) | 169 | Staff identification, account status, `blockedUntil`, `Report`, `Appeal` |

---

## B. Mixed files, line by line

Line numbers are as of this document's writing. **Ranges marked 🔒 are frozen** — restyle
around them, never through them. Ranges marked ⚠️ are flow/state and need FLOW_REDESIGN.md
approval. Everything else is free.

### Root

**[lib/main.dart](lib/main.dart)** (45)

| Lines | Class | What |
|---|---|---|
| 15-21, 27-44 | ⚠️ FLOW | Init order: config guard → Firebase → background handler → chrome → prefs → `runApp`. The prefs-before-first-frame ordering is why the theme never flashes |
| 22-25 | FREE | The `SetupRequiredScreen` early return |

**[lib/app.dart](lib/app.dart)** (69)

| Lines | Class | What |
|---|---|---|
| 19-25 | ⚠️ FLOW | `initState` — push controller start + context supplier |
| 29-30 | ⚠️ FLOW | Router and theme-mode watches |
| 35-42 | ⚠️ FLOW | uid listener → token sync / forget |
| 44-52 | FREE | `MaterialApp.router` — title, theme, debug banner |
| 53-66 | FREE | Text-scale clamp 0.9–1.3 |

**[lib/router.dart](lib/router.dart)** (258)

| Lines | Class | What |
|---|---|---|
| 34 | ⚠️ FLOW | `rootNavigatorKey` |
| 36-44 | FREE | `_fadePage` — 260 ms cross-fade for gates |
| 46-51 | ⚠️ FLOW | Router provider + session refresh listener |
| **56-96** | ⚠️ FLOW | **The redirect table.** Every gate decision in the app. See [section D](#d-user-flows) |
| 97-236 | ⚠️ FLOW | Route tree, shell branches, path params |
| 237 | ⚠️ FLOW | `errorBuilder` |
| 241-258 | FREE | `_NotFoundScreen` |

### lib/core

**[lib/core/widgets/feedback.dart](lib/core/widgets/feedback.dart)** (356)

| Lines | Class | What |
|---|---|---|
| 13-58 | FREE | `AsyncView` — the one place async state renders |
| **66-79** | 🔒 BUSINESS | **`ErrorView.friendly`** — Firestore code → user copy. Business logic living in `core/widgets`. Relocation proposed in [section F](#f-deferred--requires-flow_redesignmd) |
| 60-65, 81-119 | FREE | `ErrorView` chrome |
| 122-170 | FREE | `EmptyView` |
| 174-277 | FREE | `SkeletonPulse`, `SkeletonCard`, `SkeletonList` |
| 281-309 | FREE | `showFlowToast` |
| 312-356 | FREE | `withBusyOverlay` |

**[lib/core/widgets/misc.dart](lib/core/widgets/misc.dart)** (271)

| Lines | Class | What |
|---|---|---|
| 8-28 | FREE | `SectionHeader` |
| **36-57** | 🔒 BUSINESS (thin) | `PaymentPill` — switches on `PaymentStatus`, guards on `isDisplayable`. The `unknown` → render-nothing rule is deliberate and must survive |
| 60-87 | FREE | `TagPill` |
| 91-167 | FREE | `FlowChoiceChip` |
| 170-226 | FREE | `InfoTile` |
| 229-271 | FREE | `Stars` |

**[lib/core/widgets/picker_field.dart](lib/core/widgets/picker_field.dart)** (385)

| Lines | Class | What |
|---|---|---|
| 15-107 | FREE | `FlowPickerField` chrome |
| 44-56 | ⚠️ FLOW | `_open` — sheet round trip; `null` ≠ empty list |
| 111-154 | FREE | `_Tags` |
| 158-178 | FREE | `showFlowPicker` |
| **207-238** | 🔒 BUSINESS | `_query` / `_all` / `_visible` / `_canAddCustom` — search filter, **prefix-first ranking**, custom-value dedupe. "ge" must surface German before Nigerien |
| 240-265 | ⚠️ FLOW | `_toggle` / `_addCustom` — single-select commits on tap, multi-select accumulates |
| 267-385 | FREE | Sheet body and `_Row` |

### lib/providers

**[lib/providers/providers.dart](lib/providers/providers.dart)** (615)

| Lines | Class | What |
|---|---|---|
| 31-56 | ⚠️ FLOW | Infrastructure + repository wiring |
| 60-64 | ⚠️ FLOW | Auth stream, current uid |
| **75-85** | 🔒 BUSINESS | `signOutProvider` — token cleared **before** sign-out, best-effort. Rules reject the write afterwards |
| 89-93 | ⚠️ FLOW | `currentUserProvider` — streamed, not fetched once |
| 95-141 | 🔒 BUSINESS | `AppStage`, `Session`, `knownName` vs `displayName` |
| **145-208** | 🔒 BUSINESS | **`sessionProvider` — the gate state machine. Evaluation order is the rule.** Step 5 checks `isBlockInForce`, not just `status`, so a timed ban lapses on its own |
| 212-235 | ⚠️ FLOW | Explore/profile stream providers |
| 237-289 | ⚠️ FLOW | `ExploreFilter` + notifier; `activeCount` excludes the query |
| **292-315** | 🔒 BUSINESS | `filteredTrainersProvider` — favourites ∩ query ∩ spot ∩ languages, in that order |
| 319-332 | ⚠️ FLOW | Booking streams |
| **336-353** | 🔒 BUSINESS | `_bucketize` — per-side hiding, upcoming/active sorted soonest-first, history keeps source order |
| **364-421** | 🔒 BUSINESS | Pending requests, today manifest, revenue, month revenue, unpaid, outstanding. The comment at 406-412 explains why unpaid is *not* subtracted from earned |
| **431-495** | 🔒 BUSINESS | `dayAvailabilityProvider` — merges three streams, emits only when all three have a value; `autoDispose` teardown |
| 499-523 | ⚠️ FLOW | Wind providers; `providerWindProvider` resolves the spot from the profile |
| 527-576 | ⚠️ FLOW | Notifications, chat, support streams and counters |
| 583-615 | ⚠️ FLOW | Admin streams (staff-gated, autoDispose) + queue badge |

### lib/services

**[lib/services/image_service.dart](lib/services/image_service.dart)** (81)

| Lines | Class | What |
|---|---|---|
| **24-33** | ⚠️ FLOW | `pickWithSheet` — sheet → pick → crop. Crop lives here so no caller can forget it |
| **37-48** | ⚠️ FLOW | `crop` — pushes `CropScreen` on the root navigator |
| 50-61 | 🔒 BUSINESS | `pick` / `pickMulti` — enforces 1600 px / q82 |
| 68-80 | ⚠️ FLOW | `pickMultiCropped` — cancelling one crop drops one image, not the batch |

**[lib/services/push_service.dart](lib/services/push_service.dart)** (138)

| Lines | Class | What |
|---|---|---|
| 14-15 | 🔒 BUSINESS | Background handler — registered before `runApp` |
| 35-52 | 🔒 BUSINESS | `start` — subscriptions, token refresh, cold-start message |
| 57-69 | 🔒 BUSINESS | `syncTokenFor` — latch + retry semantics |
| **71-91** | FREE | `_onForeground` — builds a SnackBar. **The only presentation in a frozen file** |
| **96-116** | ⚠️ FLOW | `handleTap` — deep-link routing, forks on `isTrainer` |
| 124-131 | 🔒 BUSINESS | `forgetSyncedUid`, `dispose` |

### lib/features — auth

**[lib/features/auth/welcome_screen.dart](lib/features/auth/welcome_screen.dart)** (95) — 28-52 & 61-94 FREE; **54-60, 64-68** ⚠️ FLOW (`reset()` then `push`).

**[lib/features/auth/sign_in_screen.dart](lib/features/auth/sign_in_screen.dart)** (178)

| Lines | Class | What |
|---|---|---|
| 22-45 | ⚠️ FLOW | Controllers, focus nodes, `_attempted`; email seeded from `authEmailProvider` |
| **51-55** | 🔒 BUSINESS | Error getters — delegate to `AuthValidators`, gated on `_attempted` |
| **57-79** | ⚠️ FLOW | `_submit` — unfocus first, focus the failing field, hand email to the provider |
| 82-167 | FREE | `AuthScaffold` composition |
| **172-177** | ⚠️ FLOW | `_switchTo` — carries email, resets errors, `pushReplacement` |

**[lib/features/auth/sign_up_screen.dart](lib/features/auth/sign_up_screen.dart)** (304)

| Lines | Class | What |
|---|---|---|
| 28-70 | ⚠️ FLOW | Controllers + `_confirmTouched` focus listener |
| **74-87** | 🔒 BUSINESS | Error getters + `_confirmMatches` |
| **89-114** | ⚠️ FLOW | `_submit` — three-field gate, focus first problem |
| 116-233 | FREE | Form layout |
| **235-240** | ⚠️ FLOW | `_switchTo` |
| 245-304 | FREE | `_MatchHint`, `_StrengthMeter` |

**[lib/features/auth/reset_password_screen.dart](lib/features/auth/reset_password_screen.dart)** (169)

| Lines | Class | What |
|---|---|---|
| 28-48 | ⚠️ FLOW | Controller, `_attempted`, `_sent` |
| **50-67** | ⚠️ FLOW | `_send` — validate, send, flip to `_sent` |
| 70-113 | FREE | Form + `_resend` |
| 122-169 | FREE | `_SentState` — **enumeration-safe wording, do not make it conditional on existence** |

### lib/features — onboarding

**[lib/features/onboarding/role_select_screen.dart](lib/features/onboarding/role_select_screen.dart)** (172) — 18-50 & 90-172 FREE; **25** ⚠️ sign-out; **57-63, 74-78** ⚠️ `push` not `go`, so a mistapped role can be backed out of.

**[lib/features/onboarding/kiter_form_screen.dart](lib/features/onboarding/kiter_form_screen.dart)** (296)

| Lines | Class | What |
|---|---|---|
| 26-49 | ⚠️ FLOW | Field state; name seeded from `knownName`, **never `displayName`** |
| **61-80** | 🔒 BUSINESS | Per-field error getters — one place per field so the scroll target and the message agree |
| **82-101** | ⚠️ FLOW | `_submit` gate + first-problem scroll (name → details → languages) |
| **103-136** | 🔒 BUSINESS | Upload then `createRiderProfile`; router takes over on success |
| 138-295 | FREE | Form layout |

**[lib/features/onboarding/trainer_form_screen.dart](lib/features/onboarding/trainer_form_screen.dart)** (613)

| Lines | Class | What |
|---|---|---|
| 36-77 | ⚠️ FLOW | `_step`, `_lastStep`, `_attempted` set, controllers |
| **81-107** | 🔒 BUSINESS | Per-step gates; `_step1Ok`…`_step4Ok` |
| **109-137** | ⚠️ FLOW | `_next` / `_back` — Next is always tappable; failing reveals hints and scrolls to top |
| **139-184** | 🔒 BUSINESS | `_submit` — photo, gallery, certificate uploads in order, then `createTrainerProfile` |
| 186-292 | FREE | Scaffold, progress bar, directional slide transition |
| 294-612 | FREE | `_header`, `_buildStep1`…`_buildStep4` |

Note: [:329](lib/features/onboarding/trainer_form_screen.dart#L329) and
[:342](lib/features/onboarding/trainer_form_screen.dart#L342) inline their own name/bio
checks (`length <= 2`, `isEmpty`) instead of showing `_nameError` / `_bioError`. The
button gate and the inline message can therefore disagree. Flagged, not fixed — see
[section F](#f-deferred--requires-flow_redesignmd).

### lib/features — explore & booking

**[lib/features/explore/explore_screen.dart](lib/features/explore/explore_screen.dart)** (596)

| Lines | Class | What |
|---|---|---|
| 29-43 | ⚠️ FLOW | Search controller + debounce timer |
| **48-60** | ⚠️ FLOW | `_onQueryChanged` (220 ms debounce), `_clearQuery` (immediate) |
| 63-307 | FREE | Header, search row, chip strip, grid |
| **309-315** | ⚠️ FLOW | `_resetAll` — **cancels the debounce first**, or an in-flight timer re-applies the query |
| 318-392 | FREE | Filter sheet |
| 395-596 | FREE | `_TrainerCard`, `_FavHeart`, `_GridSkeleton` |
| 412-414 | ⚠️ FLOW | Station/safari vs trainer route fork |
| 429-440 | 🔒 BUSINESS | Optimistic favourite toggle |

**[lib/features/explore/trainer_profile_screen.dart](lib/features/explore/trainer_profile_screen.dart)** (833)

| Lines | Class | What |
|---|---|---|
| 28-57 | FREE | Screen shell + not-found state |
| 69-86 | ⚠️ FLOW | `PageController`, `_reviewableBooking`, `_reviewEligibilityChecked` |
| **88-108** | 🔒 BUSINESS | `_checkReviewEligibility` — checked before render, not on submit |
| 110-113 | FREE | `_images` |
| 116-313 | FREE | Sliver layout, header, info tiles, bio, languages |
| 315-323 | FREE | `_openViewer` |
| **326-425** | MIXED | Report sheet: 341-378 FREE; **385-418** 🔒 upload + `reportUser` |
| 428-605 | FREE | `_GalleryHeader`, `_FullScreenViewer`, `_ScrimButton` |
| 607-756 | FREE | `_ReviewsSection`, `_ReviewTile` |
| 650-676 | 🔒 BUSINESS | Review delete + the two-async-gap `mounted` guard |
| 760-833 | FREE | `_BottomBar` |
| 796-806 | ⚠️ FLOW | `openThread` then `push('/chat/…')` |
| 817-826 | ⚠️ FLOW | `BookingTarget` construction — the funnel every bookable thing passes through |

**[lib/features/explore/station_profile_screen.dart](lib/features/explore/station_profile_screen.dart)** (492)

| Lines | Class | What |
|---|---|---|
| 20-47 | FREE | Shell + not-found |
| **55-74** | 🔒 BUSINESS | Tab-set derivation: safari-only gets one tab, station gets three; services split by `ServiceKind` |
| 76-181 | FREE | `NestedScrollView`, header, tab bar |
| 185-255 | FREE | `_LessonsTab` — **236-247** ⚠️ books against the *station's* calendar with instructor as `subTarget` |
| 257-338 | FREE | `_ServicesTab` — **318-330** ⚠️ `BookingTarget` per service |
| 342-363 | FREE | `_ExpeditionsTab` |
| **378-413** | 🔒 BUSINESS | `_reserve` — confirm, transactional seat, `SlotTakenFailure` → "manifest full" |
| 415-492 | FREE | `_TripCard` |

**[lib/features/booking/booking_screen.dart](lib/features/booking/booking_screen.dart)** (1060)

| Lines | Class | What |
|---|---|---|
| 34-50 | ⚠️ FLOW | `_date`, `_selection`, `_message`, `_gearNeeded`, `_submitting` |
| **52-59** | ⚠️ FLOW | `_changeDay` — **selection never survives a day change** |
| **62-102** | 🔒 BUSINESS | **`_tapSlot`** — anchor-to-range contiguity rule; a blocked hour between picks collapses to a restart |
| **106-141** | 🔒 BUSINESS | **`_pruneSelection`** — post-frame, re-checks against live selection, keeps only `BookingMath.leadingRun`. A gapped selection would book straight across a taken hour |
| 143-261 | FREE | Body layout |
| 146-151 | ⚠️ FLOW | Availability watch + prune trigger |
| 264-342 | FREE | Review sheet |
| **344-385** | 🔒 BUSINESS | `_confirm` — `createBooking`, `SlotTakenFailure`/`LeadTimeFailure` both clear the selection |
| 389-435 | FREE | Success dialog (non-dismissible; Done pops the screen) |
| 438-529 | FREE | `_ReviewRow`, `_ProviderCard` |
| 537-667 | FREE | `_DayStrip` — 570-581 derives away/over-for-today flags |
| **674-680** | FREE | `windColor` — shared by strip and summary so a day cannot read two ways |
| 687-746 | FREE | `_WindSummary` |
| 748-811 | FREE | `_SlotArea` — 762-782 renders the away / fully-booked / late-in-day notices |
| 815-948 | FREE | `_SlotTile`, `_Notice`, `_SlotGridSkeleton` |
| 950-1060 | FREE | `_SummaryCard`, `_StickyBar` |

### lib/features — sessions & command centre

**[lib/features/sessions/sessions_screen.dart](lib/features/sessions/sessions_screen.dart)** (626)

| Lines | Class | What |
|---|---|---|
| 31-58 | ⚠️ FLOW | `TabController`, `_highlight`, `_highlightHandled`, `_cardKeys` |
| **60-91** | ⚠️ FLOW | `_handleHighlight` — finds which bucket holds the id, switches tab, scrolls, clears tint after ~4 s |
| 94-173 | FREE | Scaffold + tabs |
| **182-186** | 🔒 BUSINESS | `_tabLabel` — no count before data arrives, because zero must mean zero |
| 189-265 | FREE | `_LiveDot`, `_BookingList` |
| 269-369 | FREE | `SessionCard` |
| **371-419** | ⚠️ FLOW | `_actions` — status-dependent action set |
| **421-456** | 🔒 BUSINESS | `_cancelButton` — confirm, `cancelByRider`, failure must not leave the rider assuming success |
| 459-473 | FREE | `_openRateSheet` |
| 476-501 | FREE | `StatusPill` |
| 507-512 | FREE | `showQrTicket` |
| **522-539** | 🔒 BUSINESS | `_QrTicketDialogState` — live booking watch, started-haptic latch, **QR payload `{bookingId, trainerId}`** |
| 541-626 | FREE | Ticket dialog layout (**QR stays on white in dark mode**) |

**[lib/features/sessions/review_composer.dart](lib/features/sessions/review_composer.dart)** (130) —
35-43 ⚠️ state; **45-69** 🔒 `_submit`; 72-130 FREE.

**[lib/features/command_center/command_center_screen.dart](lib/features/command_center/command_center_screen.dart)** (1141)

| Lines | Class | What |
|---|---|---|
| 31-48 | ⚠️ FLOW | `TabController`, `_requestsKey`, `_todayScroll` |
| **51-59** | ⚠️ FLOW | `_maybeShowTour` — once per uid via `onboardingFlagsProvider` |
| **61-80** | 🔒 BUSINESS | `_openScanner` — push scanner, `checkIn`, `CheckInFailure` messaging |
| 82-93 | ⚠️ FLOW | `_scrollToRequests` |
| 95-142 | FREE | Scaffold, tabs, FAB |
| 145-176 | ⚠️ FLOW | `_TodayTab` provider watches |
| **178-181** | ⚠️ FLOW | `comingUp` derivation — **hardcodes `.take(10)` while `FlowConst.comingUpLimit = 10` exists unused**. See [section F](#f-deferred--requires-flow_redesignmd) |
| 183-232 | FREE | Today list composition |
| 238-343 | FREE | `_StatTile`, `_EmptyToday` |
| **358-379** | 🔒 BUSINESS | `_approve` — busy guard, haptic, UNDO in the toast |
| **381-431** | 🔒 BUSINESS | `_decline` — reason sheet, `setStatus(rejected)`, controller disposal |
| 433-518 | FREE | `_RequestCard` layout |
| 522-621 | FREE | `_ManifestCard` layout |
| **623-642** | 🔒 BUSINESS | `_scanToStart` — **duplicate of 61-80** |
| **644-698** | 🔒 BUSINESS | **`_finish`** — settlement sheet, then `completed`, then (separately) `markPaid`. The two writes are deliberately not atomic: a failed settlement must not report a failed finish |
| **702-740** | FREE | `_askSettlement` — one sheet, three outcomes (`true`/`false`/`null`) |
| 743-803 | FREE | `_openDetails` — 786-797 ⚠️ opens a chat thread |
| 806-859 | FREE | `_ComingUpRow` |
| 863-1012 | FREE | `showEarningsSheet` — 869-874 ⚠️ provider watches; 932-957 outstanding banner shown only when > 0 |
| **1018-1044** | 🔒 BUSINESS | `_settle` — confirm then `markPaid`, `PaymentFailure` surfaced verbatim |
| 1047-1141 | FREE | `showTrainerTour` — 4 steps |

**[lib/features/command_center/schedule_tab.dart](lib/features/command_center/schedule_tab.dart)** (773)

| Lines | Class | What |
|---|---|---|
| 28-32 | ⚠️ FLOW | `_date`, `_key` |
| **34-41** | 🔒 BUSINESS | `_shiftDay` — cannot navigate before today |
| **50-57** | 🔒 BUSINESS | **`_rollOverIfStale`** — a tab left open overnight would otherwise write a walk-in into the past |
| **59-73** | 🔒 BUSINESS | `_pickDate` — `initialDate` clamped, or `showDatePicker` asserts |
| 76-222 | FREE | Day navigator, action row, vacation banner, timeline section |
| **224-249** | 🔒 BUSINESS | `_toggleSlot` — blocked → release, free → block |
| **253-270** | 🔒 BUSINESS | Walk-in preconditions: only genuinely free hours, price pre-filled from rate |
| **278-287** | 🔒 BUSINESS | `slotRangeFree` — **checks `fitsInDay` first**, because `isFree` is vacuously true past 17:00 |
| **293-328** | 🔒 BUSINESS | Walk-in `submit` — `createWalkIn`, `SlotTakenFailure` handling |
| 330-416 | FREE | Walk-in sheet layout + controller disposal |
| **431-450** | 🔒 BUSINESS | Time-off `pick` — "to" can never precede "from" |
| **452-474** | 🔒 BUSINESS | Time-off `submit` — `addVacation` |
| 476-512 | FREE | Time-off sheet layout |
| 515-554 | FREE | `_DateButton` |
| 557-693 | FREE | `_Timeline` — 596-615 derives row state and tappability |
| 696-773 | FREE | `_VacationList` — 742-763 🔒 delete + UNDO via `restoreVacation` |

**[lib/features/command_center/qr_scanner_screen.dart](lib/features/command_center/qr_scanner_screen.dart)** (288)

| Lines | Class | What |
|---|---|---|
| 35-49 | ⚠️ FLOW | Controller with `DetectionSpeed.normal` — `noDuplicates` made a rejected ticket unretryable |
| 51-58 | ⚠️ FLOW | `_warn` — 3 s banner, camera stays open |
| **60-95** | 🔒 BUSINESS | **`_onDetect`** — JSON shape check, `trainerId` match, capture latch, 250 ms flash. A security check; the authoritative check is still server-side in `checkIn` |
| 97-214 | FREE | Scanner UI, error builder, torch |
| 217-288 | FREE | `_ScrimPainter`, `_RoundButton` |

### lib/features — chat, notifications, support

**[lib/features/chat/chat_screen.dart](lib/features/chat/chat_screen.dart)** (435)

| Lines | Class | What |
|---|---|---|
| 35-43 | ⚠️ FLOW | Scroll/input controllers, `_didInitialJump`, `_missedWhileAway`, `_lastCount` |
| **45-61** | 🔒 BUSINESS | `initState` — `openThread` + `markThreadRead` |
| **70-94** | ⚠️ FLOW | `_nearBottom` (120 px) and `_jumpToLatest` — **also marks the thread read**, or the inbox badge lingers |
| **96-118** | ⚠️ FLOW | `_onMessages` — first load jumps, later loads follow only when near the bottom |
| **120-142** | 🔒 BUSINESS | `_send` — clear optimistically, restore text on failure |
| 145-268 | FREE | Layout + jump-to-latest pill |
| **197-208** | 🔒 BUSINESS | Timestamp gap (10 min) and message-run grouping |
| 271-350 | FREE | `_Bubble` |
| **352-355** | 🔒 DUPLICATE | `monthsForChat` — re-declares what [date_x.dart:29-30](lib/core/utils/date_x.dart#L29-L30) provides |
| 357-435 | FREE | `_Composer`, `_ChatSkeleton` |

**[lib/features/chat/inbox_screen.dart](lib/features/chat/inbox_screen.dart)** (189) —
23 ⚠️ `_query`; **54-60** 🔒 partner-name filter; 26-87 & 89-189 FREE; **114-115** ⚠️ chat deep link.

**[lib/features/notifications/notifications_screen.dart](lib/features/notifications/notifications_screen.dart)** (249)

| Lines | Class | What |
|---|---|---|
| 20-21 | ⚠️ FLOW | Unread derivation |
| **29-45** | 🔒 BUSINESS | Mark-all-read + UNDO; only rendered when something is unread |
| 49-79 | FREE | List, empty state, skeleton |
| 87-96 | FREE | `_icon` |
| **98-138** | ⚠️ FLOW | `_open` — mark read, then route. **Forks on `isTrainer`**; broadcast/system open a sheet instead |
| **140-143** | 🔒 BUSINESS | `_delete` |
| 146-249 | FREE | `Dismissible` tile, semantics action, unread tint |

**[lib/features/support/support_screen.dart](lib/features/support/support_screen.dart)** (394)

| Lines | Class | What |
|---|---|---|
| 21-114 | FREE | Ticket list, empty state, FAB |
| 64-65 | ⚠️ FLOW | Push `TicketThreadScreen` (plain `MaterialPageRoute`, not a GoRoute) |
| **129-155** | 🔒 BUSINESS | New-ticket `submit` — sheet stays open until it succeeds |
| 157-193 | FREE | New-ticket sheet layout |
| 210-217 | ⚠️ FLOW | Thread input state |
| **219-239** | 🔒 BUSINESS | `_send` — restores text on failure |
| 242-393 | FREE | Thread layout; **338-388** composer locks when resolved, replaced by REOPEN |
| 378-385 | 🔒 BUSINESS | `reopenTicket` |

### lib/features — profile, gates, media, shell

**[lib/features/profile/profile_screen.dart](lib/features/profile/profile_screen.dart)** (413)

| Lines | Class | What |
|---|---|---|
| 24-27 | ⚠️ FLOW | Session + theme watches |
| 31-207 | FREE | Identity block, settings sections, version label |
| 99-126 | ⚠️ FLOW | Staff-only admin entry + queue badge |
| 162-165 | ⚠️ FLOW | Theme mode write |
| 181-189 | 🔒 BUSINESS | Sign-out confirm → `signOutProvider` |
| 209-219 | FREE | `_row` |
| 222-255 | FREE | `_openPrivacySheet` |
| **259-347** | 🔒 BUSINESS | **`_deleteAccountFlow`** — confirm → leave-reason sheet → **`needsReauthForDeletion` checked before anything is touched** → record reason → delete profile → delete auth user. The order is load-bearing: a profile deleted ahead of a failed auth deletion cannot be restored |
| 350-413 | FREE | `_SettingsCard`, `_PrivacyItem` |

**[lib/features/profile/edit_profile_screen.dart](lib/features/profile/edit_profile_screen.dart)** (473)

| Lines | Class | What |
|---|---|---|
| 34-50 | ⚠️ FLOW | Snapshot + field state |
| 52-72 | ⚠️ FLOW | `initState` / `_load` — listeners rebuild on every keystroke |
| **83-98** | 🔒 BUSINESS | `_dirty` — order-insensitive list comparison; drives the Save button |
| 100-103 | 🔒 BUSINESS | Name/languages error getters |
| **105-161** | 🔒 BUSINESS | `_save` — uploads, then `updateProfile` with the **`clear` set**. A null means "not editing"; emptying a field must be named explicitly or the write silently no-ops |
| 163-173 | ⚠️ FLOW | `_confirmLeave` — also intercepts predictive back |
| 176-417 | FREE | Form layout; 252-258 and 320-327 use `TextFormField.initialValue` for read-only fields to avoid leaking a controller per rebuild |
| 420-473 | FREE | `_GalleryThumb` |

**[lib/features/gates/blocked_screen.dart](lib/features/gates/blocked_screen.dart)** (452)

| Lines | Class | What |
|---|---|---|
| **37-51** | 🔒 BUSINESS | **One-minute ticker** — recomputes the countdown and invalidates `currentUserProvider` once the ban lapses, so the router releases the user without a restart |
| **59-69** | 🔒 BUSINESS | `_countdown` formatting |
| 71-166 | FREE | Gate layout, appeal branch |
| **170-212** | 🔒 BUSINESS | Appeal sheet submit — non-dismissible, **keeps the typed text on failure** |
| 214-291 | FREE | Appeal sheet layout, evidence thumbs |
| 303-338 | ⚠️ FLOW / 🔒 | `_AppealThreadState._reply` — `arrayUnion` via `replyToAppeal` |
| 340-452 | FREE | `_AppealThread`, `_AppealBubble` |

**[lib/features/media/crop_screen.dart](lib/features/media/crop_screen.dart)** (402)

| Lines | Class | What |
|---|---|---|
| 14-20 | 🔒 BUSINESS | `CropShape` — circle 1:1, rect 4:3 |
| 43-59 | ⚠️ FLOW | Scale/offset/window state |
| 73-85 | 🔒 BUSINESS | `_load` — decode + dispose discipline |
| **89-110** | 🔒 BUSINESS | `_minScale` / `_clamp` — panning can never expose a transparent gap |
| **112-129** | 🔒 BUSINESS | Gesture math — focal point stays anchored during a pinch |
| **133-195** | 🔒 BUSINESS | **`_save`** — output capped at `FlowConst.uploadMaxDimension` so a crop cannot smuggle a larger file past the upload contract; opaque backing because JPEG has no alpha |
| 198-301 | FREE | Scaffold, editor layout, first-layout centring |
| 304-402 | FREE | `_CropPainter`, `_Message` |

**[lib/features/shell/app_shell.dart](lib/features/shell/app_shell.dart)** (105)

| Lines | Class | What |
|---|---|---|
| 18-19 | ⚠️ FLOW | Role + unread watches |
| **22-29** | ⚠️ FLOW | **`branchOf`** — trainers get branches [0,2,3]; the Sessions branch is not in their bar |
| **37-44** | ⚠️ FLOW | `onDestinationSelected` — tapping the active tab pops that branch to its root |
| 45-105 | FREE | Destinations, `_BadgedIcon` |

### lib/features — admin

**[lib/features/admin/admin_screen.dart](lib/features/admin/admin_screen.dart)** (775)

| Lines | Class | What |
|---|---|---|
| **31-42** | ⚠️ FLOW | Staff gate — defence in depth alongside the route guard and Firestore rules |
| 44-70 | FREE | Tab labels with open counts |
| 75-112 | FREE | `_ApprovalsTab` |
| **125-145** | 🔒 BUSINESS | `_approve` — `approveTrainer` + UNDO via `restoreToPending`. **This is what makes a trainer visible in Explore** |
| **147-197** | 🔒 BUSINESS | `_reject` — reason sheet then `rejectTrainer` |
| 199-336 | FREE | `_ApplicantCard`, certificate viewer |
| 340-376 | FREE | `_ReportsTab` |
| 378-463 | FREE | `_ReportCard` |
| **465-522** | 🔒 BUSINESS | `_openResolveSheet` — **uphold writes a full ISO timestamp, not a bare `ymd`**; a date-only value parses to midnight and shortens the suspension |
| **583-631** | 🔒 BUSINESS | `_AppealCardState._send` — reply first, then status bump **in its own guard**; `resolved` is terminal |
| **633-654** | 🔒 BUSINESS | `_lift` — `unblockUser` then `setAppealStatus('resolved')` |
| 656-775 | FREE | `_AppealCard` layout |

---

## C. Component inventory

### C.1 Shared components (public, reusable)

Call-site counts are `grep` occurrences across `lib/`, declaration included.

| Component | File | Sites | Notes |
|---|---|---:|---|
| `showFlowToast` | [feedback.dart:281](lib/core/widgets/feedback.dart#L281) | 68 | Most-used thing in the app; carries the UNDO pattern |
| `PrimaryButton` | [buttons.dart:5](lib/core/widgets/buttons.dart#L5) | 29 | Keeps brand fill while busy |
| `FormGroup` | [onboarding_widgets.dart:101](lib/features/onboarding/onboarding_widgets.dart#L101) | 29 | Lives in `features/onboarding` but used by `features/profile` too |
| `TagPill` | [misc.dart:60](lib/core/widgets/misc.dart#L60) | 25 | |
| `interNum` | [typography.dart:47](lib/core/theme/typography.dart#L47) | 25 | Tabular figures — money and counters never jitter |
| `MicroAction` | [buttons.dart:63](lib/core/widgets/buttons.dart#L63) | 22 | |
| `SectionHeader` | [misc.dart:8](lib/core/widgets/misc.dart#L8) | 20 | |
| `EmptyView` | [feedback.dart:122](lib/core/widgets/feedback.dart#L122) | 20 | |
| `showFlowSheet` | [sheets.dart:8](lib/core/widgets/sheets.dart#L8) | 20 | Every sheet in the app |
| `AsyncView` | [feedback.dart:13](lib/core/widgets/feedback.dart#L13) | 17 | `onRetry` is required by design |
| `SkeletonPulse` | [feedback.dart:174](lib/core/widgets/feedback.dart#L174) | 13 | Honours reduce-motion |
| `FlowPickerField` | [picker_field.dart:15](lib/core/widgets/picker_field.dart#L15) | 12 | |
| `SkeletonList` | [feedback.dart:262](lib/core/widgets/feedback.dart#L262) | 12 | |
| `FlowChoiceChip` | [misc.dart:91](lib/core/widgets/misc.dart#L91) | 11 | |
| `FlowImage` | [flow_image.dart:8](lib/core/widgets/flow_image.dart#L8) | 11 | Never shows a broken-image glyph |
| `FlowAvatar` | [flow_image.dart:71](lib/core/widgets/flow_image.dart#L71) | 10 | |
| `WaveBackdrop` | [brand.dart:48](lib/core/widgets/brand.dart#L48) | 10 | Auth + all gates |
| `confirmAction` | [sheets.dart:63](lib/core/widgets/sheets.dart#L63) | 9 | |
| `StatusPill` | [sessions_screen.dart:476](lib/features/sessions/sessions_screen.dart#L476) | 6 | Public, but declared in a feature file and imported by `command_center` via a `show` clause |
| `FlowWordmark` | [brand.dart:27](lib/core/widgets/brand.dart#L27) | 6 | |
| `Stars` | [misc.dart:229](lib/core/widgets/misc.dart#L229) | 5 | Display and input in one widget |
| `FlowLogo` | [brand.dart:7](lib/core/widgets/brand.dart#L7) | 5 | |
| `AvatarPicker` | [onboarding_widgets.dart:12](lib/features/onboarding/onboarding_widgets.dart#L12) | 5 | |
| `InfoTile` | [misc.dart:170](lib/core/widgets/misc.dart#L170) | 4 | |
| `ErrorView` | [feedback.dart:60](lib/core/widgets/feedback.dart#L60) | 4 | |
| `SkeletonCard` | [feedback.dart:227](lib/core/widgets/feedback.dart#L227) | 4 | |
| `PaymentPill` | [misc.dart:36](lib/core/widgets/misc.dart#L36) | 3 | |
| `withBusyOverlay` | [feedback.dart:312](lib/core/widgets/feedback.dart#L312) | 2 | Account deletion only |
| `SessionCard` | [sessions_screen.dart:269](lib/features/sessions/sessions_screen.dart#L269) | 2 | |
| `ReviewComposerCard` | [review_composer.dart:15](lib/features/sessions/review_composer.dart#L15) | 3 | Profile + Sessions ▸ Rate |
| `AuthScaffold` / `AuthBanner` / `AuthRecoveryCard` / `AuthTextField` | [auth_widgets.dart](lib/features/auth/auth_widgets.dart) | 4 screens | Auth-only family |
| `showFlowPicker` | [picker_field.dart:158](lib/core/widgets/picker_field.dart#L158) | 2 | |
| `showImageSourceSheet` | [sheets.dart:101](lib/core/widgets/sheets.dart#L101) | 2 | |
| `showQrTicket` | [sessions_screen.dart:507](lib/features/sessions/sessions_screen.dart#L507) | 3 | |
| `showEarningsSheet` / `showTrainerTour` | [command_center_screen.dart:863](lib/features/command_center/command_center_screen.dart#L863) / [:1047](lib/features/command_center/command_center_screen.dart#L1047) | 2 | |

### C.2 Duplicates and near-duplicates

22 clusters, ordered by cost to fix ÷ benefit. Every entry is `file:line` of the
*declaration or first line of the duplicated block*.

**1 — Card decoration. 11 open-coded copies, 4 different radii.**
`BoxDecoration(color: tones.card, borderRadius: circular(N), border: Border.all(color: tones.line))`
appears at radius **14** ([schedule_tab.dart:531](lib/features/command_center/schedule_tab.dart#L531),
[:713](lib/features/command_center/schedule_tab.dart#L713),
[command_center_screen.dart:814](lib/features/command_center/command_center_screen.dart#L814)),
**16** ([trainer_profile_screen.dart:708](lib/features/explore/trainer_profile_screen.dart#L708),
[booking_screen.dart:968](lib/features/booking/booking_screen.dart#L968),
[support_screen.dart:66](lib/features/support/support_screen.dart#L66),
[command_center_screen.dart:906](lib/features/command_center/command_center_screen.dart#L906)),
**18** ([station_profile_screen.dart:206](lib/features/explore/station_profile_screen.dart#L206),
[:286](lib/features/explore/station_profile_screen.dart#L286),
[booking_screen.dart:473](lib/features/booking/booking_screen.dart#L473),
[inbox_screen.dart:116](lib/features/chat/inbox_screen.dart#L116),
[profile_screen.dart:356](lib/features/profile/profile_screen.dart#L356)),
and **20** ([command_center_screen.dart:316](lib/features/command_center/command_center_screen.dart#L316),
[:437](lib/features/command_center/command_center_screen.dart#L437),
[:530](lib/features/command_center/command_center_screen.dart#L530),
[admin_screen.dart:204](lib/features/admin/admin_screen.dart#L204),
[:385](lib/features/admin/admin_screen.dart#L385),
[:666](lib/features/admin/admin_screen.dart#L666),
[sessions_screen.dart:284](lib/features/sessions/sessions_screen.dart#L284),
[station_profile_screen.dart:419](lib/features/explore/station_profile_screen.dart#L419),
[explore_screen.dart:576](lib/features/explore/explore_screen.dart#L576),
[feedback.dart:233](lib/core/widgets/feedback.dart#L233)).
`ThemeData.cardTheme` at [app_theme.dart:210](lib/core/theme/app_theme.dart#L210) already
defines radius 20 + `tones.line` — **and almost nothing uses `Card`**. No `FlowCard` exists.
*Largest single duplication in the codebase.*

**2 — Tinted rounded-square icon chip. 11 copies.**
A `Container` with a `withValues(alpha:)` fill, `circular(10…28)`, and a centred icon:
[feedback.dart:90](lib/core/widgets/feedback.dart#L90) ·
[feedback.dart:145](lib/core/widgets/feedback.dart#L145) ·
[blocked_screen.dart:105](lib/features/gates/blocked_screen.dart#L105) ·
[pending_screen.dart:36](lib/features/gates/pending_screen.dart#L36) ·
[rejected_screen.dart:44](lib/features/gates/rejected_screen.dart#L44) ·
[setup_required_screen.dart:124](lib/features/gates/setup_required_screen.dart#L124) ·
[notifications_screen.dart:192](lib/features/notifications/notifications_screen.dart#L192) ·
[profile_screen.dart:385](lib/features/profile/profile_screen.dart#L385) ·
[command_center_screen.dart:1084](lib/features/command_center/command_center_screen.dart#L1084) ·
[booking_screen.dart:401](lib/features/booking/booking_screen.dart#L401) ·
[sessions_screen.dart:553](lib/features/sessions/sessions_screen.dart#L553).
Sizes range 40–88 px and radii 10–28 with no system behind the variation.

**3 — Status pill. Three renderings of one idea.**
`TagPill` ([misc.dart:60](lib/core/widgets/misc.dart#L60), radius 8, `inter(11,680)`) ·
`StatusPill` ([sessions_screen.dart:476](lib/features/sessions/sessions_screen.dart#L476),
radius 7, `inter(10,740)`, own container — does **not** use `TagPill`) ·
inline appeal status ([blocked_screen.dart:365](lib/features/gates/blocked_screen.dart#L365),
radius 8, `inter(10.5,720)`). `PaymentPill` correctly delegates to `TagPill`; the other two do not.

**4 — Circular scrim icon button. Three implementations.**
`_ScrimButton` ([trainer_profile_screen.dart:571](lib/features/explore/trainer_profile_screen.dart#L571), 42 px, `alpha .35`) ·
`_RoundButton` ([qr_scanner_screen.dart:253](lib/features/command_center/qr_scanner_screen.dart#L253), 48 px, `alpha .4`, has an `active` state) ·
inline back button ([station_profile_screen.dart:83](lib/features/explore/station_profile_screen.dart#L83), no size box, `alpha .35`).

**5 — Gallery thumbnail with remove ✕. Three copies.**
`_GalleryThumb` ([edit_profile_screen.dart:420](lib/features/profile/edit_profile_screen.dart#L420), 84 px, has a NEW badge) ·
inline ([trainer_form_screen.dart:379](lib/features/onboarding/trainer_form_screen.dart#L379), 84 px) ·
inline ([blocked_screen.dart:231](lib/features/gates/blocked_screen.dart#L231), 72 px).
All three use `Colors.black54` + `close_rounded` at size 14; only one has a `Semantics` label.

**6 — Message thread. Three independent bubble + composer implementations.**
Chat: `_Bubble` [chat_screen.dart:271](lib/features/chat/chat_screen.dart#L271) + `_Composer` [:357](lib/features/chat/chat_screen.dart#L357) (run grouping, corner radii, long-press copy).
Support: inline bubble [support_screen.dart:280](lib/features/support/support_screen.dart#L280) + inline composer [:331](lib/features/support/support_screen.dart#L331).
Appeals: `_AppealBubble` [blocked_screen.dart:418](lib/features/gates/blocked_screen.dart#L418) + inline reply row [:385](lib/features/gates/blocked_screen.dart#L385).
Three different max-widths (`.74`, `.78`, 280 px), three different timestamp treatments.

**7 — Sign-out app-bar action. Four byte-identical copies.**
[role_select_screen.dart:24](lib/features/onboarding/role_select_screen.dart#L24) ·
[blocked_screen.dart:94](lib/features/gates/blocked_screen.dart#L94) ·
[pending_screen.dart:26](lib/features/gates/pending_screen.dart#L26) ·
[rejected_screen.dart:34](lib/features/gates/rejected_screen.dart#L34).
Same icon, same size, same `FlowColors.haze`, same `inter(14, 600)`.

**8 — Empty-list wrapper. Seven copies.**
`ListView(children: const [SizedBox(height: 60), EmptyView(...)])`:
[inbox_screen.dart:62](lib/features/chat/inbox_screen.dart#L62) ·
[notifications_screen.dart:59](lib/features/notifications/notifications_screen.dart#L59) ·
[support_screen.dart:41](lib/features/support/support_screen.dart#L41) ·
[admin_screen.dart:92](lib/features/admin/admin_screen.dart#L92) ·
[:357](lib/features/admin/admin_screen.dart#L357) ·
[:544](lib/features/admin/admin_screen.dart#L544) ·
[sessions_screen.dart:244](lib/features/sessions/sessions_screen.dart#L244) (height 60 → variant).
[explore_screen.dart:231](lib/features/explore/explore_screen.dart#L231) is the same idea with height 40.
The wrapper exists only so `RefreshIndicator` has something scrollable.

**9 — Notice / callout box. Six variants.**
`_Notice` ([booking_screen.dart:893](lib/features/booking/booking_screen.dart#L893), `warningTint`, radius 18) ·
vacation banner ([schedule_tab.dart:166](lib/features/command_center/schedule_tab.dart#L166), `warningTint`, radius 16) ·
rate callout ([trainer_form_screen.dart:505](lib/features/onboarding/trainer_form_screen.dart#L505), `successTint`, radius 14) ·
review callout ([trainer_form_screen.dart:589](lib/features/onboarding/trainer_form_screen.dart#L589), azure `.1`, radius 14) ·
outstanding banner ([command_center_screen.dart:932](lib/features/command_center/command_center_screen.dart#L932), warning `.12` + border, radius 14) ·
`AuthBanner` ([auth_widgets.dart:83](lib/features/auth/auth_widgets.dart#L83), coral `.13` + border, radius 12).
Same anatomy — tinted box, leading icon, title and/or body — six times, six radii.

**10 — Duplicated constant.**
`monthsForChat` ([chat_screen.dart:352](lib/features/chat/chat_screen.dart#L352)) re-declares
what `monthsShort` / `monthsLong` at [date_x.dart:29-30](lib/core/utils/date_x.dart#L29-L30)
already provide. Both are `['Jan','Feb',…]` — `monthsShort` is uppercase, which is the only
reason a second list was written.

**11 — Sticky bottom bar. Four copies.**
`surfaceContainerLow` + `Border(top: BorderSide(color: tones.line))` + `MediaQuery.paddingOf(context).bottom`:
[booking_screen.dart:1015](lib/features/booking/booking_screen.dart#L1015) ·
[trainer_profile_screen.dart:769](lib/features/explore/trainer_profile_screen.dart#L769) ·
[chat_screen.dart:371](lib/features/chat/chat_screen.dart#L371) ·
[support_screen.dart:331](lib/features/support/support_screen.dart#L331).

**12 — Full-screen image viewer. Two implementations.**
`_FullScreenViewer` ([trainer_profile_screen.dart:520](lib/features/explore/trainer_profile_screen.dart#L520)
— paged, `InteractiveViewer` maxScale 4, `_ScrimButton` close) vs the certificate viewer
([admin_screen.dart:310](lib/features/admin/admin_screen.dart#L310) — single image,
maxScale 5, `IconButton.filledTonal` close). Both `PageRouteBuilder(opaque: false, barrierColor: Colors.black)`.

**13 — Page-dot indicator. Two copies.**
[trainer_profile_screen.dart:483](lib/features/explore/trainer_profile_screen.dart#L483) and
[command_center_screen.dart:1104](lib/features/command_center/command_center_screen.dart#L1104).
Identical: `AnimatedContainer`, 200 ms, `width: i == active ? 18 : 6`, height 6, radius 3.

**14 — Date block (month over day). Two copies.**
[sessions_screen.dart:303](lib/features/sessions/sessions_screen.dart#L303) (52 px, azure `.1` fill, radius 12) and
[command_center_screen.dart:824](lib/features/command_center/command_center_screen.dart#L824) (44 px, no fill).
Both render `monthsShort[day.month-1]` over `day.day` with the same weights.

**15 — Icon/number + title + body row. Two copies.**
`_Step` ([setup_required_screen.dart:106](lib/features/gates/setup_required_screen.dart#L106), numbered) vs
`_PrivacyItem` ([profile_screen.dart:367](lib/features/profile/profile_screen.dart#L367), icon).
Same 30–42 px leading chip, same column, same spacing.

**16 — Centred message state.**
`_Message` ([crop_screen.dart:377](lib/features/media/crop_screen.dart#L377)) re-implements
`EmptyView` because `crop_screen` deliberately avoids the theme (it runs on `FlowColors.ink`
regardless of brightness). Real constraint, but the duplication is unmanaged.

**17 — Stat / hero tile. Two shapes in one file.**
`_StatTile` ([command_center_screen.dart:238](lib/features/command_center/command_center_screen.dart#L238),
gradient when emphasised) vs the two earnings cards
([:884](lib/features/command_center/command_center_screen.dart#L884) gradient,
[:906](lib/features/command_center/command_center_screen.dart#L906) plain).
Same label-over-value anatomy, different radii (18 vs 16) and label sizes (9.5 vs 10).

**18 — Icon-result dialog. Three copies.**
Booking success ([booking_screen.dart:389](lib/features/booking/booking_screen.dart#L389)) ·
QR started state ([sessions_screen.dart:549](lib/features/sessions/sessions_screen.dart#L549)) ·
trainer tour ([command_center_screen.dart:1078](lib/features/command_center/command_center_screen.dart#L1078)).
All three: `Dialog` → `Padding` → `Column(mainAxisSize: min)` → 72–76 px tinted icon circle →
headline → body → `PrimaryButton`.

**19 — Label-over-value tile.**
`_DateButton` ([schedule_tab.dart:515](lib/features/command_center/schedule_tab.dart#L515)) vs
`InfoTile` ([misc.dart:170](lib/core/widgets/misc.dart#L170)). `_DateButton` is `InfoTile`
minus the leading icon and trailing arrow; `InfoTile` already makes both optional-ish.

**20 — Evidence-attachment sheet. Two copies.**
Report sheet ([trainer_profile_screen.dart:326](lib/features/explore/trainer_profile_screen.dart#L326)) vs
appeal sheet ([blocked_screen.dart:170](lib/features/gates/blocked_screen.dart#L170)).
Both: `StatefulBuilder` + local `busy` + `List<XFile>` + upload-then-write + keep-open-on-failure.
The report uses `ImageService.pickMulti()` (no crop); the appeal uses
`pickWithSheet(shape: null)` (also no crop) — same intent, two spellings.

**21 — Skeletons. A family with no shared base.**
`SkeletonList` ([feedback.dart:262](lib/core/widgets/feedback.dart#L262)) ·
`_GridSkeleton` ([explore_screen.dart:561](lib/features/explore/explore_screen.dart#L561)) ·
`_SlotGridSkeleton` ([booking_screen.dart:929](lib/features/booking/booking_screen.dart#L929)) ·
`_ChatSkeleton` ([chat_screen.dart:411](lib/features/chat/chat_screen.dart#L411)) ·
timeline skeleton inline ([schedule_tab.dart:201](lib/features/command_center/schedule_tab.dart#L201)).
All build on `SkeletonPulse`, none share layout scaffolding.

**22 — Scanner launch + check-in. The same 18 lines twice.** *(Flow — deferred.)*
`_openScanner` ([command_center_screen.dart:61](lib/features/command_center/command_center_screen.dart#L61))
and `_scanToStart` ([:623](lib/features/command_center/command_center_screen.dart#L623)) are
identical except that one guards on `mounted` (State) and the other on `context.mounted`
(ConsumerWidget) — which is exactly why they were not shared.

### C.3 Dead or unwired declarations

All sit in frozen files. Listed as observations; none are actioned by this plan.

**Read the last column before acting on any row.** Several have no `lib/` call site but are
directly asserted by the frozen test suites — deleting them breaks `flutter test`.

| Declaration | Where | `lib/` | `test/` | Status |
|---|---|---:|---:|---|
| `FlowConst.comingUpLimit = 10` | [constants.dart:116](lib/core/constants.dart#L116) | 0 | 0 | Genuinely unwired — [command_center_screen.dart:181](lib/features/command_center/command_center_screen.dart#L181) hardcodes `.take(10)` |
| `UserRepository.watchProfile` | [user_repository.dart:22](lib/data/repositories/user_repository.dart#L22) | 0 | 0 | Genuinely unused; an alias for `watchUser` |
| `ScheduleRepository.watchAllBlocks` | [schedule_repository.dart:25](lib/data/repositories/schedule_repository.dart#L25) | 0 | 0 | Genuinely unused |
| `FlowTones.onSuccessTint` | [app_theme.dart:28](lib/core/theme/app_theme.dart#L28) | 0 | 0 | Declared and populated in both themes; never read |
| `FlowTones.copyWith` | [app_theme.dart:92](lib/core/theme/app_theme.dart#L92) | — | — | Returns `this` — a stub satisfying `ThemeExtension`. Required by the interface |
| `Booking.awaitsPayment` | [booking.dart:154](lib/data/models/booking.dart#L154) | 0 | **5** | **Not dead** — asserted by the `payments` group in [core_logic_test.dart](test/core_logic_test.dart). The UI reads `payment.isOutstanding` directly instead |
| `PaymentMethod.isCollectedInPerson` | [payment.dart:63](lib/data/models/payment.dart#L63) | 0 | **2** | **Not dead** — asserted by "only cash is offered, and only cash is settled by a person". A documented seam for a future processor |
| `WindRating.suitsBeginners` | [wind.dart:42](lib/data/models/wind.dart#L42) | 0 | **5** | **Not dead** — asserted by "only the middle bands suit beginners" |

---

## D. User flows

### D.0 The gate machine (frames everything below)

`sessionProvider` ([providers.dart:145-208](lib/providers/providers.dart#L145-L208)) collapses
auth + profile into one `AppStage`. **Evaluation order is the rule**, not an implementation
detail:

1. auth stream loading → `loading`
2. no Firebase user → `signedOut`
3. profile stream loading → `loading`
4. profile missing **or** `role == unknown` → `chooseRole`
5. `status == blocked` **and** `isBlockInForce` → `blocked`
6. non-staff trainer, `status == pending` → `awaitingApproval`
7. non-staff trainer, `status == rejected` → `rejected`
8. otherwise → `ready`

`router.dart` ([:56-96](lib/router.dart#L56-L96)) turns each stage into a redirect:

| Stage | Allowed | Otherwise redirect to |
|---|---|---|
| `loading` | `/` | `/` |
| `signedOut` | `/auth`, `/auth/*` | `/auth` |
| `chooseRole` | `/onboarding*` | `/onboarding/role` |
| `awaitingApproval` | `/pending` | `/pending` |
| `blocked` | `/blocked` | `/blocked` |
| `rejected` | `/rejected`, `/support` | `/rejected` |
| `ready` | everything except `/`, `/auth*`, `/pending`, `/blocked`, `/rejected`, `/onboarding*` | `/home` |

Two extra `ready` rules: `/admin` redirects to `/home` unless `isStaff`; `/sessions*`
redirects to `/home` for trainers.

The session is **streamed, not fetched** — approval, a block, or a block lapsing moves the
user immediately, with no restart.

---

### D.1 Authentication

**Routes** `/auth` (Welcome) → `/auth/sign-in` · `/auth/sign-up` · `/auth/reset`
Four routes, not one screen with a mode toggle.

**Step order** Welcome → pick a door → credentials → submit. On success the auth stream
flips the session and the router replaces the screen; **no screen navigates on success**.

**State**
- `authControllerProvider` ([auth_controller.dart:72](lib/features/auth/auth_controller.dart#L72)) — `busy`, `banner`, `fieldErrors`, `notice`, `recovery`. Reset on every screen entry.
- `authEmailProvider` ([:80](lib/features/auth/auth_controller.dart#L80)) — **the typed email survives every switch between the three screens.**
- Per-screen local: controllers, focus nodes, `_attempted`, `_obscure`, `_confirmTouched`, `_sent`.

**Entry** Cold start while signed out · sign-out from anywhere · the router bouncing any
route while `signedOut`.
**Exit** Successful credential call → session flips → `chooseRole` or `ready`.

**Notable** Wrong-door recovery: `email-already-in-use` on sign-up offers "Sign in";
`user-not-found` on sign-in offers "Sign up" ([auth_controller.dart:243-247](lib/features/auth/auth_controller.dart#L243-L247)).
Password reset always reports the same outcome, deliberately, to avoid an enumeration oracle.

### D.2 Rider onboarding

**Route** `/onboarding/role` → `/onboarding/rider` (pushed, so Back returns)

**Step order** One page. Submit validates in order name → nationality/age → languages/bio and
**scrolls the first unmet field into view** ([kiter_form_screen.dart:82-101](lib/features/onboarding/kiter_form_screen.dart#L82-L101)).

**State** All local to `_KiterFormScreenState`. Name pre-filled from `session.knownName` —
**never `displayName`**, or the "Rider" placeholder is one tap from being saved as a real name.
Nothing persists if the user backs out.

**Entry** `chooseRole` stage. **Exit** `createRiderProfile` writes `status: 'active'` → session → `ready` → `/home`.
Back-navigation is blocked while saving (`PopScope canPop: !_busy`).

### D.3 Trainer onboarding

**Route** `/onboarding/role` → `/onboarding/trainer`

**Step order** 4 gated steps in one route: **1** profile (photo\*, name\*, bio\*, languages\*, gallery) →
**2** spot (spot\*, maps link) → **3** rate (\*, €60–110) → **4** verification (IKO ID\*, certificate).
Next is always tappable; tapping on an incomplete step marks it attempted, reveals hints and
scrolls to top. Back is intercepted by `PopScope` and steps backwards rather than leaving.

**State** `_step`, `_lastStep`, `_attempted` (a `Set<int>`), and all field controllers local to
`_TrainerFormScreenState`. **Leaving the route loses everything** — there is no draft.

**Entry** `chooseRole`. **Exit** Submit uploads photo → gallery → certificate sequentially, then
`createTrainerProfile` writes `status: 'pending'` → session → `awaitingApproval` → `/pending`.

### D.4 Explore → book a trainer

**Routes** `/home` (Explore) → `/trainer/:id` → `/book/:id` (target passed via `extra`)

**Step order** Search/filter → trainer card → profile → **Book now** → day strip →
hour grid → summary → **Review & confirm** sheet → **Confirm** → success dialog → Done pops
back to the profile.

**State**
- Filter: `exploreFilterProvider` — **survives navigation**, so returning to Explore keeps the filter. The search field is debounced 220 ms; `_resetAll` cancels the debounce first.
- Booking: `_date` and `_selection` local to `_BookingScreenState`. **Selection is cleared on any day change** and pruned live when availability changes.
- Availability: `dayAvailabilityProvider((instructorId, date))` — merges blocks + bookings + vacations, `autoDispose`.
- `BookingTarget` is transient and never persisted.

**Entry** Explore card · trainer profile · station instructor/service card · deep link to `/book/:id` **with `extra`** (a bare URL crashes — `state.extra as BookingTarget` at [router.dart:214](lib/router.dart#L214)).
**Exit** Success dialog Done → `context.pop()`. Or `SlotTakenFailure`/`LeadTimeFailure` → sheet closes, selection clears, toast explains.

### D.5 Station and safari booking

**Routes** `/home` → `/station/:id` → `/book/:id` (lessons and services) or an in-place transaction (expeditions)

**Step order** Tabs derive from operator type: safari-only → one EXPEDITIONS tab; station →
LESSONS / RENTALS / BEACH. Lessons and services route into D.4's booking screen with the
**station** as `providerId` and the instructor or service name as `subTarget`.
Expeditions never enter the booking screen: **Reserve my seat** → `confirmAction` → transactional
`reserveSafariSeat` → toast.

**State** All read-through providers; only `_TripCardState._busy` is local.
**Entry** Explore card where `isStation || isSafariOperator`. **Exit** Toast, or `SlotTakenFailure` → "manifest full".

### D.6 Rider sessions and the QR ticket

**Route** `/sessions`, optionally `?highlight=<bookingId>`

**Step order** Three tabs (UPCOMING / ACTIVE / HISTORY) from `riderBucketsProvider`. Card actions
depend on status: pending → CANCEL · confirmed → CHECK IN + CANCEL · in-progress → SHOW TICKET ·
completed → RATE.

**State** `_tabs`, `_highlight`, `_highlightHandled`, `_cardKeys` local. Deep-link handling
([sessions_screen.dart:60-91](lib/features/sessions/sessions_screen.dart#L60-L91)) finds which
bucket holds the id, switches tab, waits 350 ms, scrolls the card in, drops the tint after 4 s.

**Entry** Tab bar · notification tap · **push notification tap** ([push_service.dart:103-110](lib/services/push_service.dart#L103-L110)) · `didUpdateWidget` when a new highlight arrives on the same route.
**Exit** Tab switch. The QR dialog watches `bookingByIdProvider` and flips to "Session started"
with a haptic the instant the trainer scans.

### D.7 Trainer day (Command Center)

**Route** `/home` — resolved through a `Consumer` so a role change swaps Explore ⇄ Command Center without a restart ([router.dart:161-166](lib/router.dart#L161-L166))

**Step order** Two tabs.
*TODAY*: stat row (Requests / Upcoming / Total earned) → Action required → Today's manifest →
Coming up. Approve is one tap with UNDO in the toast; Decline opens a reason sheet.
Manifest cards offer SCAN TO START (confirmed) or FINISH SESSION (in progress).
**Finish is one sheet with three outcomes**: paid / still owing / cancel — then `completed`,
then `markPaid` as a **separate** write.
*SCHEDULE*: day navigator (never before today) → WALK-IN / TIME OFF → timeline (tap to
block/release) → scheduled time off list (delete with UNDO).

**State** `_tabs`, `_requestsKey`, `_todayScroll` (Command Center); `_date` (Schedule tab, with
overnight rollover at [:50-57](lib/features/command_center/schedule_tab.dart#L50-L57)).
First-run tour gated by `onboardingFlagsProvider` per uid.

**Entry** Any trainer landing on `/home` · CHECK IN FAB from either tab · push tap (trainers go to `/home`, never `/sessions`).
**Exit** Scanner returns a bookingId → `checkIn` → toast. Earnings sheet is a modal over the tab.

### D.8 Chat

**Routes** `/inbox` → `/chat/:id?name=<partnerName>`

**Step order** Inbox (client-side name search) → thread. Opening a thread creates the document
if needed and clears the unread counter.

**State** `_scroll`, `_input`, `_didInitialJump`, `_missedWhileAway`, `_lastCount`, `_canSend`.
Scroll contract: jump to newest on first load; afterwards follow only when within 120 px of the
bottom, otherwise count into a jump-to-latest pill. **Tapping the pill also marks the thread read.**

**Entry** Inbox tab · Message from a trainer profile · Message rider from a manifest detail sheet ·
push tap with `type == 'message'`.
**Exit** Back. Failed sends restore the text to the composer.

### D.9 Notifications

**Route** `/notifications` (root navigator — a modal over whatever is beneath)

**Step order** List → tap. Tap marks read fire-and-forget, then routes: booking kinds and
reminders go to `/home` for trainers and `/sessions?highlight=…` for riders; `message` → `/inbox`;
`review` → `/sessions`; broadcast/system have **no destination** and open the full untruncated
text in a sheet.

**State** None local beyond the list. Swipe-to-delete is also exposed as a custom semantics action.
**Entry** Bell icon on Explore and Command Center · Profile ▸ Notifications · push tap fallback.
**Exit** `context.go(...)` — note this **replaces** rather than pushes, so the notification screen is left behind.

### D.10 Support tickets

**Route** `/support` → `TicketThreadScreen` (a plain `MaterialPageRoute`, not a GoRoute)

**Step order** Ticket list → NEW TICKET sheet (subject\*, body\*) or open an existing thread.
The thread composer **locks when support resolves the ticket** and is replaced by REOPEN.

**State** `_query`-free list; `_input` and `_sending` in the thread.
**Entry** Profile ▸ Help & support · **Contact support from the rejected gate** — the one route a
rejected trainer may reach besides `/rejected`.
**Exit** Back. The new-ticket sheet stays open until the write succeeds.

### D.11 Appeals (from the suspension gate)

**Route** `/blocked` — no sub-route; the appeal lives inside the gate

**Step order** Gate shows the countdown → **Appeal this decision** → non-dismissible sheet
(reason\*, optional evidence, no cropping) → on success the gate renders the appeal thread
instead of the button.

**State** `_ticker` and `_invalidatedOnLapse` in `_BlockedScreenState`; sheet-local `reason`,
`evidence`, `busy`; `_controller`/`_sending` in the thread.

**Entry** `blocked` stage. **Exit** Two ways out — an admin lifts the suspension (`unblockUser`
restores the *prior* status), or **the ban lapses and the one-minute ticker invalidates the
profile stream**, releasing the user with no restart. Sign-out is the third.

### D.12 Admin console

**Route** `/admin` (root navigator, staff-gated three ways: entry point, router redirect, Firestore rules)

**Step order** Three tabs with live counts.
*APPROVALS* — applicant card → VIEW CERTIFICATE / PROFILE → APPROVE (with UNDO) or DECLINE (reason sheet).
**Approval is what makes a trainer visible in Explore.**
*REPORTS* — report card → RESOLVE sheet → "Uphold & suspend 7 days" (writes a full ISO timestamp) or "Dismiss".
*APPEALS* — appeal card → reply as support (bumps status to `reviewed` unless already `resolved`) → LIFT SUSPENSION.

**State** `_busy` per card; `_reply` controller per appeal card. All lists are `autoDispose`
providers so non-staff never hold them open.
**Entry** Profile ▸ Staff ▸ Admin console (badged with `adminQueueCountProvider`).
**Exit** Back.

### D.13 Profile, settings and account deletion

**Routes** `/profile` → `/profile/edit` · `/notifications` · `/support` · `/admin` · `/trainer/:uid` (own public profile)

**Step order** Identity block → Staff (if staff) → Account → Appearance (theme segmented control,
persisted immediately) → Privacy → Sign out → **Danger zone**.

Deletion is a five-step gate ([profile_screen.dart:259-347](lib/features/profile/profile_screen.dart#L259-L347)):
destructive confirm → leave-reason sheet → **`needsReauthForDeletion` checked before anything is
touched** → heavy haptic → blocking overlay running `recordLeaveReason` → `deleteProfile` →
`deleteAccount`, in that order.

**State** Edit Profile holds a `_snapshot` of the loaded `AppUser`; **Save is disabled until
`_dirty`**; leaving dirty prompts to discard and also intercepts predictive back. The `clear` set
names fields the user deliberately emptied, because a null means "not editing".

**Entry** Profile tab. **Exit** Sign out → `signedOut`; deletion → profile gone → `signedOut`.

### D.14 Cross-cutting: push deep links

`handleTap` ([push_service.dart:96-116](lib/services/push_service.dart#L96-L116)) is an entry
point into D.6, D.7 and D.8 from outside the app entirely — cold start, background tap, or an
in-app snackbar's VIEW action. It reads `type` and `bookingId` from the data payload and forks on
`isTrainer`. It uses `context.go` for bookings and messages but `context.push` for the fallback,
so the back-stack behaviour differs by notification type.

---

## E. Proposed phase order

Presentation only. Bottom-up, so every phase lands on ground the previous one made stable.
**One flow per commit**, per CLAUDE.md. No phase here touches a 🔒 or ⚠️ range from
[section B](#b-mixed-files-line-by-line).

> **All nine phases are done.** Deviations from the plan below, and the things
> deliberately left undone, are recorded in [E.10](#e10-what-was-not-done).

**Phase 1 — Design tokens.**
[lib/core/theme/](lib/core/theme/). Settle the radius scale (14/16/18/20 are currently used
interchangeably), decide whether `onSuccessTint` earns its place, and make `cardTheme` the single
source for card geometry. Nothing else can be deduplicated until the tokens agree.
*Touches:* `app_theme.dart`, `palette.dart`, `typography.dart`. *Unblocks:* every later phase.

**Phase 2 — Card and surface primitives.**
Introduce `FlowCard` (fill + radius + hairline) and a tinted icon-chip widget; fold the six
notice/callout variants into one. *Clears clusters 1, 2, 9 — ~28 call sites.* Largest single win.

**Phase 3 — Pills.**
Fold `StatusPill` and the inline appeal-status pill into `TagPill`, following `PaymentPill`'s
existing pattern. Moves `StatusPill` out of `sessions_screen.dart` and removes the cross-feature
`show StatusPill` import in `command_center_screen.dart`. *Cluster 3.*

**Phase 4 — Buttons and scrim controls.**
One circular scrim button covering `_ScrimButton`, `_RoundButton` and the inline station back
button, with the `active` state `_RoundButton` needs. *Cluster 4.*

**Phase 5 — Empty / error / skeleton family.**
Give `EmptyView` a scrollable variant so the seven `ListView(children: [SizedBox(60), EmptyView])`
wrappers collapse; give the skeletons a shared base; reconcile `crop_screen`'s `_Message`.
*Clusters 8, 16, 21.* **Also proposes relocating `ErrorView.friendly` out of `core/widgets` —
that part needs approval, see [section F](#f-deferred--requires-flow_redesignmd).**

**Phase 6 — Media components.**
One gallery thumbnail (with the NEW badge and the semantics label both variants should have had),
one full-screen viewer, one page-dot indicator, one evidence-attachment sheet body.
*Clusters 5, 12, 13, 20.*

**Phase 7 — Thread components.**
One bubble and one composer serving chat, support and appeals. The three currently disagree on
max-width, timestamps and corner radii. *Cluster 6.* Largest behavioural-surface risk in the
presentation set — do it after the primitives are settled.

**Phase 8 — Gate screens.**
A shared gate scaffold (ink background, `WaveBackdrop`, sign-out action, icon chip, title, body,
wordmark) across `/pending`, `/blocked`, `/rejected` and the role selector. *Cluster 7.*
Sign-out **placement** is a flow question — reuse the existing behaviour verbatim here.

**Phase 9 — Per-screen restyle**, largest first so the shared components get exercised early:
`command_center_screen` (1141) → `booking_screen` (1060) → `trainer_profile_screen` (833) →
`admin_screen` (775) → `schedule_tab` (773) → `sessions_screen` (626) → `explore_screen` (596) →
`trainer_form_screen` (613) → the remainder.

Also fold in the low-risk tidies as they come up: dropping `monthsForChat` for `date_x`'s lists
(cluster 10), `_DateButton` → `InfoTile` (19), the sticky bottom bar (11), the date block (14),
the icon-result dialog (18), `_Step`/`_PrivacyItem` (15), the stat tile (17).

**Verification for every phase:** `flutter analyze` clean, `flutter test` green with the three
suites unmodified, and a visual pass in both light and dark at text scale 0.9 and 1.3.

### E.10 What was not done

Four near-duplicate clusters were left alone. Each is recorded here so the next person
does not re-derive the question:

- **Cluster 15 — `_Step` vs `_PrivacyItem`.** The leading element differs in kind, a
  numeral versus a glyph, and `setup_required_screen` runs in its own `MaterialApp`
  outside the theme. A shared component would be a `ListTile` with two escape hatches.
- **Cluster 17 — stat tile vs earnings cards.** Both live in `command_center_screen.dart`.
  Within-file, not a cross-file duplicate.
- **Cluster 18 — icon-result dialog.** Three sites, but one is the paged tour dialog,
  which is a different thing. The other two already share `FlowIconChip`.
- **Cluster 20 — evidence sheet, report half.** The appeal sheet now uses `ThumbTile`.
  The report sheet still shows only a count and offers **no way to remove a
  mis-picked screenshot at all.** Unifying them hands users a capability they do not
  have today, which is not restyling — so it needs a product decision first.

Three places deliberately keep a different shape, each carrying a comment saying why:

- **Explore's trainer grid tile** stays hand-rolled — borderless with an edge-to-edge
  photo, where `FlowCard`'s hairline would clip to a half-pixel.
- **The notification tile** stays an `AnimatedContainer` — its read/unread tint tweens
  (§10.9), and `FlowCard` paints a plain `Container`, which would make that snap.
- **Dense list rows** pass `FlowRadii.control` explicitly rather than folding up to the
  content radius, so the hierarchy between a row and a card survives.

Radius literals below 8 (bars, dots, drag handles) and proportional ones (`size * .32`)
are not surfaces and stay literal. Everything else in `lib/features` and
`lib/core/widgets` now goes through `FlowRadius`/`FlowRadii`.

---

## F. Deferred — requires FLOW_REDESIGN.md

Real findings that are **not** presentation. None have a phase number. Each needs to be written
up in FLOW_REDESIGN.md and approved before any code moves.

| # | Finding | Status |
|---|---|---|
| 1 | Duplicate scanner path | **Done** — one top-level `runCheckInScan`, guarding on `context.mounted` |
| 2 | `comingUpLimit` not wired | **Done** — the constant is load-bearing |
| 3 | Sign-out placement across gates | **Done in Phase 8** — standardised on the app-bar trailing slot |
| 4 | Notification tap routing | **Done** — `leaveTo()` pops before `go()`. *This was the open product question; option 2 was chosen without an answer, and it is one helper to revert.* |
| 5 | `ErrorView.friendly` in the component library | **Done** — rule moved to `core/utils/error_copy.dart`, delegating alias kept so no call site changed |
| 6 | Trainer form validates twice | **Done** — inline checks deleted, validators are the single source |
| 7 | Dead declarations | **Done** — the four genuinely unreferenced removed; the rest kept, they are test-asserted or documented seams |
| 8 | `/book/:id` requires `extra` | **No action** — unreachable today; recorded as a constraint on future deep-linking |

1. **Duplicate scanner path.** `_openScanner` ([command_center_screen.dart:61](lib/features/command_center/command_center_screen.dart#L61))
   and `_scanToStart` ([:623](lib/features/command_center/command_center_screen.dart#L623)) are
   the same logic twice, differing only in their `mounted` guard. Sharing them changes where
   check-in errors surface.

2. **`comingUpLimit` is not wired.** [constants.dart:116](lib/core/constants.dart#L116) declares
   `10`; [command_center_screen.dart:181](lib/features/command_center/command_center_screen.dart#L181)
   hardcodes `.take(10)`. They agree today. Connecting them is a one-word edit in a **frozen**
   file's consumer and makes the constant load-bearing.

3. **Sign-out placement across gates.** Four copies (cluster 7) with three different positions:
   an `AppBar` action on the role selector, a `ListView`-top `Align` on blocked, a `Column`-top
   `Align` on pending and rejected. Unifying the component is presentation (Phase 8); unifying
   the *placement* is a flow decision.

4. **Notification tap routing.** `_open` ([notifications_screen.dart:98-138](lib/features/notifications/notifications_screen.dart#L98-L138))
   uses `context.go`, which replaces the notification screen rather than pushing over it — so
   Back after tapping a notification does not return to the list. `handleTap`
   ([push_service.dart:96-116](lib/services/push_service.dart#L96-L116)) makes the same fork with
   `go` for bookings and `push` for the fallback. Two forks, one rule, inconsistent stack behaviour.

5. **`ErrorView.friendly` lives in the component library.**
   [feedback.dart:66-79](lib/core/widgets/feedback.dart#L66-L79) maps Firestore error codes to
   user copy — business logic inside `core/widgets`. Moving it (e.g. beside `AuthRepository.message`)
   is the right shape but crosses the frozen boundary.

6. **Trainer form step 1 validates twice, differently.**
   `_nameError`/`_bioError` ([trainer_form_screen.dart:81-84](lib/features/onboarding/trainer_form_screen.dart#L81-L84))
   gate Continue via `_step1Ok`, but the inline messages at
   [:329](lib/features/onboarding/trainer_form_screen.dart#L329) and
   [:342](lib/features/onboarding/trainer_form_screen.dart#L342) re-implement their own checks
   (`length <= 2`, `isEmpty`) that do not match the validators. Three concrete divergences —
   see [FLOW_REDESIGN.md](FLOW_REDESIGN.md) F6 for the full table. `kiter_form_screen` already
   does this correctly: one getter per field, used by both the gate and the message.



7. **Dead declarations in frozen files.** See [C.3](#c3-dead-or-unwired-declarations). Only four
   are genuinely unreferenced (`comingUpLimit`, `watchProfile`, `watchAllBlocks`, `onSuccessTint`);
   the rest are asserted by the frozen tests or are documented seams for a future payment
   processor and must stay. Removing even the four touches frozen files.

8. **`/book/:id` requires `extra`.** [router.dart:214](lib/router.dart#L214) casts
   `state.extra as BookingTarget` unconditionally. **Currently unreachable** — the manifest
   declares no deep-link intent filters (MAIN/LAUNCHER only) and no `restorationScopeId` is set,
   so `extra` can never arrive null. Recorded as a constraint on any future deep-linking work,
   not as a live defect.
