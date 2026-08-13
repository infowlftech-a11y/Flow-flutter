// Every shared component at both ends of the text-scale clamp, on a 320px
// phone — failing on any layout overflow.
//
// This is the cheapest guard the component library has. Text scale is exactly
// the axis nobody checks by hand, and a component that overflows at 1.3x looks
// fine to whoever wrote it at 1.0x. It caught nothing when the spacing scale
// was normalised, which is the point: it is the reason that change could be
// made across 250 call sites without opening the app.
//
// It ran the same matrix in both themes until dark mode was removed.
//
// Add a case here whenever a component is added to lib/core/widgets/.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flow/core/theme/app_theme.dart';
import 'package:flow/core/theme/palette.dart';
import 'package:flow/core/widgets/booking_grid.dart';
import 'package:flow/core/widgets/buttons.dart';
import 'package:flow/core/widgets/charts.dart';
import 'package:flow/core/widgets/dashboard.dart';
import 'package:flow/core/widgets/conditions.dart';
import 'package:flow/core/widgets/feedback.dart';
import 'package:flow/core/widgets/provider_card.dart';
import 'package:flow/core/widgets/session_card.dart';
import 'package:flow/core/widgets/ticket.dart';
import 'package:flow/data/models/wind.dart';
import 'package:flow/core/widgets/gate.dart';
import 'package:flow/core/widgets/loader.dart';
import 'package:flow/core/widgets/media.dart';
import 'package:flow/core/widgets/misc.dart';
import 'package:flow/core/widgets/picker_field.dart';
import 'package:flow/core/widgets/surfaces.dart';
import 'package:flow/core/widgets/thread.dart';

/// Long enough to wrap hard at 1.3 on a 320 px phone.
const _long =
    'Your account was suspended by our moderation team and this sentence '
    'exists to make the text wrap several times over.';

