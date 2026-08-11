// firestore.rules — match /chats/{chatId} and its messages sub-collection
//
// The prompt names "neither party can read a third party's chat" as a rule
// that must hold. Messages are immutable once sent, which is what makes a
// conversation evidence rather than a draft.

import { test, describe, before, beforeEach, after } from 'node:test';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { as, anon, reset, seed, cleanup, testEnv } from './helpers.mjs';

before(async () => { await testEnv(); });
beforeEach(async () => {
  await reset();
  await seed(async (db) => {
    await db.collection('chats').doc('c1').set({
      participants: ['rider', 'trainer'],
      lastMessage: 'Hi', unreadCount: { rider: 0, trainer: 1 },
    });
    await db.collection('chats').doc('c1').collection('messages').doc('m1').set({
      senderId: 'rider', receiverId: 'trainer', text: 'Hi', read: false,
    });
  });
});
after(cleanup);

describe('chats — read', () => {
  test('a participant reads the thread', async () => {
    const db = await as('rider');
    await assertSucceeds(db.collection('chats').doc('c1').get());
  });

  test('the other participant reads the thread', async () => {
    const db = await as('trainer');
    await assertSucceeds(db.collection('chats').doc('c1').get());
  });

  test('DENY a third party reading the thread', async () => {
    const db = await as('rider2');
    await assertFails(db.collection('chats').doc('c1').get());
  });

  test('DENY staff reading a private thread', async () => {
    // Staff moderate reports and appeals, not correspondence. Pinned.
    const db = await as('admin');
    await assertFails(db.collection('chats').doc('c1').get());
  });

  test('DENY a signed-out visitor', async () => {
    const db = await anon();
    await assertFails(db.collection('chats').doc('c1').get());
  });

  test('the inbox query is authorised by array-contains on self', async () => {
    const db = await as('rider');
    await assertSucceeds(
      db.collection('chats').where('participants', 'array-contains', 'rider').get(),
    );
  });

  test('DENY listing chats a user is not in', async () => {
    const db = await as('rider2');
    await assertFails(
      db.collection('chats').where('participants', 'array-contains', 'rider').get(),
    );
  });

  test('DENY listing the whole chats collection', async () => {
    const db = await as('rider');
    await assertFails(db.collection('chats').get());
  });
});

describe('chats — create', () => {
  test('a user opens a thread they are part of', async () => {
    const db = await as('rider');
    await assertSucceeds(
      db.collection('chats').doc('c2').set({ participants: ['rider', 'trainer2'] }),
    );
  });

  test('DENY creating a thread between two other people', async () => {
    const db = await as('rider2');
    await assertFails(
      db.collection('chats').doc('c2').set({ participants: ['rider', 'trainer'] }),
    );
  });

  test('DENY a thread with no participants array', async () => {
    const db = await as('rider');
    await assertFails(db.collection('chats').doc('c2').set({ lastMessage: 'x' }));
  });
});

describe('chats — update and delete', () => {
  test('a participant updates the thread — marking read (§8.11)', async () => {
    const db = await as('rider');
    await assertSucceeds(
      db.collection('chats').doc('c1').set({ unreadCount: { rider: 0 } }, { merge: true }),
    );
  });

  test('DENY a third party updating', async () => {
    const db = await as('rider2');
    await assertFails(db.collection('chats').doc('c1').update({ lastMessage: 'spoofed' }));
  });

  test('DENY deleting a thread — nobody, ever', async () => {
    const db = await as('rider');
    await assertFails(db.collection('chats').doc('c1').delete());
  });

  test('DENY staff deleting a thread', async () => {
    const db = await as('admin');
    await assertFails(db.collection('chats').doc('c1').delete());
  });
});

describe('chats/messages', () => {
  test('a participant reads messages', async () => {
    const db = await as('trainer');
    await assertSucceeds(db.collection('chats').doc('c1').collection('messages').get());
  });

  test('DENY a third party reading messages', async () => {
    const db = await as('rider2');
    await assertFails(db.collection('chats').doc('c1').collection('messages').get());
  });

  test('a participant sends a message as themselves', async () => {
    const db = await as('trainer');
    await assertSucceeds(
      db.collection('chats').doc('c1').collection('messages').doc('m2')
        .set({ senderId: 'trainer', receiverId: 'rider', text: 'Hello', read: false }),
    );
  });

  test('DENY sending a message signed as the other party', async () => {
    const db = await as('trainer');
    await assertFails(
      db.collection('chats').doc('c1').collection('messages').doc('m2')
        .set({ senderId: 'rider', receiverId: 'trainer', text: 'forged', read: false }),
    );
  });

  test('DENY a third party sending into the thread', async () => {
    const db = await as('rider2');
    await assertFails(
      db.collection('chats').doc('c1').collection('messages').doc('m2')
        .set({ senderId: 'rider2', receiverId: 'rider', text: 'spam', read: false }),
    );
  });

  test('DENY editing a sent message', async () => {
    const db = await as('rider');
    await assertFails(
      db.collection('chats').doc('c1').collection('messages').doc('m1')
        .update({ text: 'rewritten' }),
    );
  });

  test('DENY deleting a sent message', async () => {
    const db = await as('rider');
    await assertFails(
      db.collection('chats').doc('c1').collection('messages').doc('m1').delete(),
    );
  });

  test('DENY messages in a thread that does not exist', async () => {
    const db = await as('rider');
    await assertFails(
      db.collection('chats').doc('nope').collection('messages').doc('m1')
        .set({ senderId: 'rider', text: 'x' }),
    );
  });
});

describe('chats — participant tampering', () => {
  test('ensureThread re-writing the identical participant pair still works', async () => {
    // The regression risk of pinning `participants`: ChatRepository.ensureThread
    // merges `{participants: [me, partnerId]..sort()}` on every open, including
    // on threads that already exist. Identical value, so affectedKeys() stays
    // empty and the guard must not bite.
    const db = await as('rider');
    await assertSucceeds(
      db.collection('chats').doc('c1').set(
        { participants: ['rider', 'trainer'], lastMessage: 'Hi again' },
        { merge: true },
      ),
    );
  });

  test('DENY a participant removing the other from the thread', async () => {
    const db = await as('rider');
    await assertFails(db.collection('chats').doc('c1').update({ participants: ['rider'] }));
  });

  test('DENY a participant adding an outsider to the thread', async () => {
    const db = await as('rider');
    await assertFails(
      db.collection('chats').doc('c1').update({ participants: ['rider', 'trainer', 'rider2'] }),
    );
  });
});
