// firestore.rules — notifications, safari_trips, the catch-all, and what a
// blocked account can still reach.
//
// The last group is not a rule block: it is the question flow 6 asks. The
// rules never inspect `status`, so blocking is enforced entirely by the
// client's gate routing. These tests establish exactly how far that goes.

import { test, describe, before, beforeEach, after } from 'node:test';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { as, anon, reset, seed, cleanup, testEnv, bookingDoc } from './helpers.mjs';

before(async () => { await testEnv(); });
beforeEach(async () => {
  await reset();
  await seed(async (db) => {
    await db.collection('notifications').doc('n1').set({
      targetUserId: 'rider', userId: 'rider', title: 'Booking approved',
      message: 'Confirmed', type: 'booking_confirmed', read: false,
    });
    await db.collection('safari_trips').doc('s1').set({
      hostId: 'trainer', title: 'Red Sea downwinder', capacity: 6,
      bookedSeats: 0, status: 'open', price: 300,
    });
    await db.collection('bookings').doc('b1').set(bookingDoc());
    await db.collection('chats').doc('c1').set({ participants: ['blocked', 'trainer'] });
  });
});
after(cleanup);

describe('notifications', () => {
  test('the recipient reads their own', async () => {
    const db = await as('rider');
    await assertSucceeds(db.collection('notifications').doc('n1').get());
  });

  test('the recipient marks it read (§10.6, fire-and-forget)', async () => {
    const db = await as('rider');
    await assertSucceeds(db.collection('notifications').doc('n1').update({ read: true }));
  });

  test('the recipient deletes it', async () => {
    const db = await as('rider');
    await assertSucceeds(db.collection('notifications').doc('n1').delete());
  });

  test('DENY another user reading it', async () => {
    const db = await as('rider2');
    await assertFails(db.collection('notifications').doc('n1').get());
  });

  test('DENY another user marking it read', async () => {
    const db = await as('rider2');
    await assertFails(db.collection('notifications').doc('n1').update({ read: true }));
  });

  test('staff reads notifications', async () => {
    const db = await as('admin');
    await assertSucceeds(db.collection('notifications').doc('n1').get());
  });

  test('the listener query filters on targetUserId (§6.2)', async () => {
    const db = await as('rider');
    await assertSucceeds(
      db.collection('notifications').where('targetUserId', '==', 'rider').get(),
    );
  });

  test('DENY listing another users notifications', async () => {
    const db = await as('rider2');
    await assertFails(
      db.collection('notifications').where('targetUserId', '==', 'rider').get(),
    );
  });

  test('a trainer notifies a rider — the app notifies the other party', async () => {
    const db = await as('trainer');
    await assertSucceeds(
      db.collection('notifications').doc('n2').set({
        targetUserId: 'rider', userId: 'rider', title: 'Booking approved ✅',
        message: 'Confirmed', type: 'booking_confirmed', read: false,
      }),
    );
  });

  // Pinned, not asserted as a denial: `allow create: if signedIn()` is
  // deliberate (the comment explains it), but it does mean any account can
  // write any notification to any user. Logged as BUG-005.
  test('any signed-in user can write a notification to anyone', async () => {
    const db = await as('rider2');
    await assertSucceeds(
      db.collection('notifications').doc('n2').set({
        targetUserId: 'trainer', userId: 'trainer', title: 'Booking cancelled',
        message: 'Spoofed', type: 'booking_cancelled', read: false,
      }),
    );
  });

  test('DENY a signed-out visitor creating one', async () => {
    const db = await anon();
    await assertFails(
      db.collection('notifications').doc('n2').set({ targetUserId: 'rider', title: 'x' }),
    );
  });
});

