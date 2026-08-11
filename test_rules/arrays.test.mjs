// Firestore semantics the Dart double gets wrong, settled against the real
// thing. Each of these decides whether an app behaviour is what the blueprint
// says, and fake_cloud_firestore answers all three differently from Firestore.
//
// Like transactions.test.mjs, these exercise the *pattern* the repositories
// use rather than the Dart code itself.

import { test, describe, before, beforeEach, after } from 'node:test';
import assert from 'node:assert/strict';
import { reset, cleanup, testEnv } from './helpers.mjs';

before(async () => { await testEnv(); });
beforeEach(reset);
after(cleanup);

function withDb(fn) {
  return testEnv().then((e) =>
    e.withSecurityRulesDisabled((ctx) => fn(ctx.firestore())));
}

describe('arrayUnion, as the appeal thread uses it (§6.3)', () => {
  test('both sides append without dropping each other', () => withDb(async (d) => {
    const { arrayUnion } = await import('firebase/firestore');
    const ref = d.collection('appeals').doc('ap1');
    await ref.set({ userId: 'blocked', status: 'pending', messages: [] });

    await ref.update({ messages: arrayUnion({ senderId: 'blocked', text: 'Any news?' }) });
    await ref.update({ messages: arrayUnion({ senderId: 'admin', text: 'Reviewing.' }) });
    await ref.update({ messages: arrayUnion({ senderId: 'blocked', text: 'Thanks.' }) });

    const msgs = (await ref.get()).data().messages;
    assert.equal(msgs.length, 3);
    assert.deepEqual(msgs.map((m) => m.senderId), ['blocked', 'admin', 'blocked']);
  }));

  test('an identical reply sent twice appears ONCE — arrayUnion is a set',
    () => withDb(async (d) => {
      // Worth knowing: to the user this looks like a lost message. Real
      // AppealMessage payloads carry an id and timestamp, which is what keeps
      // two genuine repeats distinct — so the collapse only bites when those
      // are absent or equal.
      const { arrayUnion } = await import('firebase/firestore');
      const ref = d.collection('appeals').doc('ap1');
      await ref.set({ userId: 'blocked', status: 'pending', messages: [] });

      const same = { senderId: 'blocked', text: 'Hello?' };
      await ref.update({ messages: arrayUnion(same) });
      await ref.update({ messages: arrayUnion(same) });

      assert.equal((await ref.get()).data().messages.length, 1,
        'de-duplicated by value; fake_cloud_firestore appends both');
    }));

  test('the same text with a distinct id stays two messages',
    () => withDb(async (d) => {
      const { arrayUnion } = await import('firebase/firestore');
      const ref = d.collection('appeals').doc('ap1');
      await ref.set({ userId: 'blocked', status: 'pending', messages: [] });

      await ref.update({ messages: arrayUnion({ id: 'm1', senderId: 'blocked', text: 'Hello?' }) });
      await ref.update({ messages: arrayUnion({ id: 'm2', senderId: 'blocked', text: 'Hello?' }) });

      assert.equal((await ref.get()).data().messages.length, 2,
        'AppealMessage carries an id, so genuine repeats survive');
    }));
});

describe('a transactional update of a missing document', () => {
  test('is rejected — blockUser cannot resurrect a deleted account',
    () => withDb(async (d) => {
      const ref = d.collection('users').doc('deleted-account');

      await assert.rejects(
        d.runTransaction(async (tx) => {
          const snap = await tx.get(ref);
          tx.update(ref, { status: 'blocked', statusBeforeBlock: snap.data()?.status });
        }),
        'real Firestore raises NOT_FOUND; the fake creates the document',
      );

      assert.equal((await ref.get()).exists, false,
        'no ghost profile left behind');
    }));
});
