// Drives the real app on a real device and photographs every rebuilt screen.
//
// This is not a pass/fail test in the usual sense — it navigates and captures.
// The widget suite already asserts overflow, contrast and tap targets on
// components in isolation; what it structurally cannot see is whether a screen
// *reads* correctly against live Firestore data. Every defect in the redesign
// was found by looking at a running build, not by a green suite:
//
//   - names clipped to nine characters (an ellipsis is a legal layout)
//   - a placeholder glyph painted under a hero title
//   - "Sat 29 Aug · —" wherever a booking had no hours
//   - a certification badge that never rendered at all
//
// So this exists to make that looking repeatable and cheap.
//
// IT ONLY NAVIGATES. Nothing here confirms a booking, cancels a session,
// approves a request or writes a review — it runs against the real project
// with a real signed-in user, and a walkthrough that mutates production data
// is not a walkthrough.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flow/main.dart' as app;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Advances frames for [seconds] of wall-clock time.
  ///
  /// Deliberately not `pumpAndSettle`: that waits for the frame queue to go
  /// quiet, and this app always has something animating — the skeleton
  /// shimmer while Firestore loads, the live-session dot once it has. Both
  /// repeat forever, so settling never happens and the call times out.
  Future<void> breathe(WidgetTester tester, {double seconds = 3}) async {
    final end = DateTime.now().add(
        Duration(milliseconds: (seconds * 1000).round()));
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> shoot(WidgetTester tester, String name) async {
    await breathe(tester, seconds: 1);
    await binding.takeScreenshot(name);
  }

  /// Polls for [finder] until it appears, up to [seconds].
  ///
  /// Fixed sleeps do not work here: this is a real network to a US-region
  /// Firestore, and a cold start that takes four seconds on one run takes
  /// twelve on the next. Waiting for the widget is the only honest signal.
  Future<bool> waitFor(WidgetTester tester, Finder finder,
      {double seconds = 20}) async {
    final end = DateTime.now().add(
        Duration(milliseconds: (seconds * 1000).round()));
    while (DateTime.now().isBefore(end)) {
      if (finder.evaluate().isNotEmpty) return true;
      await tester.pump(const Duration(milliseconds: 200));
    }
    return false;
  }

  /// Taps [finder] once it appears. Records a miss instead of throwing, so one
  /// unreachable screen does not cost us every screen after it — but the misses
  /// are asserted at the end, because a walk that saw nothing is a failure, not
  /// a pass.
  final missed = <String>[];

  Future<bool> tapWhenReady(WidgetTester tester, Finder finder,
      {required String what, double seconds = 20}) async {
    if (!await waitFor(tester, finder, seconds: seconds)) {
      debugPrint('WALK: never found $what');
      missed.add(what);
      return false;
    }
    await tester.tap(finder.first, warnIfMissed: false);
    await breathe(tester, seconds: 2);
    return true;
  }

  /// Signs in only if the app is sitting on the welcome gate.
  ///
  /// `flutter drive` installs its own instrumented APK and the Firebase
  /// session does not survive that, so an automated walk always starts signed
  /// out — unlike `flutter run`, which keeps it across restarts.
  ///
  /// Credentials come from --dart-define and are never committed:
  ///   flutter drive --driver=test_driver/integration_test.dart \
  ///     --target=integration_test/walkthrough_test.dart -d emulator-5554 \
  ///     --dart-define=FLOW_EMAIL=you@example.com \
  ///     --dart-define=FLOW_PASSWORD=...
  ///
  /// Without them the walk stops at the gate and says so, rather than
  /// photographing a login screen six times and reporting success.
  Future<void> signInIfGated(WidgetTester tester) async {
    const email = String.fromEnvironment('FLOW_EMAIL');
    const password = String.fromEnvironment('FLOW_PASSWORD');

    final gate = find.text('I already have an account');
    if (gate.evaluate().isEmpty) return; // already past it

    if (email.isEmpty || password.isEmpty) {
      missed.add('sign-in (no FLOW_EMAIL / FLOW_PASSWORD given)');
      return;
    }

    await tester.tap(gate.first, warnIfMissed: false);
    await breathe(tester, seconds: 2);

    final fields = find.byType(TextField);
    if (!await waitFor(tester, fields, seconds: 10)) {
      missed.add('the sign-in form');
      return;
    }
    await tester.enterText(fields.at(0), email);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(fields.at(1), password);
    await tester.pump(const Duration(milliseconds: 200));

    final submit = find.text('Sign in');
    if (submit.evaluate().isNotEmpty) {
      await tester.tap(submit.first, warnIfMissed: false);
    } else {
      await tester.testTextInput.receiveAction(TextInputAction.done);
    }
    await breathe(tester, seconds: 8);
  }

  testWidgets('walk the redesigned rider screens', (tester) async {
    await binding.convertFlutterSurfaceToImage();

    app.main();
    await breathe(tester, seconds: 4);
    await signInIfGated(tester);

    // Wait for the shell rather than a fixed sleep — this is a real network
    // to a US-region Firestore.
    await waitFor(tester, find.text('Discover'), seconds: 25);
    await shoot(tester, '01-discover');

    // Discover → trainer profile. This is the screen that proved the
    // certification badge never rendered at all.
    if (await tapWhenReady(tester, find.text('Sofia Ricci'),
        what: 'a trainer card')) {
      await breathe(tester, seconds: 3);
      await shoot(tester, '02-trainer-profile');

      // → booking. The five-state slot grid.
      if (await tapWhenReady(tester, find.text('Book now'),
          what: 'the Book now CTA')) {
        await breathe(tester, seconds: 4);
        await shoot(tester, '03-booking-grid');
        await tapWhenReady(tester, find.byTooltip('Back'),
            what: 'back out of booking', seconds: 8);
      }
      await tapWhenReady(tester, find.byTooltip('Back'),
          what: 'back out of the profile', seconds: 8);
    }

    await breathe(tester, seconds: 2);

    // Everything from here is traced, so a --profile drive reports real frame
    // build and raster times instead of adjectives. Tab switching and a
    // scroll are the two things a user does constantly, so they are what is
    // worth measuring; in debug the numbers are meaningless (JIT, asserts on)
    // and `reportData` simply stays null.
    await binding.traceAction(
      () async {
        for (final (dest, shot) in const [
          ('Sessions', '04-sessions'),
          ('Ticket', '05-ticket'),
          ('Profile', '06-profile'),
        ]) {
          if (await tapWhenReady(tester, find.text(dest),
              what: 'the $dest tab')) {
            await breathe(tester, seconds: 3);
            await shoot(tester, shot);
          }
        }

        // A real fling down the trainer list — the longest scrollable surface
        // in the app and the one carrying decoded images.
        if (await tapWhenReady(tester, find.text('Discover'),
            what: 'the Discover tab')) {
          final list = find.byType(Scrollable);
          if (list.evaluate().isNotEmpty) {
            for (var i = 0; i < 3; i++) {
              await tester.fling(list.first, const Offset(0, -400), 2000);
              await breathe(tester, seconds: 1);
              await tester.fling(list.first, const Offset(0, 400), 2000);
              await breathe(tester, seconds: 1);
            }
          }
        }
      },
      reportKey: 'walkthrough_timeline',
    );

    // The point of the whole exercise. Without this the walk reports success
    // having photographed the login screen six times — which is exactly what
    // it did on its first run after the session was lost.
    expect(missed, isEmpty,
        reason: 'the walk never reached: ${missed.join(", ")}');
  }, timeout: const Timeout(Duration(minutes: 6)));
}
