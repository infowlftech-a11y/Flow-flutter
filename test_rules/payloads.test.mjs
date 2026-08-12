// Do the app's REAL write payloads pass the REAL rules?
//
// COVERAGE.md's largest gap: the rules are verified on the emulator, the
// repositories against a fake, and nothing joins them. A rule can be correct
// and still reject the app, and no test in either suite would notice.
//
// These payloads are transcribed field for field from the repositories — not
// approximated — so a rule that is too tight fails here instead of on a
// beach. Each one names its source.

import { test, describe, before, beforeEach, after } from 'node:test';
import { assertSucceeds } from '@firebase/rules-unit-testing';
import { as, reset, seed, cleanup, testEnv } from './helpers.mjs';

before(async () => { await testEnv(); });
beforeEach(reset);
after(cleanup);

// BookingRepository.createBooking, lib/data/repositories/booking_repository.dart
// — including ...PaymentInfo.initialFields(amount:), which expands to the four
// payment keys below (payment.dart:169-179).
const createBookingPayload = (riderUid) => ({
  id: 'doc1',
  instructorId: 'trainer',
  instructorName: 'Anna',
  kiterId: riderUid,
  studentName: 'Seif',
  studentLevel: 'Independent',
  listingTitle: 'Anna',
  date: '2099-06-15',
  startTime: '09:00',
  endTime: '11:00',
  bufferedEndTime: '12:00',
  selectedTimes: ['09:00', '10:00'],
  durationHours: 2,
  totalPrice: 170,
  type: 'lesson',
  gearNeeded: false,
  message: '',
  status: 'pending',
  paymentStatus: 'unpaid',
  paymentMethod: 'cash',
  currency: 'EUR',
  amountDue: 170,
  createdAt: new Date().toISOString(),
});

describe('the real createBooking payload', () => {
  test('an active rider can write it', async () => {
    const db = await as('rider');
    await assertSucceeds(
      db.collection('bookings').doc('doc1').set(createBookingPayload('rider')),
    );
  });

  test('a rider whose profile has only the onboarding fields can write it',
    async () => {
      // createRiderProfile writes through `compact`, which drops nulls — so a
      // rider who skipped the optional fields has a sparser document than the
      // seeded one. notBlocked() reads `status`, which is always present.
      await seed(async (db) => {
        await db.collection('users').doc('sparse').set({
          name: 'Sparse', email: 's@test.dev', role: 'kiter', status: 'active',
          nationality: 'Egyptian', age: 22, level: 'Independent',
          languages: ['English'], quiver: [], favorites: [],
        });
      });
      const db = await as('sparse');
      await assertSucceeds(
        db.collection('bookings').doc('doc1').set(createBookingPayload('sparse')),
      );
    });

  test('a pending trainer can still book a lesson as a rider would', async () => {
    // Not blocked, so nothing stops them buying a lesson from someone else.
    const db = await as('pendingTrainer');
    await assertSucceeds(
      db.collection('bookings').doc('doc1')
        .set(createBookingPayload('pendingTrainer')),
    );
  });
});

// BookingRepository.createWalkIn — same shape, kiterId 'manual_entry',
// status 'confirmed', and the trainer may record cash taken up front.
describe('the real createWalkIn payload', () => {
  test('the trainer can write it', async () => {
    const db = await as('trainer');
    await assertSucceeds(db.collection('bookings').doc('doc1').set({
      id: 'doc1',
      instructorId: 'trainer',
      instructorName: 'Anna',
      kiterId: 'manual_entry',
      studentName: 'Beach walk-up',
      studentLevel: 'Walk-in',
      listingTitle: 'Private lesson (walk-in)',
      date: '2099-06-15',
      startTime: '14:00',
      endTime: '15:00',
      bufferedEndTime: '16:00',
      selectedTimes: ['14:00'],
      durationHours: 1,
      totalPrice: 85,
      type: 'manual',
      gearNeeded: false,
      message: '',
      status: 'confirmed',
      paymentStatus: 'unpaid',
      paymentMethod: 'cash',
      currency: 'EUR',
      amountDue: 85,
      createdAt: new Date().toISOString(),
    }));
  });
});

// UserRepository.createRiderProfile / createTrainerProfile.
describe('the real onboarding payloads', () => {
  test('createRiderProfile', async () => {
    const db = await as('newRider');
    await assertSucceeds(db.collection('users').doc('newRider').set({
      name: 'Seif', email: 'n@test.dev', role: 'kiter', status: 'active',
      nationality: 'Egyptian', age: 22, level: 'Independent',
      homeSpot: 'El Gouna', languages: ['English'], quiver: ['12m'],
      bio: 'hi', photoURL: 'https://example.test/a.jpg', favorites: [],
      createdAt: new Date().toISOString(),
    }));
  });

  test('createTrainerProfile', async () => {
    const db = await as('newCoach');
    await assertSucceeds(db.collection('users').doc('newCoach').set({
      name: 'Anna', email: 'c@test.dev', role: 'business', status: 'pending',
      businessType: 'Instructor', bio: 'IKO coach',
      languages: ['English'], location: 'El Gouna', hourlyRate: 85,
      ikoId: 'IKO-1', photoURL: 'https://example.test/a.jpg',
      gallery: [], favorites: [], createdAt: new Date().toISOString(),
    }));
  });
});

// AdminRepository.approveTrainer — the write that makes a trainer bookable.
describe('the real approval payload', () => {
  test('admin approving a pending trainer', async () => {
    const db = await as('admin');
    await assertSucceeds(db.collection('users').doc('pendingTrainer').update({
      status: 'active',
      reviewedAt: new Date().toISOString(),
    }));
  });
});

// BookingRepository.cancelByRider and NotificationRepository.notify.
describe('the real rider-cancel and notify payloads', () => {
  test('cancelByRider', async () => {
    await seed(async (db) => {
      await db.collection('bookings').doc('doc1')
        .set(createBookingPayload('rider'));
    });
    const db = await as('rider');
    await assertSucceeds(db.collection('bookings').doc('doc1').update({
      status: 'cancelled',
      cancelledAt: new Date().toISOString(),
      cancelledBy: 'user',
    }));
  });

  test('notify, as the rider notifying the trainer of a new request',
    async () => {
      const db = await as('rider');
      await assertSucceeds(db.collection('notifications').doc('n1').set({
        targetUserId: 'trainer',
        title: 'New booking request',
        message: 'Seif requested 15 Jun at 09:00.',
        type: 'booking_request',
        read: false,
        createdAt: new Date().toISOString(),
        bookingId: 'doc1',
      }));
    });
});
