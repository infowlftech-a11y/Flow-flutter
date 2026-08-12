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
    // idFor() sorts the pair, so this is the thread between rider and trainer.
    await db.collection('chats').doc('rider_trainer')
      .set({ participants: ['rider', 'trainer'] });
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

  test('a trainer notifies their rider about their shared booking', async () => {
    // The app's real shape: every booking notification names the booking,
    // and the rule verifies both people are its parties.
    const db = await as('trainer');
    await assertSucceeds(
      db.collection('notifications').doc('n2').set({
        targetUserId: 'rider', title: 'Booking approved ✅',
        message: 'Confirmed', type: 'booking_confirmed', read: false,
        bookingId: 'b1',
      }),
    );
  });

  test('the rider notifies the trainer — the request direction', async () => {
    const db = await as('rider');
    await assertSucceeds(
      db.collection('notifications').doc('n2').set({
        targetUserId: 'trainer', title: 'New booking request',
        message: 'Seif requested an hour.', type: 'booking_request',
        read: false, bookingId: 'b1',
      }),
    );
  });

  test('a chat message notifies the other participant', async () => {
    const db = await as('rider');
    await assertSucceeds(
      db.collection('notifications').doc('n2').set({
        targetUserId: 'trainer', title: 'Message from Seif',
        message: 'hey', type: 'message', read: false,
      }),
    );
  });

  test('staff notify anyone — the approval and suspension paths', async () => {
    const db = await as('admin');
    await assertSucceeds(
      db.collection('notifications').doc('n2').set({
        targetUserId: 'pendingTrainer', title: "You're live on Flow 🤙",
        message: 'Approved.', type: 'account_approved', read: false,
      }),
    );
  });

  // BUG-005 — this exact write used to succeed, pinned under "any signed-in
  // user can write a notification to anyone". A stranger's "Booking
  // cancelled" rendered identically to a genuine one.
  test('DENY a stranger spoofing a booking notification', async () => {
    const db = await as('rider2');
    await assertFails(
      db.collection('notifications').doc('n2').set({
        targetUserId: 'trainer', title: 'Booking cancelled',
        message: 'Spoofed', type: 'booking_cancelled', read: false,
      }),
    );
  });

  test("DENY citing a booking the sender is not a party to", async () => {
    // b1 is rider ↔ trainer. rider2 cannot ride it into either inbox.
    const db = await as('rider2');
    await assertFails(
      db.collection('notifications').doc('n2').set({
        targetUserId: 'trainer', title: 'Booking cancelled',
        message: 'Spoofed', type: 'booking_cancelled', read: false,
        bookingId: 'b1',
      }),
    );
  });

  test('DENY a message notification with no thread behind it', async () => {
    const db = await as('rider2');
    await assertFails(
      db.collection('notifications').doc('n2').set({
        targetUserId: 'rider', title: 'Message from X',
        message: 'spam', type: 'message', read: false,
      }),
    );
  });

  test('DENY writing a notification to yourself', async () => {
    // No app path does this; a self-write is someone manufacturing evidence.
    const db = await as('rider');
    await assertFails(
      db.collection('notifications').doc('n2').set({
        targetUserId: 'rider', title: 'Booking approved ✅',
        message: 'x', type: 'booking_confirmed', read: false,
        bookingId: 'b1',
      }),
    );
  });

  test('a blocked rider cancelling still warns the trainer', async () => {
    // Deliberately NOT notBlocked(): the cancel is permitted, so its warning
    // must be too — otherwise the calendar frees silently.
    await seed(async (db) => {
      await db.collection('bookings').doc('b2').set(
        bookingDoc({ id: 'b2', kiterId: 'blocked', status: 'confirmed' }));
    });
    const db = await as('blocked');
    await assertSucceeds(
      db.collection('notifications').doc('n2').set({
        targetUserId: 'trainer', title: 'Rider cancelled ⚠️',
        message: 'Cancelled.', type: 'booking_cancelled', read: false,
        bookingId: 'b2',
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

  test('the last seat flips the trip to full', async () => {
    await seed(async (db) => {
      await db.collection('safari_trips').doc('s1')
        .update({ bookedSeats: 5 });
    });
    const db = await as('rider');
    await assertSucceeds(
      db.collection('safari_trips').doc('s1')
        .update({ bookedSeats: 6, status: 'full' }),
    );
  });

  test('a cancel releases one seat and reopens the trip', async () => {
    await seed(async (db) => {
      await db.collection('safari_trips').doc('s1')
        .update({ bookedSeats: 6, status: 'full' });
    });
    const db = await as('rider');
    await assertSucceeds(
      db.collection('safari_trips').doc('s1')
        .update({ bookedSeats: 5, status: 'open' }),
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

  // BUG-006 — `allow update: if signedIn()` authorised every field, and this
  // exact write used to succeed. A non-host may now move only the seat count
  // (one at a time, inside capacity) and the open/full flag.
  test('DENY a stranger rewriting a trips price and capacity', async () => {
    const db = await as('rider2');
    await assertFails(
      db.collection('safari_trips').doc('s1').update({ price: 0, capacity: 999 }),
    );
  });

  test('DENY a seat increment that smuggles a price change beside it', async () => {
    const db = await as('rider2');
    await assertFails(
      db.collection('safari_trips').doc('s1')
        .update({ bookedSeats: 1, status: 'open', price: 0 }),
    );
  });

  test('DENY taking two seats in one write', async () => {
    // Every legitimate call — reserve and cancel — moves exactly one seat.
    const db = await as('rider2');
    await assertFails(
      db.collection('safari_trips').doc('s1').update({ bookedSeats: 2 }),
    );
  });

  test('DENY incrementing past capacity', async () => {
    await seed(async (db) => {
      await db.collection('safari_trips').doc('s1').update({ bookedSeats: 6 });
    });
    const db = await as('rider2');
    await assertFails(
      db.collection('safari_trips').doc('s1').update({ bookedSeats: 7 }),
    );
  });

  test('DENY driving the seat count negative', async () => {
    const db = await as('rider2');
    await assertFails(
      db.collection('safari_trips').doc('s1').update({ bookedSeats: -1 }),
    );
  });

  test('DENY a non-host writing a status outside open/full', async () => {
    const db = await as('rider2');
    await assertFails(
      db.collection('safari_trips').doc('s1').update({ status: 'cancelled' }),
    );
  });

  test('the host still edits their own trip freely', async () => {
    const db = await as('trainer');
    await assertSucceeds(
      db.collection('safari_trips').doc('s1').update({ price: 350, capacity: 8 }),
    );
  });

  test('staff still edit any trip', async () => {
    const db = await as('admin');
    await assertSucceeds(
      db.collection('safari_trips').doc('s1').update({ status: 'cancelled' }),
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

describe('a blocked account is stopped at the API, not just in the UI', () => {
  // BUG-007. Nothing read `status` before, so a suspension was enforced by
  // the client's routing alone — which stops the app from *offering* an
  // action, not from performing it.

  test('DENY a blocked user creating a booking', async () => {
    const db = await as('blocked');
    await assertFails(
      db.collection('bookings').doc('nb').set(bookingDoc({ id: 'nb', kiterId: 'blocked' })),
    );
  });

  test('DENY a blocked user opening a chat thread', async () => {
    const db = await as('blocked');
    await assertFails(
      db.collection('chats').doc('c2').set({ participants: ['blocked', 'trainer2'] }),
    );
  });

  test('DENY a blocked user sending a chat message', async () => {
    // The highest-harm case: the usual reasons for a block are
    // "Inappropriate behavior" and "Safety concerns", and this is the path
    // straight back to the person who reported them.
    const db = await as('blocked');
    await assertFails(
      db.collection('chats').doc('c1').collection('messages').doc('m1')
        .set({ senderId: 'blocked', receiverId: 'trainer', text: 'hi', read: false }),
    );
  });

  test('DENY a blocked user posting a review', async () => {
    const db = await as('blocked');
    await assertFails(
      db.collection('reviews').doc('r9').set({
        trainerId: 'trainer', userId: 'blocked', userName: 'B',
        rating: 1, comment: '', bookingId: 'b1',
      }),
    );
  });

  test('DENY a blocked user filing a report', async () => {
    const db = await as('blocked');
    await assertFails(
      db.collection('reports').doc('rp9')
        .set({ reporterId: 'blocked', reportedUserId: 'trainer', reason: 'Other' }),
    );
  });
});

describe('…and keeps everything a suspension must not take away', () => {
  test('a blocked user files an appeal — the point of a suspension (§3.12)',
    async () => {
      const db = await as('blocked');
      await assertSucceeds(
        db.collection('appeals').doc('ap9')
          .set({ userId: 'blocked', reason: 'Please', status: 'pending' }),
      );
    });

  test('a blocked user opens a support ticket', async () => {
    const db = await as('blocked');
    await assertSucceeds(
      db.collection('tickets').doc('t9')
        .set({ userId: 'blocked', subject: 'Help', status: 'open' }),
    );
  });

  test('a blocked user reads profiles — they can still see the app', async () => {
    const db = await as('blocked');
    await assertSucceeds(db.collection('users').doc('trainer').get());
  });

  test('a blocked rider can still CANCEL an existing booking', async () => {
    // Load-bearing. If a suspension froze their bookings, a blocked rider
    // would hold a trainer's calendar hostage until it lifted.
    await seed(async (db) => {
      await db.collection('bookings').doc('b2')
        .set(bookingDoc({ id: 'b2', kiterId: 'blocked', status: 'confirmed' }));
    });
    const db = await as('blocked');
    await assertSucceeds(db.collection('bookings').doc('b2').update({
      status: 'cancelled', cancelledAt: 'now', cancelledBy: 'user',
    }));
  });

  test('a blocked user can still delete their account (§3.13)', async () => {
    const db = await as('blocked');
    await assertSucceeds(db.collection('users').doc('blocked').delete());
  });

  test('a blocked user can still record why they left', async () => {
    const db = await as('blocked');
    await assertSucceeds(
      db.collection('leave_reasons').doc('l9')
        .set({ userId: 'blocked', reason: 'Done with it' }),
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

describe('notBlocked() fails closed', () => {
  test('DENY a signed-in user with no profile document creating a booking',
    async () => {
      // Mid-onboarding there is no users/{uid} yet. Onboarding writes the
      // profile before anything else, so nothing legitimate is caught here —
      // and a missing profile must never read as "not blocked".
      const db = await as('noProfile');
      await assertFails(
        db.collection('bookings').doc('nb')
          .set(bookingDoc({ id: 'nb', kiterId: 'noProfile' })),
      );
    });

  test('an active user with a profile is unaffected', async () => {
    const db = await as('rider2');
    await assertSucceeds(
      db.collection('bookings').doc('nb')
        .set(bookingDoc({ id: 'nb', kiterId: 'rider2' })),
    );
  });

  test('a pending trainer is not blocked — pending is not blocked', async () => {
    const db = await as('pendingTrainer');
    await assertSucceeds(
      db.collection('chats').doc('c3')
        .set({ participants: ['pendingTrainer', 'rider'] }),
    );
  });
});
