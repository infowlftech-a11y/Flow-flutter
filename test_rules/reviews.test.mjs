// firestore.rules — match /reviews/{reviewId}
//
// The rules pin authorship, the 1-5 range, and — since BUG-004 — the §8.9
// eligibility facts, by reading the named booking: it completed, the author
// was the rider on it, and it was with this trainer. What they still cannot
// pin is one-review-per-booking (that needs a deterministic review id, a
// document-shape change); the repository holds that line, and the last test
// keeps the gap visible rather than assumed.

import { test, describe, before, beforeEach, after } from 'node:test';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { as, anon, reset, seed, cleanup, testEnv, bookingDoc } from './helpers.mjs';

const review = (o = {}) => ({
  trainerId: 'trainer', userId: 'rider', userName: 'Rider One',
  rating: 5, comment: 'Great', bookingId: 'b1', ...o,
});

before(async () => { await testEnv(); });
beforeEach(async () => {
  await reset();
  await seed(async (db) => {
    // The booking that earns the review: completed, rider with trainer.
    await db.collection('bookings').doc('b1').set(
      bookingDoc({ id: 'b1', status: 'completed' }));
    // A second rider's completed booking, for authorship cross-checks.
    await db.collection('bookings').doc('b2').set(
      bookingDoc({ id: 'b2', kiterId: 'rider2', status: 'completed' }));
    // One still pending — training that has not happened yet.
    await db.collection('bookings').doc('pending1').set(
      bookingDoc({ id: 'pending1', status: 'pending' }));
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

describe('reviews — eligibility is enforced at the API (BUG-004)', () => {
  // Each of these used to pass, pinned under "what the rules deliberately do
  // not enforce". The enforcement model changed on purpose: a rating that
  // drives Explore has to hold against a direct Firestore client, not only
  // against the app's own repository.

  test('DENY a review with no booking behind it at all', async () => {
    const db = await as('rider2');
    await assertFails(
      db.collection('reviews').doc('n2')
        .set(review({ userId: 'rider2', bookingId: 'does-not-exist' })),
    );
  });

  test('DENY a review with no bookingId field at all', async () => {
    const doc = review();
    delete doc.bookingId;
    const db = await as('rider');
    await assertFails(db.collection('reviews').doc('n2').set(doc));
  });

  test('DENY a trainer reviewing themselves', async () => {
    const db = await as('trainer');
    await assertFails(
      db.collection('reviews').doc('n2')
        .set(review({ userId: 'trainer', trainerId: 'trainer' })),
    );
  });

  test("DENY reviewing on the back of someone else's booking", async () => {
    // b2 completed, but its rider is rider2 — this author never trained.
    const db = await as('rider');
    await assertFails(
      db.collection('reviews').doc('n2').set(review({ bookingId: 'b2' })),
    );
  });

  test('DENY reviewing a session that has not happened (§8.9)', async () => {
    const db = await as('rider');
    await assertFails(
      db.collection('reviews').doc('n2').set(review({ bookingId: 'pending1' })),
    );
  });

  test('DENY pointing the review at a trainer the booking does not name',
    async () => {
      // A completed booking with `trainer` must not mint a rating for
      // `trainer2`.
      const db = await as('rider');
      await assertFails(
        db.collection('reviews').doc('n2')
          .set(review({ trainerId: 'trainer2' })),
      );
    });

  // Still open, and pinned so the boundary stays visible: one-review-per-
  // booking needs a deterministic review id (a shape change). The
  // repository's re-check is the only guard. If this ever starts failing,
  // the enforcement model changed again — update BUGS.md BUG-004.
  test('two reviews for the same bookingId still pass the rules', async () => {
    const db = await as('rider');
    await assertSucceeds(db.collection('reviews').doc('n2').set(review()));
    await assertSucceeds(db.collection('reviews').doc('n3').set(review()));
  });

  // "a blocked user can still write a review" used to live here, pinning
  // BUG-007. It no longer holds: notBlocked() guards this create, and the
  // denial is asserted in misc.test.mjs alongside the rest of the
  // suspension surface.
});