final _cases = <String, Widget Function()>{
  // Pumped mid-animation: the harness's fixed pumps land it partway through
  // a revolution, which is the state it actually ships in.
  'FlowLoader': () => const Center(child: FlowLoader()),
  'FlowCard': () => const FlowCard(child: Text(_long)),
  'FlowCard.onTap': () => FlowCard(onTap: () {}, child: const Text(_long)),
  // Three metrics on a 320px phone at 1.3x is the case this component is most
  // likely to fail: each is an icon plus a stacked label and value, and they
  // share the width equally.
  'ConditionsStrip': () => const ConditionsStrip(
    day: WindDay(
      date: '2026-05-13',
      knots: 18,
      gustKnots: 24,
      directionDegrees: 315,
      airC: 28,
      waterC: 26,
    ),
  ),
  // Wind only — the shape when the marine grid has no coverage.
  'ConditionsStrip.windOnly': () => const ConditionsStrip(
    day: WindDay(
      date: '2026-05-13',
      knots: 18,
      gustKnots: 24,
      directionDegrees: 315,
    ),
  ),
  'ProviderCard': () => ProviderCard(
    name: 'Konstantinos Papadopoulos',
    photoUrl: null,
    rating: 4.9,
    reviewCount: 128,
    location: 'El Gouna, Red Sea',
    priceLabel: '€110',
    onTap: () {},
  ),
  'ProviderCard.bare': () =>
      ProviderCard(name: 'Marco B.', photoUrl: null, onTap: () {}),
  // Enough values to wrap the tag row twice on a 320px phone at 1.3x.
  'FlowPickerField.tags': () => FlowPickerField(
    values: const ['English', 'German', 'Arabic', 'Portuguese'],
    onChanged: (_) {},
    options: const ['English', 'German', 'Arabic', 'Portuguese'],
    sheetTitle: 'Languages',
    multiSelect: true,
  ),
  'FlowPickerField.empty': () => FlowPickerField(
    values: const [],
    onChanged: (_) {},
    options: const ['El Gouna'],
    sheetTitle: 'Home spot',
    hintText: 'Where you ride most',
  ),
  // Three across a 320 phone is the narrowest each tile ever gets, and the
  // longest state word ("Unavailable") is the one that has to survive it.
  'SlotTile.grid': () => GridView.count(
    crossAxisCount: 3,
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    childAspectRatio: 1.55,
    mainAxisSpacing: 8,
    crossAxisSpacing: 8,
    children: [
      for (final s in SlotState.values)
        SlotTile(range: '09:00 – 10:00', state: s, onTap: () {}),
    ],
  ),
  'SlotLegend': () => const SlotLegend(),
  'WeekBars': () => WeekBars(
    bars: [
      for (final d in ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'])
        WeekBar(
          label: d,
          value: d == 'Wed' ? 320 : 90,
          semanticValue: d == 'Wed' ? '€3,200' : '€900',
          highlighted: d == 'Wed',
        ),
    ],
  ),
  // A week of zeroes is a real state, not an error — it must not render as
  // seven flat stubs.
  'WeekBars.empty': () => const WeekBars(
    bars: [
      WeekBar(label: 'Mon', value: 0, semanticValue: '€0'),
      WeekBar(label: 'Tue', value: 0, semanticValue: '€0'),
      WeekBar(label: 'Wed', value: 0, semanticValue: '€0'),
    ],
  ),
  'AgendaRow.live': () => AgendaRow(
    time: '10:00',
    name: 'Annelies van der Berg-Hoekstra',
    live: true,
    onTap: () {},
  ),
  'AgendaRow': () => AgendaRow(
    time: '12:00',
    name: 'Ahmed K.',
    statusLabel: 'Upcoming',
    onTap: () {},
  ),
  'RequestRow': () => RequestRow(
    when: 'Tomorrow, 09:00 - 10:00',
    name: 'Nicolas P.',
    location: 'El Gouna',
    onApprove: () {},
    onDecline: () {},
  ),
  'TicketCard': () => const TicketCard(
    payload: '{"bookingId":"seed-lina-omar-next","trainerId":"omar"}',
    qrSize: 140,
    ticketId: 'FLW-13MAY-10AM-7X8K',
    rows: [
      ('SESSION', '13 May 2026 · 10:00 – 11:00'),
      ('INSTRUCTOR', 'Konstantinos Papadopoulos'),
      ('SPOT', 'El Gouna, Red Sea'),
    ],
  ),
  'LiveSessionCard': () => LiveSessionCard(
    title: 'Today, 13 May · 10:00 – 11:00',
    subtitle: 'with Konstantinos Papadopoulos · El Gouna, Red Sea',
    badgeLabel: 'LIVE NOW',
    countdownTo: DateTime.now().add(const Duration(minutes: 32)),
    onTap: () {},
  ),
  'LiveSessionCard.bare': () => LiveSessionCard(
    title: 'Wed, 14 May · 09:00 – 11:00',
    subtitle: 'with Nadia Cherif',
    onTap: () {},
  ),
  'SessionRow': () => SessionRow(
    when: 'Tue, 13 May · 12:00 – 13:00',
    who: 'Konstantinos Papadopoulos',
    location: 'El Gouna',
    priceLabel: '€110',
    statusLabel: 'UPCOMING',
    onTap: () {},
  ),
  'WeekStrip': () => WeekStrip(
    days: [for (var i = 0; i < 21; i++) DateTime(2026, 5, 13 + i)],
    selected: DateTime(2026, 5, 13),
    onSelect: (_) {},
  ),
  'FlowIconChip': () => const FlowIconChip(icon: Icons.air_rounded, size: 88),
  'FlowNotice': () => const FlowNotice(
    icon: Icons.warning_amber_rounded,
    title: 'Away',
    body: _long,
  ),
  'TagPill': () => const Wrap(
    children: [TagPill('CONFIRMED'), TagPill('AWAITING PAYMENT', dense: true)],
  ),
  'ScrimIconButton': () => ScrimIconButton(
    icon: Icons.close_rounded,
    tooltip: 'Close',
    onTap: () {},
  ),
  'EmptyView': () => const EmptyView(
    icon: Icons.forum_outlined,
    title: 'No conversations',
    subtitle: _long,
  ),
  'EmptyView.scrollable': () => const EmptyView.scrollable(
    icon: Icons.forum_outlined,
    title: 'No conversations',
    subtitle: _long,
  ),
  'EmptyView.onScrim': () => const ColoredBox(
    color: Colors.black,
    child: EmptyView(
      onScrim: true,
      icon: Icons.no_photography_outlined,
      title: 'Camera unavailable',
      subtitle: _long,
    ),
  ),
  'ErrorView': () => ErrorView(error: 'permission-denied', onRetry: () {}),
  'SkeletonCard': () => const SkeletonCard(),
  'SkeletonList': () => const SkeletonList(count: 2),
  'SkeletonGrid': () => const SkeletonGrid(
    count: 2,
    shrinkWrap: true,
    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3),
    tile: SkeletonPulse(height: 999),
  ),
  'ChatBubble.mine': () => const ChatBubble(text: _long, mine: true),
  'ChatBubble.theirs': () => const ChatBubble(
    text: _long,
    mine: false,
    header: Text('FLOW SUPPORT'),
    footer: Text('2h ago'),
  ),
  'ChatBubble.run': () => const Column(
    children: [
      ChatBubble(text: 'first', mine: true, lastOfRun: false),
      ChatBubble(
        text: 'middle',
        mine: true,
        firstOfRun: false,
        lastOfRun: false,
      ),
      ChatBubble(text: 'last', mine: true, firstOfRun: false),
    ],
  ),
  'MessageComposer': () =>
      MessageComposer(controller: TextEditingController(), onSend: () {}),
  'ComposerField.busy': () => ComposerField(
    controller: TextEditingController(),
    onSend: () {},
    busy: true,
  ),
  'StickyBar': () => const StickyBar(child: Text(_long)),
  'PageDots': () => const PageDots(count: 4, index: 1),
  'ThumbTile': () => ThumbTile(
    onRemove: () {},
    isNew: true,
    child: Container(width: 84, height: 84, color: Colors.grey),
  ),
  'InfoTile': () => const InfoTile(
    icon: Icons.place_outlined,
    label: 'Location',
    value: 'El Gouna',
  ),
  'InfoTile.noIcon': () => InfoTile(
    label: 'FROM',
    value: 'Wednesday, 12 August',
    trailingIcon: Icons.edit_calendar_outlined,
    onTap: () {},
  ),
  'DateBlock': () => Row(
    children: [
      DateBlock(date: DateTime(2026, 8, 8)),
      const DateBlock(date: null, compact: true),
    ],
  ),
  'GateHeadline': () => const GateHeadline(
    icon: Icons.front_hand_rounded,
    color: FlowColors.coral,
    title: 'Application not approved',
    body: _long,
  ),
  // The point of ScrollableFill is that a Spacer keeps working inside it —
  // that is the whole reason it is not a bare SingleChildScrollView, which
  // hands its child unbounded height and makes any flex child throw.
  'ScrollableFill': () => ScrollableFill(
    child: Column(
      children: [
        const Spacer(),
        const Text(_long),
        const Spacer(),
        PrimaryButton(label: 'Create account', onPressed: () {}),
      ],
    ),
  ),
};

