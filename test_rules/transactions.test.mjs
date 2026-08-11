// Transactional isolation, against real Firestore on the emulator.
//
// This file exists because the Dart suite cannot answer the question.
// fake_cloud_firestore's runTransaction has no isolation: two concurrent
// transactions that each read a counter and write read+1 land on 1, not 2.
// Any test there asserting "concurrent writers cannot oversell" is testing
// the double, and will report a bug that does not exist (or, worse, pass a
// guard that was never there).
//
// So the two concurrency claims in §8.6 are settled here instead:
//
//   * safari seats ARE locked — the count lives on one known document, so a
//     transaction can re-read it and refuse;
//   * hourly bookings are NOT — a transaction cannot read a query, so the
//     clash check is a re-query before the write and two riders in the same
//     instant both land.
//
// These exercise the *pattern* the repository uses, not the Dart code, which
// cannot reach an emulator from `flutter test`. That distinction is recorded
// in COVERAGE.md rather than glossed.

import { test, describe, before, beforeEach, after } from 'node:test';
import assert from 'node:assert/strict';
import { reset, cleanup, testEnv } from './helpers.mjs';

before(async () => { await testEnv(); });
beforeEach(reset);
after(cleanup);

/// Runs `fn` with a rules-free handle. The work has to happen *inside* the
/// callback — withSecurityRulesDisabled terminates the client when it
/// returns, so a handle carried out of it throws "client already terminated".
/// This file is about concurrency, not authorisation, hence rules off.
function withDb(fn) {
  return testEnv().then((e) =>
    e.withSecurityRulesDisabled((ctx) => fn(ctx.firestore())));
}

/// The seat reservation exactly as reserveSafariSeat shapes it: re-read
/// capacity inside the transaction and refuse when the trip is full.
const reserveSeat = (d, trip) => d.runTransaction(async (tx) => {
  const snap = await tx.get(trip);
  const { capacity, bookedSeats } = snap.data();
  if (capacity > 0 && bookedSeats >= capacity) throw new Error('full');
  tx.update(trip, {
    bookedSeats: bookedSeats + 1,
    status: capacity > 0 && bookedSeats + 1 >= capacity ? 'full' : 'open',
  });
});

describe('real Firestore transactions', () => {
  test('two concurrent increments both land — the baseline the fake fails',
    () => withDb(async (d) => {
      const ref = d.collection('counters').doc('c1');
      await ref.set({ n: 0 });

      await Promise.all([0, 1].map(() => d.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        tx.update(ref, { n: snap.data().n + 1 });
      })));

      assert.equal((await ref.get()).data().n, 2,
        'real Firestore retries the losing transaction; the fake loses it');
    }));

  test('safari seats: three riders, two seats, one is refused',
    () => withDb(async (d) => {
      const trip = d.collection('safari_trips').doc('t1');
      await trip.set({ hostId: 'trainer', capacity: 2, bookedSeats: 0, status: 'open' });

      const results = await Promise.allSettled([
        reserveSeat(d, trip), reserveSeat(d, trip), reserveSeat(d, trip),
      ]);
      const ok = results.filter((r) => r.status === 'fulfilled');

      assert.equal(ok.length, 2, 'exactly the two real seats were sold');
      const after = (await trip.get()).data();
      assert.equal(after.bookedSeats, 2);
      assert.equal(after.status, 'full');
    }));

  test('an uncapped trip (capacity 0) never refuses',
    () => withDb(async (d) => {
      const trip = d.collection('safari_trips').doc('t1');
      await trip.set({ hostId: 'trainer', capacity: 0, bookedSeats: 0, status: 'open' });

      const results = await Promise.allSettled([
        reserveSeat(d, trip), reserveSeat(d, trip), reserveSeat(d, trip),
      ]);

      assert.equal(results.filter((r) => r.status === 'fulfilled').length, 3);
      assert.equal((await trip.get()).data().bookedSeats, 3);
    }));

  test('hourly bookings: two riders in the same instant BOTH land (§8.6)',
    () => withDb(async (d) => {
      // The documented trade-off, confirmed against real Firestore rather
      // than inferred. A transaction cannot read a query, so this is a
      // re-query then a write — and neither writer sees the other.
      const bookIfFree = async (rider) => {
        const clash = await d.collection('bookings')
          .where('instructorId', '==', 'trainer')
          .where('date', '==', '2099-06-15')
          .get();
        const taken = new Set();
        for (const doc of clash.docs) {
          const b = doc.data();
          if (['pending', 'confirmed', 'in_progress'].includes(b.status)) {
            (b.selectedTimes ?? []).forEach((t) => taken.add(t));
          }
        }
        if (taken.has('10:00')) throw new Error('taken');
        await d.collection('bookings').doc(`b-${rider}`).set({
          instructorId: 'trainer', kiterId: rider, date: '2099-06-15',
          selectedTimes: ['10:00'], status: 'pending',
        });
      };

      const results = await Promise.allSettled([
        bookIfFree('r1'), bookIfFree('r2'),
      ]);

      assert.equal(results.filter((r) => r.status === 'fulfilled').length, 2,
        'both land — this is the documented behaviour, not a defect');
      const all = await d.collection('bookings').get();
      assert.equal(all.size, 2);
      assert.ok(all.docs.every((doc) => doc.data().status === 'pending'),
        'neither is confirmed; the trainer declines one');
    }));

  test('sequentially, the landed booking is visible to the next check',
    () => withDb(async (d) => {
      await d.collection('bookings').doc('b1').set({
        instructorId: 'trainer', kiterId: 'r1', date: '2099-06-15',
        selectedTimes: ['10:00'], status: 'pending',
      });

      const clash = await d.collection('bookings')
        .where('instructorId', '==', 'trainer')
        .where('date', '==', '2099-06-15')
        .get();
      const taken = new Set(clash.docs.flatMap((doc) => doc.data().selectedTimes));

      assert.ok(taken.has('10:00'));
    }));
});
