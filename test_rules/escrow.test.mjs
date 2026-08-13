// The money's API surface — full-audit pass, 2026-08-13.
//
// P1 made every escrow judgement a *derivation*: CancellationPolicy.settle
// reads booking status, cancelledBy and cancelledAt, and reports what the
// held money becomes. That moved the money question onto fields these rules
// were letting either party write freely — the repository's _writeIfLive,
// markPaid and reserveSafariSeat guards bind the app, not a hand-rolled
// client. Each group below is one way a raw SDK could bend the derivation,
// written as the denial the rules must produce (BUG-019…BUG-024).
//
// What is deliberately NOT asserted here: pinning cancelledAt to
// request.time. cancellation.dart documents the timestamp's honesty as the
// processor's to verify; BUG-019's terminal guard closes the worst case
// (backdating a completed booking), and the residual free-window edge is
// left as the owner's call — see the NOTE in BUGS.md.

import { test, describe, before, beforeEach, after } from 'node:test';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import firebase from 'firebase/compat/app';
import 'firebase/compat/firestore';
import { as, reset, seed, cleanup, testEnv, bookingDoc } from './helpers.mjs';

const { FieldValue, Timestamp } = firebase.firestore;

/// What the repository writes: a server timestamp, which the rules see as
/// request.time.
const now = () => FieldValue.serverTimestamp();

/// A stamp from before any plausible free-cancel deadline. Used only to seed
/// already-cancelled fixtures, never as the thing under test.
const backdated = () => Timestamp.fromDate(new Date('2026-01-01T10:00:00Z'));

before(async () => { await testEnv(); });
beforeEach(async () => {
  await reset();
  await seed(async (db) => {
    // One booking per interesting starting state, all escrow-held.
    const held = { paymentStatus: 'held', paymentMethod: 'app' };
    await db.collection('bookings').doc('live').set(
      bookingDoc({ id: 'live', status: 'confirmed', ...held }));
    await db.collection('bookings').doc('waiting').set(
      bookingDoc({ id: 'waiting', status: 'pending', ...held }));
    await db.collection('bookings').doc('running').set(
      bookingDoc({ id: 'running', status: 'in_progress', ...held }));
    await db.collection('bookings').doc('done').set(
      bookingDoc({ id: 'done', status: 'completed', ...held }));
    await db.collection('bookings').doc('dead').set(
      bookingDoc({ id: 'dead', status: 'cancelled', cancelledBy: 'user',
        cancelledAt: backdated(), ...held }));
    await db.collection('bookings').doc('cash').set(
      bookingDoc({ id: 'cash', status: 'completed' })); // unpaid cash
    await db.collection('bookings').doc('settled').set(
      bookingDoc({ id: 'settled', status: 'completed',
        paymentStatus: 'paid', paidAt: backdated() }));
    // The safari fixture: a published trip with free seats, host = trainer,
    // who has never enabled Instant Book (no safari host needs to).
    await db.collection('safari_trips').doc('t1').set({
      hostId: 'trainer', title: 'Sunset safari', price: 90,
      capacity: 8, bookedSeats: 2, status: 'open',
    });
  });
});
after(cleanup);

const cancelAsRider = (extra = {}) => ({
  status: 'cancelled',
  cancelledAt: now(),
  cancelledBy: 'user',
  ...extra,
});

const booking = (db, id) => db.collection('bookings').doc(id);