/// Cases that own a scrollable and must not be nested inside another.
const _selfScrolling = {
  'EmptyView.scrollable',
  'SkeletonList',
  'ScrollableFill',
};

void main() {
  // 320x640 is the smallest phone the app realistically meets; 1.3 on top of
  // that is the worst case a rider actually hits.
  for (final scale in [0.9, 1.3]) {
    {
      // This loop ran each case in both themes. There is one theme now, so the
      // brightness axis is gone and the text-scale axis is the whole matrix.
      final label = '@${scale}x';

      _cases.forEach((name, build) {
        testWidgets('$name — $label', (tester) async {
          tester.view.physicalSize = const Size(320, 640);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          await tester.pumpWidget(
            MaterialApp(
              theme: FlowTheme.light(),
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

          expect(
            tester.takeException(),
            isNull,
            reason: '$name overflowed or threw at $label',
          );
        });
      });

      // The gate scaffold owns a Scaffold, so it is pumped as the whole page.
      testWidgets('GateScaffold — $label', (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MaterialApp(
            theme: FlowTheme.light(),
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: GateScaffold(
                onSignOut: () {},
                child: const Column(
                  children: [
                    Spacer(),
                    GateHeadline(
                      icon: Icons.hourglass_top_rounded,
                      color: FlowColors.azure,
                      title: 'Under review',
                      body: _long,
                    ),
                    Spacer(flex: 2),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          tester.takeException(),
          isNull,
          reason: 'GateScaffold overflowed or threw at $label',
        );
      });
    }
  }
}
