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

  // The BUG-017 revert checklist. These four asserted the TEMPORARY
  // `allow read: if signedIn()` as assertSucceeds while nothing wrote the
  // occupied availability docs; now that those exist and the rule is
  // restored, each one flips to the denial it was always meant to be.
  test('DENY an unrelated rider reading a booking (BUG-017 reverted)', async () => {
    const db = await as('rider2');
    await assertFails(db.collection('bookings').doc('b1').get());
  });

  test('DENY an unrelated trainer reading a booking (BUG-017 reverted)', async () => {
    const db = await as('trainer2');
    await assertFails(db.collection('bookings').doc('b1').get());
  });

  test('DENY listing the whole collection (BUG-017 reverted)', async () => {
    const db = await as('rider');
    await assertFails(db.collection('bookings').get());
  });

  test("DENY filtering on another rider's kiterId (BUG-017 reverted)",
    async () => {
      const db = await as('rider');
      await assertFails(
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

  // P1 — escrow. The rider may state a hold (paid to FLOW at booking); what
  // they still may not state is that the *trainer* was settled, which is the
  // 'paid' denial above.
  test('a rider creates an escrow booking — paymentStatus held', async () => {
    const db = await as('rider');
    await assertSucceeds(
      db.collection('bookings').doc('n1').set(bookingDoc({
        id: 'n1', paymentStatus: 'held', paymentMethod: 'app',
      })),
    );
  });

  test('DENY a rider creating a booking already paid out', async () => {
    const db = await as('rider');
    await assertFails(
      db.collection('bookings').doc('n1').set(bookingDoc({ id: 'n1', paymentStatus: 'paid_out' })),
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

// P5 — Instant Book. A rider-created booking is born 'pending' unless the
// trainer's own document carries instantBook: true, in which case — and only
// in which case — it may be born 'confirmed'. Before P5 the create rule did
// not constrain status at all: any rider could self-confirm against any
// trainer with a hand-rolled client. These pin both the feature and the
// closed hole.
describe('bookings — create, Instant Book (trainerAllowsInstant)', () => {
  test('DENY a rider self-confirming against a trainer who never opted in', async () => {
    const db = await as('rider');
    await assertFails(
      db.collection('bookings').doc('n1').set(bookingDoc({
        id: 'n1', status: 'confirmed', paymentStatus: 'held', paymentMethod: 'app',
      })),
    );
  });

  test('a rider books confirmed when the trainer opted into Instant Book', async () => {
    await seed(async (db) => {
      await db.collection('users').doc('trainer').set({ instantBook: true }, { merge: true });
    });
    const db = await as('rider');
    await assertSucceeds(
      db.collection('bookings').doc('n1').set(bookingDoc({
        id: 'n1', status: 'confirmed', paymentStatus: 'held', paymentMethod: 'app',
      })),
    );
  });

  test('DENY confirmed when the trainer explicitly turned Instant Book off', async () => {
    await seed(async (db) => {
      await db.collection('users').doc('trainer').set({ instantBook: false }, { merge: true });
    });
    const db = await as('rider');
    await assertFails(
      db.collection('bookings').doc('n1').set(bookingDoc({
        id: 'n1', status: 'confirmed', paymentStatus: 'held', paymentMethod: 'app',
      })),
    );
  });

  test('DENY any other rider-written status, Instant Book or not', async () => {
    await seed(async (db) => {
      await db.collection('users').doc('trainer').set({ instantBook: true }, { merge: true });
    });
    const db = await as('rider');
    await assertFails(
      db.collection('bookings').doc('n1').set(bookingDoc({
        id: 'n1', status: 'completed', paymentStatus: 'held', paymentMethod: 'app',
      })),
    );
  });

  test('pending stays allowed regardless of the trainer flag', async () => {
    await seed(async (db) => {
      await db.collection('users').doc('trainer').set({ instantBook: true }, { merge: true });
    });
    const db = await as('rider');
    await assertSucceeds(
      db.collection('bookings').doc('n1').set(bookingDoc({
        id: 'n1', status: 'pending', paymentStatus: 'held', paymentMethod: 'app',
      })),
    );
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

  // P1 — a provider cancellation stamps itself, and the stamp is in the
  // provider's writable set. 'provider' in cancelledBy is what refunds the
  // held payment in full under the escrow derivation.
  test('the trainer cancels with the provider stamp', async () => {
    const db = await as('trainer');
    await assertSucceeds(db.collection('bookings').doc('b1').update({
      status: 'cancelled', cancelledAt: new Date().toISOString(), cancelledBy: 'provider',
      updatedAt: new Date().toISOString(),
    }));
  });

  test('DENY another trainer touching the booking', async () => {
    const db = await as('trainer2');
    await assertFails(db.collection('bookings').doc('b1').update({ status: 'confirmed' }));
  });

  // BUG-003 — `isProvider()` used to carry no field restriction at all. The
  // provider's writable set is now closed the way the rider's is, so the
  // fields that define *which session this is* cannot move.
  test('DENY the trainer reassigning the booking to another trainer', async () => {
    const db = await as('trainer');
    await assertFails(
      db.collection('bookings').doc('b1').update({ instructorId: 'trainer2' }),
    );
  });

  test('DENY the trainer moving the session to another day', async () => {
    const db = await as('trainer');
    await assertFails(
      db.collection('bookings').doc('b1').update({ date: '2026-09-01' }),
    );
  });

  test('DENY the trainer swapping the rider on the booking', async () => {
    const db = await as('trainer');
    await assertFails(
      db.collection('bookings').doc('b1').update({ kiterId: 'rider2' }),
    );
  });

  test('DENY the trainer repricing the session after the fact', async () => {
    const db = await as('trainer');
    await assertFails(
      db.collection('bookings').doc('b1').update({ totalPrice: 999 }),
    );
  });

  test('DENY the trainer rewriting the hours the rider selected', async () => {
    const db = await as('trainer');
    await assertFails(
      db.collection('bookings').doc('b1')
        .update({ selectedTimes: ['09:00'], startTime: '09:00' }),
    );
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

  // P1 — the cancellation stamps are mandatory, not polite. cancelledAt and
  // cancelledBy are what the escrow derivation reads to decide refund vs
  // charge, so a rider cancel may not exist without them, and a rider may
  // not sign one as the provider (whose cancellations always refund).
  test('DENY a rider cancel with no stamps at all', async () => {
    const db = await as('rider');
    await assertFails(db.collection('bookings').doc('b1').update({ status: 'cancelled' }));
  });

  test('DENY a rider cancel missing its cancelledAt', async () => {
    const db = await as('rider');
    await assertFails(db.collection('bookings').doc('b1').update({
      status: 'cancelled', cancelledBy: 'user',
    }));
  });

  test('DENY a rider cancel signed as the provider', async () => {
    const db = await as('rider');
    await assertFails(db.collection('bookings').doc('b1').update({
      status: 'cancelled', cancelledAt: new Date().toISOString(), cancelledBy: 'provider',
    }));
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
