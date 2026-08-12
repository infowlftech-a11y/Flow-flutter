// The reads a rider performs on the way to making a booking.
//
// Every one of these runs before any write. A denial here surfaces in the app
// as "You don't have access to this yet." (§10.3, permission-denied) on a
// screen whose slots rendered perfectly — which is exactly what a rider
// reported (BUG-017).
//
// The shape that caused it: bookings are readable per-document by their own
// parties, and rules cannot see query filters, so the grid's
// `instructorId + date` query over *bookings* is unauthorisable for a rider.
// The fix is that the grid and the clash re-check read `availability` — the
// trainer's host blocks plus the `occupied` doc every live booking maintains
// (§8.5). This file asserts the queries the app now actually issues, and pins
// that the old bookings-shaped query stays denied for a rider — the app must
// treat that denial as "not my calendar", never widen the rule again.

import { test, describe, before, beforeEach, after } from 'node:test';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { as, anon, reset, seed, cleanup, testEnv, bookingDoc } from './helpers.mjs';

before(async () => { await testEnv(); });
beforeEach(async () => {
  await reset();
  await seed(async (db) => {
    // Someone else's booking with this trainer, on the day being viewed —
    // and the occupied doc it maintains, which is all a stranger may see.
    await db.collection('bookings').doc('other').set(bookingDoc({
      id: 'other', kiterId: 'rider2', date: '2099-06-15',
    }));
    await db.collection('availability').doc('other').set({
      instructorId: 'trainer', date: '2099-06-15', startTime: '09:00',
      endTime: '11:00', status: 'occupied', label: 'Booked',
    });
    await db.collection('availability').doc('a1').set({
      instructorId: 'trainer', date: '2099-06-15', startTime: '12:00',
      endTime: '13:00', status: 'host-blocked',
    });
    await db.collection('vacations').doc('v1').set({
      instructorId: 'trainer', startDate: '2099-09-01', endDate: '2099-09-07',
    });
  });
});
after(cleanup);

describe('the booking grid — dayAvailabilityProvider, three streams', () => {
  test('blocks + occupied: a rider reads the trainers availability for the day',
    async () => {
      const db = await as('rider');
      await assertSucceeds(
        db.collection('availability')
          .where('instructorId', '==', 'trainer')
          .where('date', '==', '2099-06-15')
          .get(),
      );
    });

  test('vacations: a rider reads the trainers vacations', async () => {
    const db = await as('rider');
    await assertSucceeds(
      db.collection('vacations').where('instructorId', '==', 'trainer').get(),
    );
  });

  test('bookings: DENIED for a rider — the provider degrades to the occupied '
    + 'docs instead', async () => {
    // watchDayBookings still runs for the trainer's own calendar. For anyone
    // else dayAvailabilityProvider treats this exact denial as "no bookings
    // visible"; the same hours arrived through the occupied doc above.
    const db = await as('rider');
    await assertFails(
      db.collection('bookings')
        .where('instructorId', '==', 'trainer')
        .where('date', '==', '2099-06-15')
        .get(),
    );
  });

  test('bookings: the trainer still reads their own day', async () => {
    const db = await as('trainer');
    await assertSucceeds(
      db.collection('bookings')
        .where('instructorId', '==', 'trainer')
        .where('date', '==', '2099-06-15')
        .get(),
    );
  });

  test('bookings: staff still read any day', async () => {
    const db = await as('admin');
    await assertSucceeds(
      db.collection('bookings')
        .where('instructorId', '==', 'trainer')
        .where('date', '==', '2099-06-15')
        .get(),
    );
  });
});

describe('the clash re-check — _assertSlotsFree, immediately before the write',
  () => {
    test('a rider can run its availability half', async () => {
      const db = await as('rider');
      await assertSucceeds(
        db.collection('availability')
          .where('instructorId', '==', 'trainer')
          .where('date', '==', '2099-06-15')
          .get(),
      );
    });

    test('the trainer can run its bookings half for their own calendar',
      async () => {
        const db = await as('trainer');
        await assertSucceeds(
          db.collection('bookings')
            .where('instructorId', '==', 'trainer')
            .where('date', '==', '2099-06-15')
            .get(),
        );
      });

    test('DENY a signed-out visitor reading availability', async () => {
      const db = await anon();
      await assertFails(
        db.collection('availability')
          .where('instructorId', '==', 'trainer')
          .where('date', '==', '2099-06-15')
          .get(),
      );
    });
  });

describe('what the occupied doc leaks — nothing but the hours', () => {
  test('the doc a stranger can read carries no rider identity', async () => {
    // Not a rules assertion — a schema one, pinned where the privacy
    // property is earned. If someone adds the rider's name to the occupied
    // doc "for convenience", this is the test that notices.
    const db = await as('rider');
    const snap = await db.collection('availability').doc('other').get();
    const keys = Object.keys(snap.data()).sort();
    for (const forbidden of
        ['kiterId', 'studentName', 'message', 'totalPrice', 'price']) {
      if (keys.includes(forbidden)) {
        throw new Error(`occupied doc leaks ${forbidden}`);
      }
    }
  });
});
