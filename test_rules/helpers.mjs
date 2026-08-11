// Shared harness for the firestore.rules suite.
//
// These tests run against the Firestore emulator, which is the only place the
// rules are actually executed. The Dart suite uses fake_cloud_firestore, which
// ignores rules entirely — so every "a rider cannot do X" claim in the app is
// unverified until it is asserted here.
//
// Run:  cd test_rules && npm test
//
// Note on seeding: isStaff() and privilegedFieldsUnchanged() resolve through a
// get() on users/{uid}. Any actor whose request hits one of those needs a
// profile document, so ACTORS below is seeded before every test.

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { initializeTestEnvironment } from '@firebase/rules-unit-testing';

const here = dirname(fileURLToPath(import.meta.url));

/// Every actor the suite needs, and the profile document each one gets.
/// `noProfile` is deliberately absent from this map: a signed-in user with no
/// users/{uid} document is a real state (it exists between sign-up and the end
/// of onboarding) and several rules resolve differently for them.
export const ACTORS = {
  rider: { role: 'kiter', status: 'active', name: 'Rider One' },
  rider2: { role: 'kiter', status: 'active', name: 'Rider Two' },
  trainer: { role: 'business', status: 'active', name: 'Trainer One' },
  trainer2: { role: 'business', status: 'active', name: 'Trainer Two' },
  pendingTrainer: { role: 'business', status: 'pending', name: 'Pending Coach' },
  rejectedTrainer: { role: 'business', status: 'rejected', name: 'Rejected Coach' },
  blocked: { role: 'kiter', status: 'blocked', name: 'Blocked Rider' },
  admin: { role: 'admin', status: 'active', name: 'Admin' },
  owner: { role: 'owner', status: 'active', name: 'Owner' },
  support: { role: 'support', status: 'active', name: 'Support' },
};

let env;

export async function testEnv() {
  env ??= await initializeTestEnvironment({
    projectId: 'wlf-flow',
    firestore: {
      rules: readFileSync(join(here, '..', 'firestore.rules'), 'utf8'),
    },
  });
  return env;
}

/// Wipes Firestore and re-seeds every actor's profile. Call in beforeEach so
/// no test can pass because of a document another test left behind.
export async function reset() {
  const e = await testEnv();
  await e.clearFirestore();
  await e.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    for (const [uid, doc] of Object.entries(ACTORS)) {
      await db.collection('users').doc(uid).set({ ...doc, email: `${uid}@test.dev` });
    }
  });
}

/// Firestore handle for a signed-in user.
export async function as(uid) {
  const e = await testEnv();
  return e.authenticatedContext(uid).firestore();
}

/// Firestore handle for a signed-out visitor.
export async function anon() {
  const e = await testEnv();
  return e.unauthenticatedContext().firestore();
}

/// Seeds documents bypassing rules — the arrange step, never the assertion.
export async function seed(fn) {
  const e = await testEnv();
  await e.withSecurityRulesDisabled(async (ctx) => fn(ctx.firestore()));
}

export async function cleanup() {
  if (env) await env.cleanup();
  env = undefined;
}

/// A booking document in the shape createBooking actually writes (§6.3), so
/// rules are tested against real payloads rather than minimal stand-ins.
export function bookingDoc(overrides = {}) {
  return {
    id: 'b1',
    instructorId: 'trainer',
    instructorName: 'Trainer One',
    kiterId: 'rider',
    guestId: 'rider',
    studentName: 'Rider One',
    studentLevel: 'Rider',
    listingTitle: 'Trainer — Lesson',
    serviceName: 'Lesson',
    date: '2026-08-14',
    time: '09:00',
    startTime: '09:00',
    endTime: '11:00',
    bufferedEndTime: '12:00',
    selectedTimes: ['09:00', '10:00'],
    durationHours: 2,
    price: 240,
    totalPrice: 240,
    type: 'lesson',
    bookingType: 'lesson',
    gearNeeded: false,
    message: '',
    status: 'pending',
    paymentStatus: 'unpaid',
    ...overrides,
  };
}