describe('escrow — terminal states are terminal at the API (BUG-019)', () => {
  test('DENY the rider cancelling a completed session — the refund theft',
    async () => {
      // completed + held reads as payoutDue; cancelled-by-user-in-time reads
      // as refundDue. This single write moves the whole session price from
      // the trainer to the rider.
      const db = await as('rider');
      await assertFails(booking(db, 'done').update(cancelAsRider()));
    });

  test('DENY the trainer completing a cancelled booking — the payout theft',
    async () => {
      const db = await as('trainer');
      await assertFails(booking(db, 'dead')
        .update({ status: 'completed', updatedAt: now() }));
    });

  test('DENY the trainer resurrecting a cancelled booking to confirmed',
    async () => {
      const db = await as('trainer');
      await assertFails(booking(db, 'dead')
        .update({ status: 'confirmed', updatedAt: now() }));
    });

  test('staff may move history — the dispute door stays open', async () => {
    const db = await as('admin');
    await assertSucceeds(booking(db, 'dead')
      .update({ status: 'confirmed', updatedAt: now() }));
  });

  // The transitions the app actually performs, pinned so the guard can
  // never eat them.
  test('the rider still cancels a pending request', async () => {
    const db = await as('rider');
    await assertSucceeds(booking(db, 'waiting').update(cancelAsRider()));
  });

  test('the rider still cancels a confirmed session', async () => {
    const db = await as('rider');
    await assertSucceeds(booking(db, 'live').update(cancelAsRider()));
  });

  test('the trainer still approves, and UNDO still un-approves', async () => {
    const db = await as('trainer');
    await assertSucceeds(booking(db, 'waiting')
      .update({ status: 'confirmed', updatedAt: now() }));
    await assertSucceeds(booking(db, 'waiting')
      .update({ status: 'pending', updatedAt: now() }));
  });

  test('the trainer still declines, checks in, and completes', async () => {
    const db = await as('trainer');
    await assertSucceeds(booking(db, 'waiting')
      .update({ status: 'rejected', updatedAt: now() }));
    await assertSucceeds(booking(db, 'live').update({ status: 'in_progress',
      checkedIn: true, startedAt: now(), updatedAt: now() }));
    await assertSucceeds(booking(db, 'running')
      .update({ status: 'completed', updatedAt: now() }));
  });

  test('settlement and hiding still land on a completed booking', async () => {
    // The guard bites only writes that MOVE status; these write other fields
    // on a terminal booking and must not be caught.
    const rider = await as('rider');
    await assertSucceeds(booking(rider, 'done').update({ hiddenByGuest: true }));
    const trainer = await as('trainer');
    await assertSucceeds(
      booking(trainer, 'done').update({ hiddenByInstructor: true }));
  });

  test('the rider cancel still needs its stamp present', async () => {
    // Presence is still pinned (BUG-001); only the timestamp's *value* is
    // left to the processor.
    const db = await as('rider');
    await assertFails(booking(db, 'live')
      .update({ status: 'cancelled', cancelledBy: 'user' }));
  });
});

describe('escrow — a provider cancel signs itself provider (BUG-020)', () => {
  test("DENY the trainer signing their own cancel as the rider's", async () => {
    // cancelledBy decides who the money favours: 'provider' refunds in full,
    // a late 'user' charges in full. A trainer writing 'user' with a late
    // stamp is paid for a session they withdrew.
    const db = await as('trainer');
    await assertFails(booking(db, 'live').update({
      status: 'cancelled', cancelledBy: 'user',
      cancelledAt: now(), updatedAt: now(),
    }));
  });

  test('DENY a trainer cancel that names no canceller at all', async () => {
    const db = await as('trainer');
    await assertFails(
      booking(db, 'live').update({ status: 'cancelled', updatedAt: now() }));
  });

  test('the trainer still cancels, signed provider', async () => {
    const db = await as('trainer');
    await assertSucceeds(booking(db, 'live').update({
      status: 'cancelled', cancelledBy: 'provider',
      cancelledAt: now(), updatedAt: now(),
    }));
  });
});

describe("escrow — held money is FLOW's to execute (BUG-021)", () => {
  test('DENY the trainer writing paid_out — forging the transfer', async () => {
    // paid_out means "FLOW actually moved the money to the trainer" and is
    // written by the processor/Functions layer or staff, never a party.
    const db = await as('trainer');
    await assertFails(booking(db, 'done')
      .update({ paymentStatus: 'paid_out', updatedAt: now() }));
  });

  test('DENY the trainer collecting a held payment as cash', async () => {
    // markPaid refuses this with "FLOW holds this payment"; the API must too.
    const db = await as('trainer');
    await assertFails(booking(db, 'done').update({
      paymentStatus: 'paid', paymentMethod: 'cash',
      paidAt: now(), updatedAt: now(),
    }));
  });

  test('DENY the trainer marking held money refunded — forging the refund',
    async () => {
      const db = await as('trainer');
      await assertFails(booking(db, 'done').update({
        paymentStatus: 'refunded', refundedAt: now(), updatedAt: now() }));
    });

  test('DENY the trainer writing paid_out on a cash booking', async () => {
    const db = await as('trainer');
    await assertFails(booking(db, 'cash')
      .update({ paymentStatus: 'paid_out', updatedAt: now() }));
  });

  test("the cash ledger still settles — markPaid's shape", async () => {
    const db = await as('trainer');
    await assertSucceeds(booking(db, 'cash').update({
      paymentStatus: 'paid', paymentMethod: 'cash',
      paidAt: now(), updatedAt: now(),
    }));
  });

  test("a settled cash booking still refunds — markRefunded's shape",
    async () => {
      const db = await as('trainer');
      await assertSucceeds(booking(db, 'settled').update({
        paymentStatus: 'refunded', refundedAt: now(), updatedAt: now() }));
    });

  test('staff still execute the escrow — paid_out from held', async () => {
    const db = await as('admin');
    await assertSucceeds(booking(db, 'done')
      .update({ paymentStatus: 'paid_out', updatedAt: now() }));
  });
});

