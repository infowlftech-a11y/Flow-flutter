// The ticket topic is required at the sheet, not at the repository (P9).
//
// The repository keeps `topic` optional so tickets from before the picker
// existed still parse — which means the only thing standing between support
// and a queue of untriaged tickets is the sheet's submit gate. This pins the
// gate from the user's side of the glass: no topic, no write, and the error
// says why; pick one and the ticket files under it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flow/data/firestore_paths.dart';
import 'package:flow/features/support/support_screen.dart';

import 'support/screen_harness.dart';

void main() {
  testWidgets('no topic, no ticket — picking one lets it through', (
    tester,
  ) async {
    final db = await seededDb();
    // Tall on purpose: the sheet's ListView builds lazily, and on a phone
    // height the submit button below the fold has no element to find. The
    // gate under test is state logic, not geometry — screen_overlap and the
    // capture harness own how the sheet fits a real phone.
    await pumpScreen(
      tester,
      const SupportScreen(),
      db: db,
      size: const Size(360, 1400),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    await tester.tap(find.text('NEW TICKET'));
    // The sheet slides in; fixed pumps because skeletons animate forever.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(find.text('TOPIC'), findsOneWidget);

    // Subject and body filled, topic deliberately not.
    await tester.enterText(
      find.byType(TextField).at(0),
      'Charged twice for one lesson',
    );
    await tester.enterText(
      find.byType(TextField).at(1),
      'The app took the payment two times.',
    );
    await tester.tap(find.text('Open ticket'));
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    expect(
      (await db.collection(Col.tickets).get()).docs,
      isEmpty,
      reason: 'the submit gate must hold the write until a topic is picked',
    );
    expect(
      find.text('Pick a topic so the right person sees it first.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Payment or refund'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('Open ticket'));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }

    final docs = (await db.collection(Col.tickets).get()).docs;
    expect(docs, hasLength(1));
    expect(docs.single.data()['topic'], 'Payment or refund');
    expect(docs.single.data()['subject'], 'Charged twice for one lesson');
  });
}
