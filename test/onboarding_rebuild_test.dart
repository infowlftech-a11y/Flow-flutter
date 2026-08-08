// Inline validation must stay live after the first submit.
//
// Both onboarding forms fired `setState(() {})` on every keystroke. Nothing
// on screen reads that text until the step has been attempted — the error
// getters all return null before then, and neither Continue nor Submit is
// ever disabled (they scroll to the first problem instead) — so every
// character retyped the whole form to produce an identical tree.
//
// Guarding those callbacks on `attempted` removes the waste. The risk it
// introduces is precise and this test covers it: after a failed submit, the
// inline error must still update as the user fixes the field. If the guard
// were placed wrongly the message would freeze at whatever it said when the
// user tapped submit.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flow/core/theme/app_theme.dart';
import 'package:flow/features/onboarding/kiter_form_screen.dart';
import 'package:flow/features/onboarding/onboarding_validators.dart';
import 'package:flow/providers/providers.dart';

Widget _app() => ProviderScope(
      overrides: [
        // The form only touches this provider while building; everything else
        // it reads happens inside _submit, which this test never reaches.
        sessionProvider
            .overrideWithValue(const Session(stage: AppStage.chooseRole)),
      ],
      child: MaterialApp(
        theme: FlowTheme.dark(),
        home: const KiterFormScreen(),
      ),
    );

void main() {
  testWidgets('the name error appears on submit and clears as you type',
      (tester) async {
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    final nameField = find.byType(TextField).first;
    final tooShort = 'a' * (OnboardingValidators.minNameLength - 1);
    final expectedError = OnboardingValidators.name(tooShort);
    expect(expectedError, isNotNull,
        reason: 'test needs a name the validator rejects');

    // Quiet before the first submit: the form does not nag an untouched field.
    await tester.enterText(nameField, tooShort);
    await tester.pumpAndSettle();
    expect(find.text(expectedError!), findsNothing);

    // Submitting reveals it.
    await tester.tap(find.text("Let's ride"));
    await tester.pumpAndSettle();
    expect(find.text(expectedError), findsOneWidget,
        reason: 'submitting an invalid form should surface the reason');

    // And now the message has to track what is typed — this is the assertion
    // the rebuild guard could break.
    await tester.enterText(nameField, 'A perfectly acceptable name');
    await tester.pumpAndSettle();
    expect(find.text(expectedError), findsNothing,
        reason: 'the inline error froze — the field no longer rebuilds after '
            'the step was attempted');
  });
}
