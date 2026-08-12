// Rendered text contrast. Ran every case in both themes until dark mode was
// removed.
//
// This complements test/theme_contrast_test.dart rather than repeating it.
// That one does arithmetic on the design tokens and catches a token tuned for
// one brightness only. This one renders the components and measures the
// pixels Flutter actually painted, so it catches the cases the token maths
// cannot see: text over a tint over a card, a label on a gradient, a colour
// that was passed explicitly at the call site instead of coming from a token.
//
// `textContrastGuideline` is Flutter's own implementation of WCAG AA (4.5:1,
// or 3:1 for large text), applied to the real render.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flow/core/theme/app_theme.dart';
import 'package:flow/core/widgets/booking_grid.dart';
import 'package:flow/core/widgets/buttons.dart';
import 'package:flow/core/widgets/conditions.dart';
import 'package:flow/core/widgets/provider_card.dart';
import 'package:flow/core/widgets/ticket.dart';
import 'package:flow/data/models/wind.dart';
import 'package:flow/core/widgets/feedback.dart';
import 'package:flow/core/widgets/misc.dart';
import 'package:flow/core/widgets/picker_field.dart';
import 'package:flow/core/widgets/surfaces.dart';
import 'package:flow/core/widgets/thread.dart';

void _noop() {}

/// Text-bearing components, in the arrangement they ship in.
final _cases = <String, Widget Function()>{
  'FlowCard': () =>
      const FlowCard(child: Text('Confirmed with Ahmed at El Gouna')),
  // Fixed ink on fixed white, in *both* themes — the ticket does not follow
  // the scheme because a camera reads it. That exemption is exactly why it
  // needs measuring: nothing else in the app would catch a label colour that
  // was picked to look right on a dark page and then painted on white.
  'TicketCard': () => const TicketCard(
        payload: '{"bookingId":"b","trainerId":"t"}',
        qrSize: 120,
        ticketId: 'FLW-13MAY-10AM-7X8K',
        rows: [
          ('SESSION', '13 May 2026 · 10:00 – 11:00'),
          ('SPOT', 'El Gouna, Red Sea'),
        ],
      ),
  'ProviderCard': () => ProviderCard(
        name: 'Nadia Cherif',
        photoUrl: null,
        rating: 4.8,
        reviewCount: 96,
        location: 'Soma Bay',
        priceLabel: '€95',
        onTap: () {},
      ),
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
  'SlotTile.free': () =>
      const SlotTile(range: '09:00 – 10:00', state: SlotState.free),
  'SlotTile.booked': () =>
      const SlotTile(range: '09:00 – 10:00', state: SlotState.booked),
  'SlotLegend': () => const SlotLegend(),
  'FlowNotice': () => const FlowNotice(
      icon: Icons.warning_amber_rounded,
      title: 'Away until Friday',
      body: 'Bookings are paused while this trainer is on vacation.'),
  'FlowNotice.success': () => Builder(
      builder: (context) => FlowNotice(
          icon: Icons.check_circle_outline_rounded,
          title: 'Paid in full',
          tone: context.tones.success)),
  'FlowNotice.danger': () => Builder(
      builder: (context) => FlowNotice(
          icon: Icons.error_outline_rounded,
          title: 'Payment failed',
          tone: context.tones.danger)),
  'TagPill': () => const TagPill('CONFIRMED'),
  'TagPill.dense': () => const TagPill('AWAITING PAYMENT', dense: true),
  'FlowChoiceChip.on': () =>
      FlowChoiceChip(label: 'El Gouna', selected: true, onTap: _noop),
  'FlowChoiceChip.off': () =>
      FlowChoiceChip(label: 'Soma Bay', selected: false, onTap: _noop),
  'PrimaryButton': () => PrimaryButton(label: 'Book this slot', onPressed: _noop),
  'MicroAction': () => MicroAction(label: 'APPROVE', onPressed: _noop),
  'InfoTile': () => const InfoTile(label: 'Level', value: 'Intermediate'),
  'DateBlock': () => DateBlock(date: DateTime(2026, 8, 8)),
  'FlowPickerField': () => FlowPickerField(
        values: const ['El Gouna'],
        onChanged: (_) {},
        options: const ['El Gouna'],
        sheetTitle: 'Spot',
      ),
  'ChatBubble.mine': () =>
      const ChatBubble(text: 'See you at the lagoon at nine.', mine: true),
  'ChatBubble.theirs': () =>
      const ChatBubble(text: 'Bring your own harness.', mine: false),
  'EmptyView': () => const EmptyView(
      icon: Icons.forum_outlined,
      title: 'No conversations',
      subtitle: 'Messages from your trainers land here.'),
};

void main() {
  {
    final theme = FlowTheme.light();
    for (final entry in _cases.entries) {
      testWidgets(entry.key, (tester) async {
        final handle = tester.ensureSemantics();
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: entry.value(),
              ),
            ),
          ),
        ));
        await tester.pumpAndSettle();

        await expectLater(tester, meetsGuideline(textContrastGuideline));

        // Disposed here, not in a tear-down: the framework checks for leaked
        // handles before tear-downs run.
        handle.dispose();
      });
    }
  }
}
