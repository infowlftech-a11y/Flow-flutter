// firestore.rules — match /users/{userId}  (lines 47-76)
//
// This is the block that decides who someone *is*. privilegedFieldsUnchanged()
// is the single rule standing between a rider and self-approval as a trainer,
// so every field it names gets its own denial test.

import { test, describe, before, beforeEach, after } from 'node:test';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { deleteField } from 'firebase/firestore';
import { as, anon, reset, seed, cleanup, testEnv } from './helpers.mjs';

before(async () => { await testEnv(); });
beforeEach(reset);
after(cleanup);

describe('users — read (line 48)', () => {
  test('any signed-in user reads any profile', async () => {
    const db = await as('rider');
    await assertSucceeds(db.collection('users').doc('trainer').get());
  });

  test('a signed-in user with no profile of their own can still read', async () => {
    const db = await as('noProfile');
    await assertSucceeds(db.collection('users').doc('trainer').get());
  });

  test('DENY a signed-out visitor', async () => {
    const db = await anon();
    await assertFails(db.collection('users').doc('trainer').get());
  });
});

describe('users — create (lines 53-59)', () => {
  test('a rider self-activates', async () => {
    const db = await as('newRider');
    await assertSucceeds(
      db.collection('users').doc('newRider').set({ role: 'kiter', status: 'active' }),
    );
  });

  test('a business account starts pending', async () => {
    const db = await as('newCoach');
    await assertSucceeds(
      db.collection('users').doc('newCoach').set({ role: 'business', status: 'pending' }),
    );
  });

  test('DENY a business account creating itself active', async () => {
    const db = await as('newCoach');
    await assertFails(
      db.collection('users').doc('newCoach').set({ role: 'business', status: 'active' }),
    );
  });

  test('DENY a rider creating itself pending', async () => {
    const db = await as('newRider');
    await assertFails(
      db.collection('users').doc('newRider').set({ role: 'kiter', status: 'pending' }),
    );
  });

  test('DENY creating a profile at someone elses uid', async () => {
    const db = await as('newRider');
    await assertFails(
      db.collection('users').doc('victim').set({ role: 'kiter', status: 'active' }),
    );
  });

  test('DENY self-creating as admin', async () => {
    const db = await as('newRider');
    await assertFails(
      db.collection('users').doc('newRider').set({ role: 'admin', status: 'active' }),
    );
  });

  test('DENY an unknown role', async () => {
    const db = await as('newRider');
    await assertFails(
      db.collection('users').doc('newRider').set({ role: 'wizard', status: 'active' }),
    );
  });

  test('DENY a role with no status at all', async () => {
    const db = await as('newRider');
    await assertFails(db.collection('users').doc('newRider').set({ role: 'kiter' }));
  });

  test('DENY a signed-out visitor creating a profile', async () => {
    const db = await anon();
    await assertFails(
      db.collection('users').doc('newRider').set({ role: 'kiter', status: 'active' }),
    );
  });
});

