// The shell's branch cross-fade must actually finish.
//
// P12 replaced IndexedStack's hard cut with AnimatedOpacity per branch, and
// muted every non-current branch's ticker for battery. Muting is correct at
// rest and wrong in the same frame the branch stops being current: the
// fade-out runs on the ticker that was just muted, so it froze at fully
// opaque. Branches paint in declaration order — Profile is last — so leaving
// Profile left its frozen frame over every other tab while the bar kept
// selecting and taps kept landing underneath: "the app stucks and does not
// go to any other page". These tests fail on that exact code.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flow/features/shell/app_shell.dart';

Widget _harness(int index) => MaterialApp(
  home: AnimatedBranchContainer(
    currentIndex: index,
    children: const [
      ColoredBox(key: ValueKey('first'), color: Colors.red),
      ColoredBox(key: ValueKey('last'), color: Colors.blue),
    ],
  ),
);

double _opacityOf(WidgetTester tester, String key) => tester
    .widget<FadeTransition>(
      find
          .ancestor(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(FadeTransition),
          )
          .first,
    )
    .opacity
    .value;

void main() {
  testWidgets('leaving the last branch fades it fully out', (tester) async {
    await tester.pumpWidget(_harness(1));
    await tester.pumpAndSettle();
    expect(_opacityOf(tester, 'last'), 1);

    // Switch to the earlier branch — the one the frozen fade painted over.
    await tester.pumpWidget(_harness(0));
    await tester.pumpAndSettle();

    expect(
      _opacityOf(tester, 'last'),
      0,
      reason:
          'the outgoing branch was muted before its fade-out ran, so its '
          'stale frame stayed opaque on top of every other tab',
    );
    expect(_opacityOf(tester, 'first'), 1);
  });

  testWidgets('a settled non-current branch is ticker-muted again', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(1));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_harness(0));
    await tester.pumpAndSettle();

    // The battery contract: once the exit fade has finished, the invisible
    // branch must not animate.
    final muted = tester.widget<TickerMode>(
      find
          .ancestor(
            of: find.byKey(const ValueKey('last')),
            matching: find.byType(TickerMode),
          )
          .first,
    );
    expect(
      muted.enabled,
      isFalse,
      reason: 'an invisible branch that still ticks is a battery drain',
    );
  });
}