describe('safari_trips', () => {
  test('any signed-in user reads a trip', async () => {
    const db = await as('rider');
    await assertSucceeds(db.collection('safari_trips').doc('s1').get());
  });

  test('the host creates a trip', async () => {
    const db = await as('trainer');
    await assertSucceeds(
      db.collection('safari_trips').doc('s2').set({ hostId: 'trainer', title: 'Trip', capacity: 4 }),
    );
  });

  test('DENY creating a trip hosted by someone else', async () => {
    const db = await as('rider');
    await assertFails(
      db.collection('safari_trips').doc('s2').set({ hostId: 'trainer', title: 'Trip' }),
    );
  });

  test('a rider increments bookedSeats — the reservation transaction (§8.6)', async () => {
    const db = await as('rider');
    await assertSucceeds(
      db.collection('safari_trips').doc('s1').update({ bookedSeats: 1, status: 'open' }),
    );
  });

  test('the host deletes their trip', async () => {
    const db = await as('trainer');
    await assertSucceeds(db.collection('safari_trips').doc('s1').delete());
  });

  test('staff deletes a trip', async () => {
    const db = await as('admin');
    await assertSucceeds(db.collection('safari_trips').doc('s1').delete());
  });

  test('DENY a rider deleting a trip', async () => {
    const db = await as('rider');
    await assertFails(db.collection('safari_trips').doc('s1').delete());
  });

  test('DENY a signed-out visitor reading', async () => {
    const db = await anon();
    await assertFails(db.collection('safari_trips').doc('s1').get());
  });

  // `allow update: if signedIn()` is wide open by necessity — the seat count
  // lives on this document and the reserving rider must increment it. It also
  // means any signed-in user can rewrite any field. Logged as BUG-006.
  test('any signed-in user can rewrite a trips price and capacity', async () => {
    const db = await as('rider2');
    await assertSucceeds(
      db.collection('safari_trips').doc('s1').update({ price: 0, capacity: 999 }),
    );
  });
});

describe('the catch-all (deny by default)', () => {
  for (const col of ['listings', 'broadcasts', 'admin', 'config', 'secrets']) {
    test(`DENY reading an undeclared collection: ${col}`, async () => {
      const db = await as('admin');
      await assertFails(db.collection(col).doc('x').get());
    });

    test(`DENY writing an undeclared collection: ${col}`, async () => {
      const db = await as('admin');
      await assertFails(db.collection(col).doc('x').set({ a: 1 }));
    });
  }

  test('DENY an undeclared sub-collection under a users document', async () => {
    const db = await as('trainer');
    await assertFails(
      db.collection('users').doc('trainer').collection('private_notes').doc('x').set({ a: 1 }),
    );
  });
});

describe('what a blocked account can still reach', () => {
  // The rules never read `status`, so suspension is a client-side gate only.
  // Each of these is a real capability a blocked user retains at the API.
  // Logged as BUG-007. Asserted as successes because that is the current
  // truth — if any starts failing, enforcement moved and this must be revised.

  test('a blocked user reads profiles', async () => {
    const db = await as('blocked');
    await assertSucceeds(db.collection('users').doc('trainer').get());
  });

  test('a blocked user creates a booking', async () => {
    const db = await as('blocked');
    await assertSucceeds(
      db.collection('bookings').doc('nb').set(bookingDoc({ id: 'nb', kiterId: 'blocked' })),
    );
  });

  test('a blocked user sends a chat message', async () => {
    const db = await as('blocked');
    await assertSucceeds(
      db.collection('chats').doc('c1').collection('messages').doc('m1')
        .set({ senderId: 'blocked', receiverId: 'trainer', text: 'hi', read: false }),
    );
  });

  test('a blocked user files a report', async () => {
    const db = await as('blocked');
    await assertSucceeds(
      db.collection('reports').doc('rp9').set({ reporterId: 'blocked', reportedUserId: 'trainer', reason: 'Other' }),
    );
  });

  test('a blocked user files an appeal — intended (§3.12)', async () => {
    const db = await as('blocked');
    await assertSucceeds(
      db.collection('appeals').doc('ap9').set({ userId: 'blocked', reason: 'Please', status: 'pending' }),
    );
  });

  test('a blocked user still cannot lift their own block', async () => {
    const db = await as('blocked');
    await assertFails(db.collection('users').doc('blocked').update({ status: 'active' }));
  });

  test('a rejected trainer still cannot self-approve', async () => {
    const db = await as('rejectedTrainer');
    await assertFails(
      db.collection('users').doc('rejectedTrainer').update({ status: 'active' }),
    );
  });
});
