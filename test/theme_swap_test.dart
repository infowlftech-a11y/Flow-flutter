// ThemeSwap replaces MaterialApp's per-tick theme lerp with a one-frame snap
// hidden under a fading screenshot. Two things must never regress:
//
//  1. The swap callback ALWAYS runs — the fade is garnish, and a capture
//     failure must degrade to an instant switch, not a dead toggle.
//  2. The shroud leaves. A screenshot that never fades out would freeze the
//     whole app under an inert image, which no other test would notice.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flow/core/theme/motion.dart';
import 'package:flow/core/widgets/theme_swap.dart';

void main() {
  testWidgets('run() swaps, shows the shroud, and removes it', (tester) async {
    var dark = false;
    late StateSetter rebuild;
    await tester.pumpWidget(
      ThemeSwap(
        child: StatefulBuilder(builder: (context, setState) {
          rebuild = setState;
          // expand: a bare ColoredBox in a Stack sizes to zero, and a
          // zero-sized boundary is the no-capture path, not this test.
          return SizedBox.expand(
              child: ColoredBox(color: dark ? Colors.black : Colors.white));
        }),
      ),
    );

    final state = tester.state<ThemeSwapState>(find.byType(ThemeSwap));
    // toImage rasterizes through real async plumbing — fake time hangs it.
    await tester.runAsync(() => state.run(() => rebuild(() => dark = true)));

    expect(dark, isTrue, reason: 'the theme change itself must have run');
    await tester.pump();
    expect(find.byType(RawImage), findsOneWidget,
        reason: 'old frame should be shrouding the new theme');

    // The shroud must be gone once the fade completes.
    await tester.pump(FlowMotion.base + const Duration(milliseconds: 16));
    expect(find.byType(RawImage), findsNothing);
  });

  testWidgets('a failed capture still swaps, with no shroud', (tester) async {
    var swapped = false;
    await tester.pumpWidget(
      // Offstage: laid out but never painted, so the boundary has no layer
      // and toImage throws — the exact "capture is garnish" degradation path.
      Offstage(
        offstage: true,
        child: ThemeSwap(child: const SizedBox.expand()),
      ),
    );
    final state = tester.state<ThemeSwapState>(
        find.byType(ThemeSwap, skipOffstage: false));
    await tester.runAsync(() => state.run(() => swapped = true));
    await tester.pump();
    expect(swapped, isTrue, reason: 'a dead toggle is the one forbidden outcome');
    expect(find.byType(RawImage), findsNothing);
  });
}
