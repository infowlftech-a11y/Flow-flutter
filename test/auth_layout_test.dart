// The auth screens have to stay usable with the keyboard up.
//
// The footer used to be pinned below a fixed-height scroll view, so once the
// keyboard claimed half the screen the viewport ended mid-button: the Sign in
// CTA was sliced horizontally with "New to FLOW?" sitting underneath it. It
// was reachable by scrolling, but it read as broken, which for the primary
// action on the front door is much the same thing.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flow/core/theme/app_theme.dart';
import 'package:flow/core/widgets/buttons.dart';
import 'package:flow/features/auth/auth_widgets.dart';

Widget _screen() => MaterialApp(
      theme: FlowTheme.dark(),
      home: AuthScaffold(
        title: 'Welcome back',
        subtitle: 'Sign in to pick up where you left off.',
        footer: TextButton(onPressed: () {}, child: const Text('New to FLOW?')),
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
          const SizedBox(height: 10),
          PrimaryButton(label: 'Sign in', onPressed: _noop),
        ],
      ),
    );

void _noop() {}

void main() {
  const screen = Size(400, 800);
  const keyboard = 300.0;

  Future<void> pump(WidgetTester tester, double inset) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1.0;
    tester.view.viewInsets = FakeViewPadding(bottom: inset);
    await tester.pumpWidget(_screen());
    await tester.pumpAndSettle();
  }

  testWidgets('with no keyboard the footer rests at the bottom',
      (tester) async {
    addTearDown(tester.view.reset);
    await pump(tester, 0);

    final footer = tester.getRect(find.text('New to FLOW?'));
    expect(footer.bottom, greaterThan(screen.height - 80),
        reason: 'the footer floated up into the form instead of resting at '
            'the bottom of the screen');
  });

  testWidgets('with the keyboard up the CTA can be brought fully into view',
      (tester) async {
    addTearDown(tester.view.reset);
    await pump(tester, keyboard);

    // Scroll to the end, as a user reaching for the button would.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await tester.pumpAndSettle();

    final visibleBottom = screen.height - keyboard;
    final cta = tester.getRect(find.widgetWithText(PrimaryButton, 'Sign in'));

    expect(cta.top, greaterThanOrEqualTo(0.0));
    expect(cta.bottom, lessThanOrEqualTo(visibleBottom),
        reason: 'the Sign in button is still cut off by the bottom of the '
            'viewport with the keyboard open');
  });

  testWidgets('nothing overflows at either inset', (tester) async {
    addTearDown(tester.view.reset);
    await pump(tester, 0);
    expect(tester.takeException(), isNull);
    await pump(tester, keyboard);
    expect(tester.takeException(), isNull);
  });

  testWidgets('holds at the largest text scale the app allows', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1.0;
    tester.view.viewInsets = const FakeViewPadding(bottom: keyboard);

    // The app clamps scaling to 1.3 (FlowConst.maxTextScale). At that size the
    // content is taller than the viewport, which is the case where the Spacer
    // has to collapse rather than force an overflow.
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
      child: _screen(),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