describe('users — update, self (lines 61-62)', () => {
  test('a rider edits their own ordinary fields', async () => {
    const db = await as('rider');
    await assertSucceeds(
      db.collection('users').doc('rider').update({ name: 'Renamed', bio: 'hi' }),
    );
  });

  test('DENY editing someone elses profile', async () => {
    const db = await as('rider');
    await assertFails(db.collection('users').doc('trainer').update({ name: 'Hacked' }));
  });

  // privilegedFieldsUnchanged() — one test per named field (lines 38-42).
  // Every value here must DIFFER from the actor's seeded value: affectedKeys()
  // ignores a write of an identical value, so re-writing 'active' over 'active'
  // would pass and prove nothing.
  for (const [field, value] of [
    ['role', 'admin'],
    ['status', 'blocked'],
    ['blockedUntil', '2030-01-01'],
    ['blockedAt', '2026-01-01'],
    ['reviewedAt', '2026-01-01'],
    ['reviewNote', 'looks good to me'],
    // BUG-018: unblockUser RESTORES this field verbatim. A pending trainer
    // who could pre-write statusBeforeBlock 'active' would come out of any
    // later suspension approved without review.
    ['statusBeforeBlock', 'active'],
  ]) {
    test(`DENY a user writing their own ${field}`, async () => {
      const db = await as('rider');
      await assertFails(db.collection('users').doc('rider').update({ [field]: value }));
    });
  }

  test('DENY a pending trainer self-approving to active', async () => {
    const db = await as('pendingTrainer');
    await assertFails(
      db.collection('users').doc('pendingTrainer').update({ status: 'active' }),
    );
  });

  // The one status transition a user may write for themselves: a declined
  // trainer putting a corrected application back in the queue. Safe because
  // of where it lands — `pending` is not bookable — and pinned tightly, so
  // the exception cannot become a hole.
  describe('re-application: rejected → pending', () => {
    test('a declined trainer resubmits', async () => {
      const db = await as('rejectedTrainer');
      await assertSucceeds(
        db.collection('users').doc('rejectedTrainer').update({
          status: 'pending', bio: 'Fixed my IKO number', hourlyRate: 400,
        }),
      );
    });

    test('…and clears the note describing the decision it replaces',
      async () => {
        // The repository deletes these two fields in the same write; a
        // deletion is an affectedKey like any other, so the rule has to
        // tolerate them being in the diff.
        await seed(async (db) => {
          await db.collection('users').doc('rejectedTrainer')
            .set({ reviewNote: 'Certificate unreadable', reviewedAt: 'x' },
              { merge: true });
        });
        const db = await as('rejectedTrainer');
        await assertSucceeds(
          db.collection('users').doc('rejectedTrainer').update({
            status: 'pending',
            reviewNote: deleteField(),
            reviewedAt: deleteField(),
          }),
        );
      });

    test('DENY resubmitting straight to active', async () => {
      const db = await as('rejectedTrainer');
      await assertFails(
        db.collection('users').doc('rejectedTrainer').update({ status: 'active' }),
      );
    });

    test('DENY a blocked account laundering itself into the queue', async () => {
      // The path this rule must never open: blocked → pending → approved.
      const db = await as('blocked');
      await assertFails(
        db.collection('users').doc('blocked').update({ status: 'pending' }),
      );
    });

    test('a pending trainer writing their own status back is a no-op edit',
      async () => {
        // Not a hole, and worth stating: `affectedKeys()` ignores a write of
        // an identical value, so `pending` over `pending` never reaches
        // isReapplication() at all — the diff contains `bio` and nothing
        // else, and this passes as the ordinary profile edit it is. The
        // transition that would matter, pending → active, is denied above.
        const db = await as('pendingTrainer');
        await assertSucceeds(
          db.collection('users').doc('pendingTrainer').update({
            status: 'pending', bio: 'nudge',
          }),
        );
      });

    test('DENY changing role on the way through', async () => {
      const db = await as('rejectedTrainer');
      await assertFails(
        db.collection('users').doc('rejectedTrainer')
          .update({ status: 'pending', role: 'admin' }),
      );
    });

    test('DENY clearing a block marker alongside the resubmission', async () => {
      const db = await as('rejectedTrainer');
      await assertFails(
        db.collection('users').doc('rejectedTrainer')
          .update({ status: 'pending', blockedUntil: null }),
      );
    });

    test('DENY resubmitting someone else’s application', async () => {
      const db = await as('rider');
      await assertFails(
        db.collection('users').doc('rejectedTrainer').update({ status: 'pending' }),
      );
    });
  });

  test('DENY a blocked user lifting their own block', async () => {
    const db = await as('blocked');
    await assertFails(
      db.collection('users').doc('blocked').update({ status: 'active', blockedUntil: null }),
    );
  });

  test('DENY a privileged field smuggled in beside a legitimate one', async () => {
    const db = await as('rider');
    await assertFails(
      db.collection('users').doc('rider').update({ name: 'Fine', role: 'admin' }),
    );
  });

  test('a no-op write of the same role value is allowed (diff is empty)', async () => {
    // Documents the actual semantics of affectedKeys(): writing an identical
    // value is not a change, so it passes. Harmless, but worth pinning so a
    // future rules edit cannot alter it silently.
    const db = await as('rider');
    await assertSucceeds(db.collection('users').doc('rider').update({ role: 'kiter' }));
  });
});

