// The session reference — the one name a booking has in conversation.
//
// It is printed on the beach ticket, quoted to support, stamped onto tickets
// and reports, and pasted into the console's Sessions search. All of those
// must agree, which is why the derivation lives in one function and this file
// pins its shape.
import 'package:flutter_test/flutter_test.dart';

import 'package:flow/core/utils/refs.dart';

void main() {
  test('a normal booking: FLW-<MMDD>-<last four of the id>, uppercased', () {
    expect(sessionRef('xK9fQ2abcd7x8k', '2026-05-13'), 'FLW-0513-7X8K');
  });

  test('non-alphanumerics in the id never reach the tail', () {
    expect(sessionRef('ab_c-d!e1234', '2026-05-13'), 'FLW-0513-1234');
  });

  test('an id of four or fewer characters is used whole', () {
    expect(sessionRef('b3', '2099-08-29'), 'FLW-0829-B3');
  });

  test('a malformed date is kept whole rather than thrown on', () {
    expect(sessionRef('abcd', '13-05'), 'FLW-1305-ABCD');
  });

  test('an empty date degrades to FLW-<tail>, never a crash', () {
    expect(sessionRef('abcd', ''), 'FLW-ABCD');
  });

  test('matches what the beach ticket has always printed', () {
    // ticket_screen.dart derived exactly this before the function was
    // shared; a rider's spoken reference must not change between builds.
    const id = 'seed-lina-omar-next';
    const date = '2026-05-13';
    final legacyClean = id.replaceAll(RegExp('[^A-Za-z0-9]'), '').toUpperCase();
    final legacyTail = legacyClean.substring(legacyClean.length - 4);
    final legacy = 'FLW-${date.replaceAll('-', '').substring(4)}-$legacyTail';
    expect(sessionRef(id, date), legacy);
  });

  group('memberRef — the person the console is talking about (P3)', () {
    test('rider and coach differ by the middle letter only', () {
      expect(memberRef('xK9fQ2abcd7x8k', coach: false), 'FLW-R-7X8K');
      expect(memberRef('xK9fQ2abcd7x8k', coach: true), 'FLW-C-7X8K');
    });

    test('same cleaning rules as sessionRef — the schemes must not drift', () {
      expect(memberRef('ab_c-d!e1234', coach: false), 'FLW-R-1234');
      expect(memberRef('u1', coach: true), 'FLW-C-U1');
    });
  });
}
