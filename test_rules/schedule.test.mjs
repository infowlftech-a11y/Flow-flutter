// firestore.rules — match /availability/{docId} and /vacations/{docId}
//
// Both are trainer-owned calendar documents with near-identical rules, so the
// shared part is driven from one table. Availability docs are *blocks*
// (§8.5): their presence removes an hour, so a rider who could write one
// freely could close a competitor's calendar.
//
// The exception is the `occupied` doc — the shadow a live booking maintains
// so that riders, who cannot read the booking, still see its hours. A rider
// may write one under exactly one condition: the same atomic commit creates
// (or cancels) the booking it shadows, verified through getAfter. The last
// describe block walks that boundary.

import { test, describe, before, beforeEach, after } from 'node:test';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { as, anon, reset, seed, cleanup, testEnv, bookingDoc } from './helpers.mjs';

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

describe('occupied docs — a rider writes them only inside a booking commit',
  () => {
    const occupied = (o = {}) => ({
      instructorId: 'trainer', date: '2099-06-15', startTime: '09:00',
      endTime: '11:00', status: 'occupied', label: 'Booked', ...o,
    });

    test('createBooking: booking + occupied doc in one batch', async () => {
      // The exact commit BookingRepository.createBooking issues.
      const db = await as('rider');
      const batch = db.batch();
      batch.set(db.collection('bookings').doc('nb'),
        bookingDoc({ id: 'nb', date: '2099-06-15' }));
      batch.set(db.collection('availability').doc('nb'), occupied());
      await assertSucceeds(batch.commit());
    });

    test('DENY the occupied doc alone — no booking behind it', async () => {
      // Without the getAfter tether this would be the old hole in a new
      // place: a rider closing a competitor's hours by writing "occupied".
      const db = await as('rider');
      await assertFails(
        db.collection('availability').doc('fake').set(occupied()),
      );
    });

    test('DENY an occupied doc whose id names someone elses booking',
      async () => {
        await seed(async (db) => {
          await db.collection('bookings').doc('other').set(
            bookingDoc({ id: 'other', kiterId: 'rider2', date: '2099-06-15' }));
        });
        const db = await as('rider');
        await assertFails(
          db.collection('availability').doc('other').set(occupied()),
        );
      });

    test('DENY a batch where the occupied doc disagrees with the booking on '
      + 'the trainer', async () => {
      // The doc must block the calendar of the trainer actually booked —
      // not whichever calendar the client claims.
      const db = await as('rider');
      const batch = db.batch();
      batch.set(db.collection('bookings').doc('nb'),
        bookingDoc({ id: 'nb', date: '2099-06-15' }));
      batch.set(db.collection('availability').doc('nb'),
        occupied({ instructorId: 'trainer2' }));
      await assertFails(batch.commit());
    });

    test('cancelByRider: cancel + release in one transaction', async () => {
      await seed(async (db) => {
        await db.collection('bookings').doc('b1').set(
          bookingDoc({ id: 'b1', status: 'confirmed', date: '2099-06-15' }));
        await db.collection('availability').doc('b1').set(occupied());
      });
      const db = await as('rider');
      await assertSucceeds(db.runTransaction(async (tx) => {
        tx.update(db.collection('bookings').doc('b1'), {
          status: 'cancelled', cancelledAt: 'now', cancelledBy: 'user',
        });
        tx.delete(db.collection('availability').doc('b1'));
      }));
    });

    test('DENY the rider deleting the occupied doc without cancelling',
      async () => {
        // Freeing the hours while the booking still holds them.
        await seed(async (db) => {
          await db.collection('bookings').doc('b1').set(
            bookingDoc({ id: 'b1', status: 'confirmed', date: '2099-06-15' }));
          await db.collection('availability').doc('b1').set(occupied());
        });
        const db = await as('rider');
        await assertFails(db.collection('availability').doc('b1').delete());
      });

    test('DENY a stranger deleting an occupied doc', async () => {
      await seed(async (db) => {
        await db.collection('bookings').doc('b1').set(
          bookingDoc({ id: 'b1', date: '2099-06-15' }));
        await db.collection('availability').doc('b1').set(occupied());
      });
      const db = await as('rider2');
      await assertFails(db.collection('availability').doc('b1').delete());
    });

    test('the trainer declines: booking update + release in one transaction',
      async () => {
        await seed(async (db) => {
          await db.collection('bookings').doc('b1').set(
            bookingDoc({ id: 'b1', date: '2099-06-15' }));
          await db.collection('availability').doc('b1').set(occupied());
        });
        const db = await as('trainer');
        await assertSucceeds(db.runTransaction(async (tx) => {
          tx.update(db.collection('bookings').doc('b1'),
            { status: 'rejected', updatedAt: 'now' });
          tx.delete(db.collection('availability').doc('b1'));
        }));
      });

    test('staff may create an occupied doc directly — the backfill path',
      async () => {
        const db = await as('admin');
        await assertSucceeds(
          db.collection('availability').doc('backfill-1').set(occupied()),
        );
      });
  });
