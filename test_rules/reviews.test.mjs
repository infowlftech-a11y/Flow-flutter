// firestore.rules — match /reviews/{reviewId}
//
// The rules pin authorship and the 1-5 range only; the comment above them
// states plainly that eligibility (§8.9 — a completed, unreviewed booking) is
// enforced in the repository. These tests assert what the rules do enforce,
// and pin the shape of what they deliberately do not, so the gap is visible
// rather than assumed.

import { test, describe, before, beforeEach, after } from 'node:test';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { as, anon, reset, seed, cleanup, testEnv } from './helpers.mjs';

const review = (o = {}) => ({
  trainerId: 'trainer', userId: 'rider', userName: 'Rider One',
  rating: 5, comment: 'Great', bookingId: 'b1', ...o,
});

before(async () => { await testEnv(); });
beforeEach(async () => {
  await reset();
  await seed(async (db) => {
    await db.collection('reviews').doc('r1').set(review());
  });
});
after(cleanup);

describe('reviews — read', () => {
  test('any signed-in user reads — ratings drive Explore', async () => {
    const db = await as('rider2');
    await assertSucceeds(db.collection('reviews').doc('r1').get());
  });

  test('the whole collection is listable — ratingsProvider snapshots it', async () => {
    const db = await as('rider2');
    await assertSucceeds(db.collection('reviews').get());
  });

  test('DENY a signed-out visitor', async () => {
    const db = await anon();
    await assertFails(db.collection('reviews').doc('r1').get());
  });
});

describe('reviews — create', () => {
  test('a rider writes a review under their own uid', async () => {
    const db = await as('rider');
    await assertSucceeds(db.collection('reviews').doc('n1').set(review()));
  });

  test('DENY writing a review under someone elses uid', async () => {
    const db = await as('rider');
    await assertFails(db.collection('reviews').doc('n1').set(review({ userId: 'rider2' })));
  });

  // Rating bounds — both edges and both sides of each edge.
  test('rating 1 is accepted', async () => {
    const db = await as('rider');
    await assertSucceeds(db.collection('reviews').doc('n1').set(review({ rating: 1 })));
  });

  test('rating 5 is accepted', async () => {
    const db = await as('rider');
    await assertSucceeds(db.collection('reviews').doc('n1').set(review({ rating: 5 })));
  });

  test('DENY rating 0', async () => {
    const db = await as('rider');
    await assertFails(db.collection('reviews').doc('n1').set(review({ rating: 0 })));
  });

  test('DENY rating 6', async () => {
    const db = await as('rider');
    await assertFails(db.collection('reviews').doc('n1').set(review({ rating: 6 })));
  });

  test('DENY a negative rating', async () => {
    const db = await as('rider');
    await assertFails(db.collection('reviews').doc('n1').set(review({ rating: -5 })));
  });

  test('DENY a rating that is a string', async () => {
    const db = await as('rider');
    await assertFails(db.collection('reviews').doc('n1').set(review({ rating: '5' })));
  });

  test('DENY a fractional rating', async () => {
    // `rating is int` — 4.5 is a double and must not pass.
    const db = await as('rider');
    await assertFails(db.collection('reviews').doc('n1').set(review({ rating: 4.5 })));
  });

  test('DENY a review with no rating field', async () => {
    const doc = review();
    delete doc.rating;
    const db = await as('rider');
    await assertFails(db.collection('reviews').doc('n1').set(doc));
  });

  test('DENY a signed-out visitor', async () => {
    const db = await anon();
    await assertFails(db.collection('reviews').doc('n1').set(review()));
  });
});

describe('reviews — update and delete', () => {
  test('DENY the author editing their own review', async () => {
    const db = await as('rider');
    await assertFails(db.collection('reviews').doc('r1').update({ rating: 1 }));
  });

  test('DENY staff editing a review', async () => {
    const db = await as('admin');
    await assertFails(db.collection('reviews').doc('r1').update({ comment: 'edited' }));
  });

  test('the author deletes their own review', async () => {
    const db = await as('rider');
    await assertSucceeds(db.collection('reviews').doc('r1').delete());
  });

  test('staff deletes any review', async () => {
    const db = await as('admin');
    await assertSucceeds(db.collection('reviews').doc('r1').delete());
  });

  test('DENY the reviewed trainer deleting a bad review of themselves', async () => {
    const db = await as('trainer');
    await assertFails(db.collection('reviews').doc('r1').delete());
  });

  test('DENY an unrelated rider deleting', async () => {
    const db = await as('rider2');
    await assertFails(db.collection('reviews').doc('r1').delete());
  });
});

describe('reviews — what the rules deliberately do not enforce', () => {
  // These pass by design: the rules pin authorship and range, and the
  // repository owns eligibility. Pinned so the boundary is explicit — if any
  // of these ever starts failing, the enforcement model changed.
  // Logged as BUG-004; the exposure is that none of this holds for a client
  // that talks to Firestore directly instead of through the app.

  test('a review can be written with no booking behind it at all', async () => {
    const db = await as('rider2');
    await assertSucceeds(
      db.collection('reviews').doc('n2').set(review({ userId: 'rider2', bookingId: 'does-not-exist' })),
    );
  });

  test('two reviews can be written for the same bookingId', async () => {
    const db = await as('rider');
    await assertSucceeds(db.collection('reviews').doc('n2').set(review()));
    await assertSucceeds(db.collection('reviews').doc('n3').set(review()));
  });

  test('a trainer can review themselves', async () => {
    const db = await as('trainer');
    await assertSucceeds(
      db.collection('reviews').doc('n2').set(review({ userId: 'trainer', trainerId: 'trainer' })),
    );
  });

  test('a blocked user can still write a review', async () => {
    const db = await as('blocked');
    await assertSucceeds(
      db.collection('reviews').doc('n2').set(review({ userId: 'blocked' })),
    );
  });
});
