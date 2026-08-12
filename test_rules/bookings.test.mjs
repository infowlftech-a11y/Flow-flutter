// firestore.rules — match /bookings/{bookingId}  (lines 81-126)
//
// Two parties, one document, and money on it. The rules have to let the rider
// cancel and the trainer run the session, while stopping either from writing
// the other's business. Every allow below is paired with the denial that gives
// it meaning.

import { test, describe, before, beforeEach, after } from 'node:test';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { as, anon, reset, seed, cleanup, testEnv, bookingDoc } from './helpers.mjs';

before(async () => { await testEnv(); });
beforeEach(async () => {
  await reset();
  await seed(async (db) => {
    await db.collection('bookings').doc('b1').set(bookingDoc());
  });
});
after(cleanup);

describe('bookings — read (line 102)', () => {
  test('the rider on the booking reads it', async () => {
    const db = await as('rider');
    await assertSucceeds(db.collection('bookings').doc('b1').get());
  });

  test('the trainer on the booking reads it', async () => {
    const db = await as('trainer');
    await assertSucceeds(db.collection('bookings').doc('b1').get());
  });

  test('staff reads any booking', async () => {
    const db = await as('admin');
    await assertSucceeds(db.collection('bookings').doc('b1').get());
  });

  test('DENY a signed-out visitor', async () => {
    const db = await anon();
    await assertFails(db.collection('bookings').doc('b1').get());
  });

  test('a rider lists their own bookings via the kiterId filter', async () => {
    const db = await as('rider');
    await assertSucceeds(db.collection('bookings').where('kiterId', '==', 'rider').get());
  });

  test('a trainer lists their own via the instructorId filter', async () => {
    const db = await as('trainer');
    await assertSucceeds(
      db.collection('bookings').where('instructorId', '==', 'trainer').get(),
    );
  });

  // ⚠ These four assert the TEMPORARY state of BUG-017, not the intended one.
  // While `allow read: if signedIn()` stands, a booking is readable by any
  // signed-in account. Each one flips back to assertFails when the `occupied`
  // availability documents land and the rule is restored — they are the
  // checklist for that revert, which is why they say so out loud rather than
  // being deleted.
  test('TEMPORARY (BUG-017): an unrelated rider can read a booking', async () => {
    const db = await as('rider2');
    await assertSucceeds(db.collection('bookings').doc('b1').get());
  });

  test('TEMPORARY (BUG-017): an unrelated trainer can read a booking', async () => {
    const db = await as('trainer2');
    await assertSucceeds(db.collection('bookings').doc('b1').get());
  });

  test('TEMPORARY (BUG-017): the whole collection is listable', async () => {
    const db = await as('rider');
    await assertSucceeds(db.collection('bookings').get());
  });

  test("TEMPORARY (BUG-017): a rider can filter on another rider's kiterId",
    async () => {
      const db = await as('rider');
      await assertSucceeds(
        db.collection('bookings').where('kiterId', '==', 'rider2').get(),
      );
    });
});

describe('bookings — create (lines 107-111)', () => {
  test('a rider creates their own unpaid booking', async () => {
    const db = await as('rider');
    await assertSucceeds(
      db.collection('bookings').doc('n1').set(bookingDoc({ id: 'n1' })),
    );
  });

  test('DENY a rider creating a booking already marked paid', async () => {
    const db = await as('rider');
    await assertFails(
      db.collection('bookings').doc('n1').set(bookingDoc({ id: 'n1', paymentStatus: 'paid' })),
    );
  });

  test('DENY a rider creating a booking with no paymentStatus at all', async () => {
    const doc = bookingDoc({ id: 'n1' });
    delete doc.paymentStatus;
    const db = await as('rider');
    await assertFails(db.collection('bookings').doc('n1').set(doc));
  });

  test('DENY a rider creating a booking in another riders name', async () => {
    const db = await as('rider');
    await assertFails(
      db.collection('bookings').doc('n1').set(bookingDoc({ id: 'n1', kiterId: 'rider2' })),
    );
  });

  test('a trainer creates a walk-in and may record cash taken', async () => {
    const db = await as('trainer');
    await assertSucceeds(
      db.collection('bookings').doc('n1').set(bookingDoc({
        id: 'n1', kiterId: 'manual_entry', status: 'confirmed', paymentStatus: 'paid',
        type: 'manual', studentLevel: 'Walk-in',
      })),
    );
  });

  test('DENY a trainer creating a walk-in on another trainers calendar', async () => {
    const db = await as('trainer2');
    await assertFails(
      db.collection('bookings').doc('n1').set(bookingDoc({
        id: 'n1', kiterId: 'manual_entry', status: 'confirmed', paymentStatus: 'paid',
      })),
    );
  });

  test('DENY a booking naming neither the creator as rider nor as trainer', async () => {
    const db = await as('rider2');
    await assertFails(db.collection('bookings').doc('n1').set(bookingDoc({ id: 'n1' })));
  });

  test('DENY a signed-out visitor creating a booking', async () => {
    const db = await anon();
    await assertFails(db.collection('bookings').doc('n1').set(bookingDoc({ id: 'n1' })));
  });
});

