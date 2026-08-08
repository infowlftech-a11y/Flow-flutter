UI/UX REFACTOR — ACTIVE

This is a Flutter app. Zones are defined by **layer, not path** — a single
screen file routinely contains all three. `REFACTOR_PLAN.md` §A classifies
every file and §B gives the line ranges inside the 34 mixed ones.

FROZEN (never modify):
- Business rules: lib/data/models, lib/data/repositories, lib/services,
  lib/data/firestore_paths.dart, lib/core/constants.dart,
  lib/core/utils/date_x.dart, lib/core/utils/doc_x.dart,
  lib/core/utils/error_copy.dart
- The validators, wherever they sit: lib/features/auth/auth_validators.dart,
  lib/features/onboarding/onboarding_validators.dart — test/ asserts their
  exact strings
- Schema, migrations, env config: firestore.rules, lib/firebase_options.dart,
  lib/core/firebase_config.dart
- Existing tests (they must pass unmodified)

CHANGEABLE WITH APPROVAL:
- Flow & state: routing, step order, what persists between steps
- lib/router.dart, lib/providers/, lib/features/auth/auth_controller.dart,
  lib/features/shell/app_shell.dart, lib/main.dart, lib/app.dart, and the
  `State` fields + lifecycle methods of every stateful screen
- Must appear in FLOW_REDESIGN.md and be approved before implementing

FREE:
- Presentation: lib/core/theme/, lib/core/widgets/, and `build()` bodies plus
  private widget classes throughout lib/features/

OUT OF SCOPE:
- lib/dev/ — separate seed_app.dart entry point, not in main.dart's import
  graph. Not deletable: test/core_logic_test.dart imports seed_data.dart.

RULES:
- If a UI change seems to require a logic change, STOP and ask.
- Never introduce a flow change silently while restyling.
- One flow per commit.

CONVENTIONS ESTABLISHED BY THE REFACTOR:
- Corner radii come from lib/core/theme/radii.dart. Do not write
  `BorderRadius.circular(n)` for a surface — pick the semantic step. Values
  below 8 (bars, dots, drag handles) and proportional ones (`size * .32`) are
  not surfaces and stay literal.
- Card surfaces are `FlowCard` (lib/core/widgets/surfaces.dart), not a
  hand-rolled `Container` + `BoxDecoration`.
- An empty state inside a refreshable list is `EmptyView.scrollable`, never a
  bare `ListView` wrapper — the wrapper silently kills pull-to-refresh.
- Transition durations come from lib/core/theme/motion.dart: `fast` for a
  control reacting under the finger, `base` for anything changing in place,
  `slow` for content arriving or leaving, `pulse` for loops. Pass
  `FlowMotion.curve` to any Animated* widget that would otherwise default to
  `Curves.linear`. Debounces, `Future.delayed`, scroll/page travel and the
  route transition are NOT motion tokens — they are tuned to other things.
- Spacing sits on a 4pt grid: 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 24, 28, 32.
  3 is the one deliberate exception — the hairline gap between a label and its
  value. Anything off-grid is drift; there is no constant to import, the grid
  is the convention.
- Colours come from `context.scheme` / `context.tones`, never from
  `FlowColors.*` directly. The palette is raw pigment; the tones are what has
  been tuned per brightness. The exceptions are surfaces that are dark in both
  themes because they sit over a photo or the camera: image viewers, the QR
  scanner, `EmptyView(onScrim: true)`, and the cropper's dimming overlay.
- Anything decoded from the network goes through `FlowImage`/`FlowAvatar`,
  which size the decode to the box. A bare `Image.network` decodes the full
  1600px source whatever it is drawn at.
- A label painted on a tint of its own tone uses `tones.onTint(tone)`, not the
  tone itself. On a dark card the two are identical; on white a 14% tint barely
  moves the background, so the text has to carry the whole ratio and the raw
  tone measures ~3.6:1. Pills and the date block go through it.
- Anything tappable is at least 48x48 and carries a semantic label. Where a
  bigger control would crowd the design (the remove puck on a photo thumb),
  keep the visual small and grow the hit box with a `SizedBox` +
  `HitTestBehavior.opaque` — never shrink the target to fit the art. Note that
  a `Border` insets its child, so a `minHeight` on a decorated `Container`
  yields a tap target 2px smaller than the number you wrote; constrain the
  InkWell's child instead.

TESTS THAT EXIST TO CATCH SPECIFIC MISTAKES (read the header before editing):
- test/component_render_test.dart — every shared component, both themes, text
  scale 0.9 and 1.3, fails on overflow. Add a case when you add a component.
- test/text_contrast_test.dart — runs Flutter's WCAG AA guideline over the
  real render of every text-bearing component, both themes. Catches what the
  token maths cannot: text over a tint over a card.
- test/theme_contrast_test.dart — measures WCAG contrast per theme and fails
  if a token reads twice as well in one brightness as the other.
- test/image_decode_size_test.dart — asserts images are decoded at display
  size, on one axis only.
- test/wave_backdrop_test.dart — the backdrop must not move when the keyboard
  opens. Its header explains why the Scaffold in it is load-bearing.
- test/tap_target_test.dart — runs Flutter's own iOS/Android tap-target and
  labelled-tappable guidelines over every interactive component.
- test/onboarding_rebuild_test.dart — inline validation must stay live after
  the first submit, which is what the per-keystroke rebuild guard could break.
- test/auth_layout_test.dart — the auth CTA must stay reachable and uncut with
  the keyboard up, including at 1.3x text.