describe('escrow — a safari seat is not an instant lesson (BUG-022)', () => {
  // reserveSafariSeat writes the booking born 'confirmed' inside the same
  // transaction that moves the seat count. P5's instant-book constraint on
  // 'confirmed' creates forgot this path: with no instantBook flag on the
  // host, the pre-fix rules denied the create and no rider could reserve a
  // seat on live Firestore at all.
  const seatBooking = (overrides = {}) => bookingDoc({
    id: 'sb1', tripId: 't1', tripTitle: 'Sunset safari',
    listingTitle: 'Expedition: Sunset safari', type: 'safari',
    status: 'confirmed', durationHours: 0, totalPrice: 90,
    paymentStatus: 'held', paymentMethod: 'app',
    paidAt: now(), createdAt: now(), ...overrides,
  });

  test('the reservation lands — booking and seat move in one commit',
    async () => {
      const db = await as('rider');
      const batch = db.batch();
      batch.update(db.collection('safari_trips').doc('t1'),
        { bookedSeats: 3, status: 'open' });
      batch.set(db.collection('bookings').doc('sb1'), seatBooking());
      await assertSucceeds(batch.commit());
    });

  test('DENY the ghost passenger — a seat booking that moves no seat',
    async () => {
      // Without the seat move in the same commit, the manifest under-counts
      // and the trip oversells honestly-booked riders (BUG-006 residue,
      // now closed).
      const db = await as('rider');
      await assertFails(
        db.collection('bookings').doc('sb1').set(seatBooking()));
    });

  test("DENY a 'safari' booking naming a trip the instructor does not host",
    async () => {
      await seed(async (db) => {
        await db.collection('safari_trips').doc('t2').set({
          hostId: 'trainer2', title: 'Other', price: 50,
          capacity: 4, bookedSeats: 0, status: 'open',
        });
      });
      const db = await as('rider');
      const batch = db.batch();
      batch.update(db.collection('safari_trips').doc('t2'),
        { bookedSeats: 1, status: 'open' });
      // instructorId still 'trainer' (bookingDoc default) but the trip is
      // trainer2's — a seat taken on one manifest, a booking on another.
      batch.set(db.collection('bookings').doc('sb1'),
        seatBooking({ tripId: 't2' }));
      await assertFails(batch.commit());
    });

  test("hourly instant booking still needs the trainer's flag", async () => {
    const db = await as('rider');
    await assertFails(db.collection('bookings').doc('n1').set(bookingDoc({
      id: 'n1', status: 'confirmed',
      paymentStatus: 'held', paymentMethod: 'app',
    })));
  });

  test('hourly instant booking lands once the trainer opted in', async () => {
    await seed(async (db) => {
      await db.collection('users').doc('trainer')
        .set({ instantBook: true }, { merge: true });
    });
    const db = await as('rider');
    await assertSucceeds(db.collection('bookings').doc('n1').set(bookingDoc({
      id: 'n1', status: 'confirmed',
      paymentStatus: 'held', paymentMethod: 'app',
      paidAt: now(), createdAt: now(),
    })));
  });
});

describe('safari trips — publishing needs a live business (BUG-024)', () => {
  const trip = (hostId) => ({
    hostId, title: 'New trip', price: 70,
    capacity: 6, bookedSeats: 0, status: 'open',
  });

  test('DENY a blocked account publishing a trip', async () => {
    const db = await as('blocked');
    await assertFails(
      db.collection('safari_trips').doc('nt').set(trip('blocked')));
  });

  test('DENY a rider publishing a trip', async () => {
    const db = await as('rider');
    await assertFails(
      db.collection('safari_trips').doc('nt').set(trip('rider')));
  });

  test('DENY a pending business publishing a trip', async () => {
    const db = await as('pendingTrainer');
    await assertFails(
      db.collection('safari_trips').doc('nt').set(trip('pendingTrainer')));
  });

  test('an active business still publishes its own trip', async () => {
    const db = await as('trainer');
    await assertSucceeds(
      db.collection('safari_trips').doc('nt').set(trip('trainer')));
  });
});
