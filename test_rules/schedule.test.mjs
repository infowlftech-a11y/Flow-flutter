// firestore.rules — match /availability/{docId} and /vacations/{docId}
// (lines 131-145, renumbered after the BUG-001 fix)
//
// Both are trainer-owned calendar documents with identical rules, so they are
// driven from one table. Availability docs are *blocks* (§8.5): their presence
// removes an hour, so a rider who could write one could close a competitor's
// calendar.

import { test, describe, before, beforeEach, after } from 'node:test';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { as, anon, reset, seed, cleanup, testEnv } from './helpers.mjs';

before(async () => { await testEnv(); });
beforeEach(async () => {
  await reset();
  await seed(async (db) => {
    await db.collection('availability').doc('a1').set({
      instructorId: 'trainer', date: '2026-08-14', startTime: '09:00',
      endTime: '11:00', status: 'host-blocked', label: 'Lunch',
    });
    await db.collection('vacations').doc('v1').set({
      instructorId: 'trainer', startDate: '2026-09-01', endDate: '2026-09-07',
      label: 'Away',
    });
  });
});
after(cleanup);

const CASES = [
  { col: 'availability', id: 'a1', doc: { date: '2026-08-14', startTime: '09:00', status: 'host-blocked' } },
  { col: 'vacations', id: 'v1', doc: { startDate: '2026-09-01', endDate: '2026-09-07' } },
];

for (const { col, id, doc } of CASES) {
  describe(`${col} — read`, () => {
    test('any signed-in user reads — the booking grid needs blocks', async () => {
      const db = await as('rider');
      await assertSucceeds(db.collection(col).doc(id).get());
    });

    test('DENY a signed-out visitor', async () => {
      const db = await anon();
      await assertFails(db.collection(col).doc(id).get());
    });
  });

  describe(`${col} — create`, () => {
    test('the trainer creates their own', async () => {
      const db = await as('trainer');
      await assertSucceeds(
        db.collection(col).doc('new').set({ ...doc, instructorId: 'trainer' }),
      );
    });

    test('DENY creating one on another trainers calendar', async () => {
      const db = await as('trainer2');
      await assertFails(
        db.collection(col).doc('new').set({ ...doc, instructorId: 'trainer' }),
      );
    });

    test('DENY a rider blocking a trainers calendar', async () => {
      const db = await as('rider');
      await assertFails(
        db.collection(col).doc('new').set({ ...doc, instructorId: 'trainer' }),
      );
    });

    test('DENY one with no instructorId at all', async () => {
      const db = await as('trainer');
      await assertFails(db.collection(col).doc('new').set(doc));
    });

    test('DENY a signed-out visitor', async () => {
      const db = await anon();
      await assertFails(
        db.collection(col).doc('new').set({ ...doc, instructorId: 'trainer' }),
      );
    });
  });

  describe(`${col} — update and delete`, () => {
    test('the owner updates', async () => {
      const db = await as('trainer');
      await assertSucceeds(db.collection(col).doc(id).update({ label: 'Changed' }));
    });

    test('the owner deletes', async () => {
      const db = await as('trainer');
      await assertSucceeds(db.collection(col).doc(id).delete());
    });

    test('staff updates', async () => {
      const db = await as('admin');
      await assertSucceeds(db.collection(col).doc(id).update({ label: 'Moderated' }));
    });

    test('DENY another trainer updating', async () => {
      const db = await as('trainer2');
      await assertFails(db.collection(col).doc(id).update({ label: 'Hijacked' }));
    });

    test('DENY a rider deleting a block to free up an hour', async () => {
      const db = await as('rider');
      await assertFails(db.collection(col).doc(id).delete());
    });

    test('DENY another trainer deleting', async () => {
      const db = await as('trainer2');
      await assertFails(db.collection(col).doc(id).delete());
    });
  });
}
