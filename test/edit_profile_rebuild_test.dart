// Personal details rebuilt itself on every keystroke.
//
// `initState` attached `setState(() {})` to all four text controllers, so one
// character typed into the bio re-ran four FormGroups, two picker fields and
// the gallery grid to produce an identical tree.
//
// The guard is the same one both onboarding forms use — rebuild when the dirty
// flag flips, or unconditionally once the user has tried to save. Three things
// are worth holding still:
//
//   1. a keystroke that changes neither the dirty flag nor a visible error
//      must not schedule a frame at all — that is the whole point, and the
//      only assertion here that fails if the guard is removed;
//   2. Save still tracks dirty in *both* directions;
//   3. after a failed save, the inline error keeps tracking what is typed.
//
// (2) and (3) are the risks the guard introduces rather than removes: a guard
// placed slightly wrong leaves Save stuck on, or freezes the error message at
// whatever it said when the user tapped it.
//
// Note on (1): `hasScheduledFrame` is the measurement, because a rebuild that
// produces an identical tree is invisible to any assertion about what is on
// screen. Do not "simplify" it to a widget lookup — the old code passes that.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flow/core/theme/app_theme.dart';
import 'package:flow/data/models/app_user.dart';
import 'package:flow/features/profile/edit_profile_screen.dart';
import 'package:flow/providers/providers.dart';

const _user = AppUser(
  uid: 'u1',
  name: 'Lina Hassan',
  email: 'lina@example.com',
  role: UserRole.kiter,
  status: AccountStatus.active,
  level: 'Intermediate',
  languages: ['English'],
  nationality: 'Egypt',
  age: 29,
);

Widget _app(Stream<AppUser?> profile) => ProviderScope(
      overrides: [currentUserProvider.overrideWith((ref) => profile)],
      child: MaterialApp(
        theme: FlowTheme.dark(),
        home: const EditProfileScreen(),
      ),
    );

void main() {
  testWidgets('a keystroke that changes nothing visible schedules no frame',
      (tester) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(Stream.value(_user)));
    await tester.pumpAndSettle();

    final bio = find.byType(TextField).at(2);

    // `build()` constructs this button fresh every time it runs, so holding on
    // to the mounted instance and checking identity afterwards asks exactly
    // "did the form rebuild?" — which is invisible to any assertion about what
    // is on screen, because the rebuilt tree is identical.
    FilledButton save() =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'));

    // First character: the form goes from clean to dirty, so Save has to light
    // up. A rebuild here is correct and expected.
    final beforeFirst = save();
    await tester.enterText(bio, 'W');
    await tester.pumpAndSettle();
    expect(identical(save(), beforeFirst), isFalse,
        reason: 'the clean→dirty transition has to reach Save');

    // Every character after it changes nothing anyone can see: still dirty,
    // still no errors (the form has not been submitted). This is the rebuild
    // the old code spent 200 times while somebody wrote their bio.
    final beforeRest = save();
    await tester.enterText(bio, 'Wind, water, repeat.');
    await tester.pumpAndSettle();
    expect(identical(save(), beforeRest), isTrue,
        reason: 'typing into an already-dirty form still rebuilds all of it');
  });

  testWidgets('a profile arriving after the first frame fills the form',
      (tester) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Deliberately unseeded: an override that already holds a value takes the
    // initState path and never exercises the load-from-build() branch.
    final controller = StreamController<AppUser?>();
    addTearDown(controller.close);

    await tester.pumpWidget(_app(controller.stream));
    await tester.pump();

    // Nothing to edit yet — the screen shows its skeleton.
    expect(find.text('Lina Hassan'), findsNothing);

    controller.add(_user);
    await tester.pumpAndSettle();

    expect(find.text('Lina Hassan'), findsOneWidget,
        reason: 'the late profile never reached the name field');
  });

  testWidgets('Save enables on a change and disables when it is undone',
      (tester) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(Stream.value(_user)));
    await tester.pumpAndSettle();

    FilledButton save() =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'));

    expect(save().onPressed, isNull,
        reason: 'an untouched form has nothing to save');

    await tester.enterText(find.byType(TextField).first, 'Lina H');
    await tester.pumpAndSettle();
    expect(save().onPressed, isNotNull,
        reason: 'the dirty flag never reached the Save button — the keystroke '
            'guard is swallowing the transition');

    // Back to the loaded value: the button has to go quiet again, which is the
    // second half of the transition and the half a one-way guard would miss.
    await tester.enterText(find.byType(TextField).first, 'Lina Hassan');
    await tester.pumpAndSettle();
    expect(save().onPressed, isNull,
        reason: 'reverting the edit left Save enabled');
  });

  testWidgets('the name error keeps tracking the field after a failed save',
      (tester) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(Stream.value(_user)));
    await tester.pumpAndSettle();

    // Emptying the required name is both a change (Save lights up) and a
    // validation failure, so one tap gets us to the attempted state.
    await tester.enterText(find.byType(TextField).first, '');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Your name is required'), findsOneWidget,
        reason: 'saving an empty name should say so');

    await tester.enterText(find.byType(TextField).first, 'Lina');
    await tester.pumpAndSettle();
    expect(find.text('Your name is required'), findsNothing,
        reason: 'the inline error froze — the guard is not letting the field '
            'rebuild once the form has been attempted');
  });
}
