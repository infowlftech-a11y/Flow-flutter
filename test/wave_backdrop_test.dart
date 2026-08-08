// The backdrop must not move when the keyboard opens.
//
// The Scaffold in this test is not scenery. An earlier version of this test
// wrapped WaveBackdrop in a hand-made MediaQuery, and that is what let a
// non-fix look proven: a Scaffold that resizes for the keyboard reports
// viewInsets.bottom to its body as 0, having already spent it on the shrink.
// The test's own MediaQuery cheerfully reported 300, so it passed while the
// app was unchanged. Any future rework of this must keep the real Scaffold.
//
// Screen is 400x800 with a 300px keyboard, so the body is 800 tall without one
// and 500 with. The first swell sits at 78% of the box the painter thinks it
// has:
//
//   correct -> .78 * 800 = 624, below the form and behind the keyboard
//   buggy   -> .78 * 500 = 390, straight across the CTA
//
// So y=420 is bare ink only when the fix is live, and y=700 with no keyboard
// confirms there is a swell to miss in the first place.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flow/core/theme/app_theme.dart';
import 'package:flow/core/theme/palette.dart';
import 'package:flow/core/theme/typography.dart';
import 'package:flow/core/widgets/brand.dart';
import 'package:flow/features/auth/auth_widgets.dart';

const _boundary = Key('probe');

Future<ui.Image> _render(
    WidgetTester tester, double keyboard, Widget home) async {
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _boundary,
      // Explicitly the dark theme: the backdrop follows brightness now, so a
      // test that left the theme to chance would be asserting against
      // whatever Material's default happened to be.
      child: MaterialApp(theme: FlowTheme.dark(), home: home),
    ),
  );
  await tester.pump();
  return tester
      .renderObject<RenderRepaintBoundary>(find.byKey(_boundary))
      .toImage();
}

/// The shape AuthScaffold puts the backdrop in: body of a Scaffold that
/// resizes for the keyboard. That Scaffold is the whole point of the test.
Widget get _bareScaffold => Scaffold(
      backgroundColor: FlowColors.ink,
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
      extendBodyBehindAppBar: true,
      body: const WaveBackdrop(child: SizedBox.expand()),
    );

/// The screen as shipped. Sampled at x=10, left of the 28px content padding,
/// so nothing but the backdrop can paint there.
Widget get _signInLikeScreen => AuthScaffold(
      title: 'Welcome back',
      subtitle: 'Sign in to pick up where you left off.',
      footer: Text('New to FLOW?', style: inter(14, 460)),
      children: [
        AuthTextField(
          label: 'Email',
          controller: TextEditingController(),
          focusNode: FocusNode(),
        ),
        AuthTextField(
          label: 'Password',
          controller: TextEditingController(),
          focusNode: FocusNode(),
          obscure: true,
        ),
      ],
    );

Future<Color> _pixel(ui.Image image, int x, int y) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final i = (y * image.width + x) * 4;
  return Color.fromARGB(
    data!.getUint8(i + 3),
    data.getUint8(i),
    data.getUint8(i + 1),
    data.getUint8(i + 2),
  );
}

void main() {
  testWidgets('swell stays out of the form when the keyboard opens',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late Color swellWithNoKeyboard;
    late Color formAreaWithKeyboard;

    await tester.runAsync(() async {
      swellWithNoKeyboard =
          await _pixel(await _render(tester, 0, _bareScaffold), 200, 700);
      formAreaWithKeyboard =
          await _pixel(await _render(tester, 300, _bareScaffold), 200, 420);
    });

    expect(swellWithNoKeyboard, isNot(equals(FlowColors.ink)),
        reason: 'expected a swell at y=700 with no keyboard');
    expect(formAreaWithKeyboard, equals(FlowColors.ink),
        reason: 'swell climbed into the form when the keyboard opened');
  });

  testWidgets('the sign-in screen itself keeps its form clear of the swell',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late Color swellWithNoKeyboard;
    late Color formAreaWithKeyboard;

    await tester.runAsync(() async {
      swellWithNoKeyboard =
          await _pixel(await _render(tester, 0, _signInLikeScreen), 10, 700);
      formAreaWithKeyboard =
          await _pixel(await _render(tester, 300, _signInLikeScreen), 10, 420);
    });

    expect(swellWithNoKeyboard, isNot(equals(FlowColors.ink)),
        reason: 'expected a swell at y=700 with no keyboard');
    expect(formAreaWithKeyboard, equals(FlowColors.ink),
        reason: 'swell climbed into the form when the keyboard opened');
  });
}
