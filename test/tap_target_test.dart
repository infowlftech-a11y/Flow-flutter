// Every tappable thing must be big enough to hit, and must say what it is.
//
// The refactor fixed three of these one at a time — a 40px send button on the
// appeal thread, a station-profile back button with no size box, a
// remove-photo control that announced nothing to a screen reader. All three
// were found by reading code, which is a poor way to find the rest.
//
// These are Flutter's own accessibility guidelines rather than a hand-rolled
// semantics walk: they measure what the platform would actually hand to an
// accessibility service, and they are maintained alongside the framework.
//
//  - iOSTapTargetGuideline    — 44x44 minimum
//  - androidTapTargetGuideline — 48x48 minimum
//  - labeledTapTargetGuideline — every tappable node has a label to announce
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flow/core/theme/app_theme.dart';
import 'package:flow/core/widgets/buttons.dart';
import 'package:flow/core/widgets/media.dart';
import 'package:flow/core/widgets/misc.dart';
import 'package:flow/core/widgets/picker_field.dart';
import 'package:flow/core/widgets/surfaces.dart';
import 'package:flow/core/widgets/thread.dart';

void _noop() {}

/// Every interactive shared component, in the tightest realistic container.
final _cases = <String, Widget Function()>{
  'PrimaryButton': () => PrimaryButton(label: 'Book', onPressed: _noop),
  'MicroAction.filled': () => MicroAction(label: 'APPROVE', onPressed: _noop),
  'MicroAction.outlined': () =>
      MicroAction(label: 'DECLINE', onPressed: _noop, filled: false),
  'ScrimIconButton': () => ScrimIconButton(
      icon: Icons.close_rounded, tooltip: 'Close', onTap: _noop),
  'FlowChoiceChip': () =>
      FlowChoiceChip(label: 'El Gouna', selected: false, onTap: _noop),
  'FlowChoiceChip.deletable': () => FlowChoiceChip(
      label: 'English', selected: true, onTap: _noop, onDeleted: _noop),
  'FlowCard.onTap': () =>
      FlowCard(onTap: _noop, child: const Text('A tappable card')),
  'InfoTile.onTap': () =>
      InfoTile(label: 'Location', value: 'El Gouna', onTap: _noop),
  'FlowPickerField': () => FlowPickerField(
        values: const [],
        onChanged: (_) {},
        options: const ['El Gouna'],
        sheetTitle: 'Spot',
      ),
  'ThumbTile': () => ThumbTile(
      onRemove: _noop,
      isNew: true,
      child: const SizedBox(width: 84, height: 84)),
  'MessageComposer': () => MessageComposer(
      controller: TextEditingController(text: 'hi'), onSend: _noop),
  'Stars.interactive': () => Stars(value: 3, onChanged: (_) {}),
};

void main() {
  for (final entry in _cases.entries) {
    testWidgets('${entry.key} meets the tap-target guidelines',
        (tester) async {
      final handle = tester.ensureSemantics();
      tester.view.physicalSize = const Size(360, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: FlowTheme.dark(),
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: entry.value(),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      // Not addTearDown: the framework checks for leaked handles before
      // tear-downs run, so deferring the dispose fails every test with
      // "a SemanticsHandle was active at the end of the test" and hides
      // whatever the guidelines actually found.
      handle.dispose();
    });
  }
}
