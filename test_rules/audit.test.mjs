// firestore.rules — match /audit_log/{entryId}  (P6)
//
// The accountability trail. Two properties carry the whole design: only
// staff touch it at all, and NOBODY — staff included — can rewrite history.
// An editable audit log is a diary, not a record.

import { test, describe, before, beforeEach, after } from 'node:test';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { as, anon, reset, seed, cleanup, testEnv } from './helpers.mjs';

before(async () => { await testEnv(); });
beforeEach(async () => {
  await reset();
  await seed(async (db) => {
    await db.collection('audit_log').doc('a1').set({
      action: 'suspend',
      staffId: 'admin',
      targetUserId: 'rider',
      targetName: 'Rider One',
      detail: 'until 2026-08-20',
    });
  });
});
after(cleanup);

const entry = (overrides = {}) => ({
  action: 'suspend',
  staffId: 'admin',
  targetUserId: 'rider',
  targetName: 'Rider One',
  ...overrides,
});

describe('audit_log — staff-only, append-only', () => {
  test('staff append an entry signed with their own uid', async () => {
    const db = await as('admin');
    await assertSucceeds(db.collection('audit_log').add(entry()));
  });

  test("DENY staff signing a colleague's name", async () => {
    const db = await as('admin');
    await assertFails(
      db.collection('audit_log').add(entry({ staffId: 'admin2' })),
    );
  });

  test('staff read the log', async () => {
    const db = await as('admin');
    await assertSucceeds(db.collection('audit_log').get());
  });

  test('DENY a rider reading the log', async () => {
    const db = await as('rider');
    await assertFails(db.collection('audit_log').doc('a1').get());
  });

  test('DENY a rider writing to the log', async () => {
    const db = await as('rider');
    await assertFails(
      db.collection('audit_log').add(entry({ staffId: 'rider' })),
    );
  });

  test('DENY a signed-out visitor entirely', async () => {
    const db = await anon();
    await assertFails(db.collection('audit_log').doc('a1').get());
  });

  test('DENY editing an entry — even as the staff member who wrote it', async () => {
    const db = await as('admin');
    await assertFails(
      db.collection('audit_log').doc('a1').update({ detail: 'never happened' }),
    );
  });

  test('DENY deleting an entry, staff included', async () => {
    const db = await as('admin');
    await assertFails(db.collection('audit_log').doc('a1').delete());
  });
});
