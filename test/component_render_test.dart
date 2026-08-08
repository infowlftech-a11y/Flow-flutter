// Every shared component, in both themes, at both ends of the text-scale
// clamp, on a 320px phone — failing on any layout overflow.
//
// This is the cheapest guard the component library has. Text scale and theme
// are exactly the two axes that nobody checks by hand, and a component that
// overflows at 1.3x looks fine to whoever wrote it at 1.0x. It caught nothing
// when the spacing scale was normalised, which is the point: it is the reason
// that change could be made across 250 call sites without opening the app.
//
// Add a case here whenever a component is added to lib/core/widgets/.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flow/core/theme/app_theme.dart';
import 'package:flow/core/theme/palette.dart';
import 'package:flow/core/widgets/buttons.dart';
import 'package:flow/core/widgets/feedback.dart';
import 'package:flow/core/widgets/gate.dart';
import 'package:flow/core/widgets/media.dart';
import 'package:flow/core/widgets/misc.dart';
import 'package:flow/core/widgets/surfaces.dart';
import 'package:flow/core/widgets/thread.dart';

/// Long enough to wrap hard at 1.3 on a 320 px phone.
const _long =
    'Your account was suspended by our moderation team and this sentence '
    'exists to make the text wrap several times over.';

final _cases = <String, Widget Function()>{
  'FlowCard': () => const FlowCard(child: Text(_long)),
  'FlowCard.onTap': () => FlowCard(onTap: () {}, child: const Text(_long)),
  'FlowIconChip': () => const FlowIconChip(icon: Icons.air_rounded, size: 88),
  'FlowNotice': () =>
      const FlowNotice(icon: Icons.warning_amber_rounded, title: 'Away', body: _long),
  'TagPill': () => const Wrap(children: [
        TagPill('CONFIRMED'),
        TagPill('AWAITING PAYMENT', dense: true),
      ]),
  'ScrimIconButton': () => ScrimIconButton(
      icon: Icons.close_rounded, tooltip: 'Close', onTap: () {}),
  'EmptyView': () => const EmptyView(
      icon: Icons.forum_outlined, title: 'No conversations', subtitle: _long),
  'EmptyView.scrollable': () => const EmptyView.scrollable(
      icon: Icons.forum_outlined, title: 'No conversations', subtitle: _long),
  'EmptyView.onScrim': () => const ColoredBox(
        color: Colors.black,
        child: EmptyView(
            onScrim: true,
            icon: Icons.no_photography_outlined,
            title: 'Camera unavailable',
            subtitle: _long),
      ),
  'ErrorView': () => ErrorView(error: 'permission-denied', onRetry: () {}),
  'SkeletonCard': () => const SkeletonCard(),
  'SkeletonList': () => const SkeletonList(count: 2),
  'SkeletonGrid': () => const SkeletonGrid(
        count: 2,
        shrinkWrap: true,
        gridDelegate:
            SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3),
        tile: SkeletonPulse(height: 999),
      ),
  'ChatBubble.mine': () => const ChatBubble(text: _long, mine: true),
  'ChatBubble.theirs': () => const ChatBubble(
        text: _long,
        mine: false,
        header: Text('FLOW SUPPORT'),
        footer: Text('2h ago'),
      ),
  'ChatBubble.run': () => const Column(children: [
        ChatBubble(text: 'first', mine: true, lastOfRun: false),
        ChatBubble(
            text: 'middle', mine: true, firstOfRun: false, lastOfRun: false),
        ChatBubble(text: 'last', mine: true, firstOfRun: false),
      ]),
  'MessageComposer': () =>
      MessageComposer(controller: TextEditingController(), onSend: () {}),
  'ComposerField.busy': () => ComposerField(
      controller: TextEditingController(), onSend: () {}, busy: true),
  'StickyBar': () => const StickyBar(child: Text(_long)),
  'PageDots': () => const PageDots(count: 4, index: 1),
  'ThumbTile': () => ThumbTile(
      onRemove: () {},
      isNew: true,
      child: Container(width: 84, height: 84, color: Colors.grey)),
  'InfoTile': () => const InfoTile(
      icon: Icons.place_outlined, label: 'Location', value: 'El Gouna'),
  'InfoTile.noIcon': () => InfoTile(
      label: 'FROM',
      value: 'Wednesday, 12 August',
      trailingIcon: Icons.edit_calendar_outlined,
      onTap: () {}),
  'DateBlock': () => Row(children: [
        DateBlock(date: DateTime(2026, 8, 8)),
        const DateBlock(date: null, compact: true),
      ]),
  'GateHeadline': () => const GateHeadline(
      icon: Icons.front_hand_rounded,
      color: FlowColors.coral,
      title: 'Application not approved',
      body: _long),
};

/// Cases that own a scrollable and must not be nested inside another.
const _selfScrolling = {'EmptyView.scrollable', 'SkeletonList'};

void main() {
  // 320x640 is the smallest phone the app realistically meets; 1.3 on top of
  // that is the worst case a rider actually hits.
  for (final scale in [0.9, 1.3]) {
    for (final dark in [false, true]) {
      final label = '${dark ? 'dark' : 'light'} @${scale}x';

      _cases.forEach((name, build) {
        testWidgets('$name — $label', (tester) async {
          tester.view.physicalSize = const Size(320, 640);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          await tester.pumpWidget(
            MaterialApp(
              theme: dark ? FlowTheme.dark() : FlowTheme.light(),
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Scaffold(
                  body: _selfScrolling.contains(name)
                      ? build()
                      : SingleChildScrollView(child: build()),
                ),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 300));

          expect(tester.takeException(), isNull,
              reason: '$name overflowed or threw at $label');
        });
      });

      // The gate scaffold owns a Scaffold, so it is pumped as the whole page.
      testWidgets('GateScaffold — $label', (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? FlowTheme.dark() : FlowTheme.light(),
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: GateScaffold(
                onSignOut: () {},
                child: const Column(children: [
                  Spacer(),
                  GateHeadline(
                    icon: Icons.hourglass_top_rounded,
                    color: FlowColors.azure,
                    title: 'Under review',
                    body: _long,
                  ),
                  Spacer(flex: 2),
                ]),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));

        expect(tester.takeException(), isNull,
            reason: 'GateScaffold overflowed or threw at $label');
      });
    }
  }
}