describe('bookings — update, the trainer (lines 120-123)', () => {
  test('the trainer approves', async () => {
    const db = await as('trainer');
    await assertSucceeds(db.collection('bookings').doc('b1').update({ status: 'confirmed' }));
  });

  test('the trainer declines', async () => {
    const db = await as('trainer');
    await assertSucceeds(db.collection('bookings').doc('b1').update({ status: 'rejected' }));
  });

  test('the trainer checks the rider in', async () => {
    const db = await as('trainer');
    await assertSucceeds(db.collection('bookings').doc('b1').update({
      status: 'in_progress', checkedIn: true, startedAt: new Date().toISOString(),
    }));
  });

  test('the trainer marks it paid — they are the one owed', async () => {
    const db = await as('trainer');
    await assertSucceeds(db.collection('bookings').doc('b1').update({ paymentStatus: 'paid' }));
  });

  test('DENY another trainer touching the booking', async () => {
    const db = await as('trainer2');
    await assertFails(db.collection('bookings').doc('b1').update({ status: 'confirmed' }));
  });
});

describe('bookings — update, the rider (lines 120-123)', () => {
  test('the rider cancels', async () => {
    const db = await as('rider');
    await assertSucceeds(db.collection('bookings').doc('b1').update({
      status: 'cancelled', cancelledAt: new Date().toISOString(), cancelledBy: 'user',
    }));
  });

  test('the rider hides a booking from their own history', async () => {
    const db = await as('rider');
    await assertSucceeds(db.collection('bookings').doc('b1').update({ hiddenByGuest: true }));
  });

  // paymentFieldsUnchanged() — one denial per named field (lines 96-100).
  for (const [field, value] of [
    ['paymentStatus', 'paid'],
    ['paymentMethod', 'cash'],
    ['paidAt', '2026-08-14'],
    ['refundedAt', '2026-08-14'],
    ['paymentRef', 'ref-1'],
    ['amountDue', 0],
    ['currency', 'USD'],
    ['totalPrice', 1],
  ]) {
    test(`DENY the rider writing ${field}`, async () => {
      const db = await as('rider');
      await assertFails(db.collection('bookings').doc('b1').update({ [field]: value }));
    });
  }

  test('DENY the rider zeroing the price alongside a legitimate cancel', async () => {
    const db = await as('rider');
    await assertFails(db.collection('bookings').doc('b1').update({
      status: 'cancelled', totalPrice: 0,
    }));
  });

  test('DENY an unrelated rider updating', async () => {
    const db = await as('rider2');
    await assertFails(db.collection('bookings').doc('b1').update({ status: 'cancelled' }));
  });

  // --- The escalation the prompt named. -------------------------------------
  // A rider is a party, and `status` is not a payment field, so the current
  // rule permits this. Asserted as a denial because that is the intended
  // behaviour; a failure here is a real defect, logged in BUGS.md.
  test('DENY the rider approving their own pending booking', async () => {
    const db = await as('rider');
    await assertFails(db.collection('bookings').doc('b1').update({ status: 'confirmed' }));
  });

  test('DENY the rider checking themselves in', async () => {
    const db = await as('rider');
    await assertFails(db.collection('bookings').doc('b1').update({
      status: 'in_progress', checkedIn: true,
    }));
  });

  test('DENY the rider marking their own session completed', async () => {
    const db = await as('rider');
    await assertFails(db.collection('bookings').doc('b1').update({ status: 'completed' }));
  });

  test('DENY the rider moving the session to another day', async () => {
    const db = await as('rider');
    await assertFails(db.collection('bookings').doc('b1').update({ date: '2026-09-01' }));
  });

  test('DENY the rider reassigning the booking to another trainer', async () => {
    const db = await as('rider');
    await assertFails(db.collection('bookings').doc('b1').update({ instructorId: 'trainer2' }));
  });
});

describe('bookings — update, staff and delete (lines 120-125)', () => {
  test('staff updates any booking', async () => {
    const db = await as('admin');
    await assertSucceeds(db.collection('bookings').doc('b1').update({ status: 'cancelled' }));
  });

  test('staff deletes a booking', async () => {
    const db = await as('admin');
    await assertSucceeds(db.collection('bookings').doc('b1').delete());
  });

  test('DENY the rider deleting', async () => {
    const db = await as('rider');
    await assertFails(db.collection('bookings').doc('b1').delete());
  });

  test('DENY the trainer deleting', async () => {
    const db = await as('trainer');
    await assertFails(db.collection('bookings').doc('b1').delete());
  });

  test('DENY a signed-out visitor deleting', async () => {
    const db = await anon();
    await assertFails(db.collection('bookings').doc('b1').delete());
  });

  test('a signed-in user with no profile is denied, not thrown at (lines 116-119)', async () => {
    // The comment above the rule records that evaluating isStaff() first threw
    // outright for a profile-less user instead of denying. This pins the order.
    const db = await as('noProfile');
    await assertFails(db.collection('bookings').doc('b1').update({ status: 'confirmed' }));
  });
});
