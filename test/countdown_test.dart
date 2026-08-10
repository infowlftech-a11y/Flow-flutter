// A per-second timer is the easiest thing in this component library to leak.
//
// `flutter_test` fails a test that ends with a Timer still pending, which
// makes leak-safety cheap to assert and expensive to skip — a leaked periodic
// timer keeps a handset's CPU awake for as long as the app is open, and it is
// invisible in every other kind of test.
//
// Note on what is NOT tested here: the tick itself. `CountdownText` reads
// `DateTime.now()`, which the test binding's fake clock does not control, so
// pumping a second of fake time does not move a real wall clock. Asserting on
// a tick would need the clock injected — a change to the component's API for
// the benefit of one test — so the value is asserted at construction and the
// timer's *lifecycle* is what this file guards.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flow/core/theme/app_theme.dart';
import 'package:flow/core/widgets/session_card.dart';

Widget _host(Widget child) => MaterialApp(
      theme: FlowTheme.dark(),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  test('formats hours, minutes and seconds with padding', () {
    expect(CountdownText.format(const Duration(seconds: 5)), '00:00:05');
    expect(CountdownText.format(const Duration(minutes: 32, seconds: 18)),
        '00:32:18');
    expect(CountdownText.format(const Duration(hours: 2, minutes: 5)),
        '02:05:00');
  });

  test('does not roll hours over at a day', () {
    // A multi-day expedition counts down in hours. Wrapping to "03:12:44"
    // three days out would be a confident lie.
    expect(CountdownText.format(const Duration(hours: 52, minutes: 30)),
        '52:30:00');
  });

  test('never renders a negative duration', () {
    expect(CountdownText.format(const Duration(seconds: -90)), '00:00:00');
  });

  testWidgets('a target already past starts no timer at all', (tester) async {
    await tester.pumpWidget(_host(CountdownText(
      target: DateTime.now().subtract(const Duration(minutes: 1)),
      style: const TextStyle(),
      expiredLabel: 'Finished',
    )));
    await tester.pump();

    expect(find.text('Finished'), findsOneWidget);
    // Reaching the end of this test at all is the assertion: a timer started
    // for an already-expired target would still be pending here and the
    // binding would fail the test.
  });

  testWidgets('disposing while running cancels the timer', (tester) async {
    await tester.pumpWidget(_host(CountdownText(
      target: DateTime.now().add(const Duration(hours: 1)),
      style: const TextStyle(),
    )));
    await tester.pump();

    // Tear the widget out while its periodic timer is live. If dispose did
    // not cancel, the binding fails with "A Timer is still pending".
    await tester.pumpWidget(_host(const SizedBox.shrink()));
    await tester.pump();
  });

  testWidgets('retargets when the session is rescheduled', (tester) async {
    final near = DateTime.now().add(const Duration(minutes: 5));
    await tester.pumpWidget(
        _host(CountdownText(target: near, style: const TextStyle())));
    await tester.pump();
    expect(find.textContaining('00:04:'), findsOneWidget,
        reason: 'should be counting to the first target');

    final far = DateTime.now().add(const Duration(hours: 3));
    await tester.pumpWidget(
        _host(CountdownText(target: far, style: const TextStyle())));
    await tester.pump();

    expect(find.textContaining('02:59:'), findsOneWidget,
        reason: 'a rescheduled session kept counting to the old time — '
            'didUpdateWidget is not restarting the timer');
  });
}