describe('users — update, staff (line 62)', () => {
  for (const staff of ['admin', 'owner', 'support']) {
    test(`${staff} approves a pending trainer`, async () => {
      const db = await as(staff);
      await assertSucceeds(
        db.collection('users').doc('pendingTrainer').update({ status: 'active' }),
      );
    });
  }

  test('admin blocks a rider', async () => {
    const db = await as('admin');
    await assertSucceeds(
      db.collection('users').doc('rider').update({ status: 'blocked', blockedUntil: '2030-01-01' }),
    );
  });

  test('DENY a trainer approving another trainer', async () => {
    const db = await as('trainer');
    await assertFails(
      db.collection('users').doc('pendingTrainer').update({ status: 'active' }),
    );
  });

  test('DENY a rider approving a trainer', async () => {
    const db = await as('rider');
    await assertFails(
      db.collection('users').doc('pendingTrainer').update({ status: 'active' }),
    );
  });

  test('DENY a signed-in user with no profile document', async () => {
    // selfProfile() resolves to a missing document; isStaff() must deny
    // rather than throw.
    const db = await as('noProfile');
    await assertFails(
      db.collection('users').doc('pendingTrainer').update({ status: 'active' }),
    );
  });
});

describe('users — delete (line 65)', () => {
  test('a user deletes their own profile', async () => {
    const db = await as('rider');
    await assertSucceeds(db.collection('users').doc('rider').delete());
  });

  test('DENY deleting someone elses profile', async () => {
    const db = await as('rider');
    await assertFails(db.collection('users').doc('trainer').delete());
  });

  test('DENY an admin deleting a profile', async () => {
    // Staff moderate but do not delete accounts — §3.13 makes deletion the
    // user's own act. Pinned so a rules edit cannot widen it unnoticed.
    const db = await as('admin');
    await assertFails(db.collection('users').doc('rider').delete());
  });
});

describe('users — station sub-collections (lines 68-75)', () => {
  beforeEach(async () => {
    await seed(async (db) => {
      await db.collection('users').doc('trainer').collection('station_instructors')
        .doc('i1').set({ name: 'Coach A' });
      await db.collection('users').doc('trainer').collection('station_services')
        .doc('s1').set({ title: 'Lesson' });
    });
  });

  for (const sub of ['station_instructors', 'station_services']) {
    test(`${sub}: any signed-in user reads`, async () => {
      const db = await as('rider');
      await assertSucceeds(
        db.collection('users').doc('trainer').collection(sub).doc('i1').get(),
      );
    });

    test(`${sub}: the owner writes`, async () => {
      const db = await as('trainer');
      await assertSucceeds(
        db.collection('users').doc('trainer').collection(sub).doc('new').set({ name: 'X' }),
      );
    });

    test(`${sub}: staff writes`, async () => {
      const db = await as('admin');
      await assertSucceeds(
        db.collection('users').doc('trainer').collection(sub).doc('new').set({ name: 'X' }),
      );
    });

    test(`${sub}: DENY another trainer writing`, async () => {
      const db = await as('trainer2');
      await assertFails(
        db.collection('users').doc('trainer').collection(sub).doc('new').set({ name: 'X' }),
      );
    });

    test(`${sub}: DENY a rider writing`, async () => {
      const db = await as('rider');
      await assertFails(
        db.collection('users').doc('trainer').collection(sub).doc('new').set({ name: 'X' }),
      );
    });

    test(`${sub}: DENY a signed-out visitor reading`, async () => {
      const db = await anon();
      await assertFails(
        db.collection('users').doc('trainer').collection(sub).doc('i1').get(),
      );
    });
  }
});
