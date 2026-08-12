// The reads a rider performs on the way to making a booking.
//
// Every one of these runs before any write. A denial here surfaces in the app
// as "You don't have access to this yet." (§10.3, permission-denied) on a
// screen whose slots rendered perfectly — which is exactly what a rider
// reported.

import { test, describe, before, beforeEach, after } from 'node:test';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { as, anon, reset, seed, cleanup, testEnv, bookingDoc } from './helpers.mjs';

before(async () => { await testEnv(); });
beforeEach(async () => {
  await reset();
  await seed(async (db) => {
    // Someone else's booking with this trainer, on the day being viewed.
    await db.collection('bookings').doc('other').set(bookingDoc({
      id: 'other', kiterId: 'rider2', date: '2099-06-15',
    }));
    await db.collection('availability').doc('a1').set({
      instructorId: 'trainer', date: '2099-06-15', startTime: '09:00',
      endTime: '10:00', status: 'host-blocked',
    });
    await db.collection('vacations').doc('v1').set({
      instructorId: 'trainer', startDate: '2099-09-01', endDate: '2099-09-07',
    });
  });
});
after(cleanup);

describe('the booking grid — dayAvailabilityProvider, three streams', () => {
  test('blocks: a rider reads the trainers availability for the day',
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

  test('bookings: a rider reads the trainers booked hours for the day',
    async () => {
      // watchDayBookings — the third stream. The grid cannot know which hours
      // are taken without it.
      const db = await as('rider');
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
    test('a rider can run it', async () => {
      const db = await as('rider');
      await assertSucceeds(
        db.collection('bookings')
          .where('instructorId', '==', 'trainer')
          .where('date', '==', '2099-06-15')
          .get(),
      );
    });

    test('the trainer can run it for their own calendar', async () => {
      const db = await as('trainer');
      await assertSucceeds(
        db.collection('bookings')
          .where('instructorId', '==', 'trainer')
          .where('date', '==', '2099-06-15')
          .get(),
      );
    });

    test('DENY a signed-out visitor running it', async () => {
      // The one limit the temporary BUG-017 widening keeps: it is
      // `signedIn()`, not open. The collection-listable consequence is
      // asserted in bookings.test.mjs under its TEMPORARY heading.
      const db = await anon();
      await assertFails(
        db.collection('bookings')
          .where('instructorId', '==', 'trainer')
          .where('date', '==', '2099-06-15')
          .get(),
      );
    });
  });
