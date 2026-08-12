// firestore.rules — tickets (+ messages), appeals, reports, leave_reasons
//
// The trust & safety surface. Reports are write-only for the reporter by
// design: §3.12 requires that you cannot discover you have been reported.
// Appeals are written by suspended users, so the rules cannot require an
// active account.

import { test, describe, before, beforeEach, after } from 'node:test';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { as, anon, reset, seed, cleanup, testEnv } from './helpers.mjs';

before(async () => { await testEnv(); });
beforeEach(async () => {
  await reset();
  await seed(async (db) => {
    await db.collection('tickets').doc('t1').set({
      userId: 'rider', userName: 'Rider One', subject: 'Help', status: 'open',
    });
    await db.collection('tickets').doc('t1').collection('messages').doc('m1')
      .set({ senderId: 'rider', text: 'Something broke' });
    await db.collection('appeals').doc('ap1').set({
      userId: 'blocked', userName: 'Blocked Rider', reason: 'Please review',
      status: 'pending', messages: [],
    });
    await db.collection('reports').doc('rp1').set({
      reporterId: 'rider', reportedUserId: 'trainer', reason: 'Safety concerns',
      status: 'pending',
    });
    await db.collection('leave_reasons').doc('l1').set({
      userId: 'rider', reason: 'Not using it',
    });
  });
});
after(cleanup);

describe('tickets', () => {
  test('the owner reads their ticket', async () => {
    const db = await as('rider');
    await assertSucceeds(db.collection('tickets').doc('t1').get());
  });

  test('staff reads any ticket', async () => {
    const db = await as('support');
    await assertSucceeds(db.collection('tickets').doc('t1').get());
  });

  test('DENY another user reading it', async () => {
    const db = await as('rider2');
    await assertFails(db.collection('tickets').doc('t1').get());
  });

  test('a user opens a ticket for themselves', async () => {
    const db = await as('rider2');
    await assertSucceeds(
      db.collection('tickets').doc('t2').set({ userId: 'rider2', subject: 'Hi', status: 'open' }),
    );
  });

  test('DENY opening a ticket in someone elses name', async () => {
    const db = await as('rider2');
    await assertFails(
      db.collection('tickets').doc('t2').set({ userId: 'rider', subject: 'Hi' }),
    );
  });

  test('the owner updates their ticket', async () => {
    const db = await as('rider');
    await assertSucceeds(db.collection('tickets').doc('t1').update({ lastMessageAt: 'now' }));
  });

  test('staff closes a ticket', async () => {
    const db = await as('support');
    await assertSucceeds(db.collection('tickets').doc('t1').update({ status: 'closed' }));
  });

  test('DENY a stranger updating', async () => {
    const db = await as('rider2');
    await assertFails(db.collection('tickets').doc('t1').update({ status: 'closed' }));
  });

  test('staff deletes a ticket', async () => {
    const db = await as('admin');
    await assertSucceeds(db.collection('tickets').doc('t1').delete());
  });

  test('DENY the owner deleting their own ticket', async () => {
    const db = await as('rider');
    await assertFails(db.collection('tickets').doc('t1').delete());
  });

  test('the owner lists their tickets by userId', async () => {
    const db = await as('rider');
    await assertSucceeds(db.collection('tickets').where('userId', '==', 'rider').get());
  });

  test('DENY listing another users tickets', async () => {
    const db = await as('rider2');
    await assertFails(db.collection('tickets').where('userId', '==', 'rider').get());
  });

  // The staff queue — `watchAllTickets()`. An unfiltered list is authorised
  // because `isStaff()` is document-independent and true for every returned
  // doc; a rider's identical query is refused by the same rule, which is
  // what makes the console's read safe to open up.
  test('staff list every ticket, unfiltered', async () => {
    const db = await as('support');
    await assertSucceeds(db.collection('tickets').get());
  });

  test('DENY a rider listing every ticket', async () => {
    const db = await as('rider');
    await assertFails(db.collection('tickets').get());
  });

  test('staff answer as FLOW support (isAdmin: true)', async () => {
    const db = await as('support');
    await assertSucceeds(
      db.collection('tickets').doc('t1').collection('messages').doc('m9')
        .set({ senderId: 'support', text: 'On it', isAdmin: true }),
    );
  });

  test('staff close a ticket', async () => {
    const db = await as('admin');
    await assertSucceeds(
      db.collection('tickets').doc('t1').update({ status: 'closed' }),
    );
  });
});

describe('tickets/messages', () => {
  test('the ticket owner reads the thread', async () => {
    const db = await as('rider');
    await assertSucceeds(db.collection('tickets').doc('t1').collection('messages').get());
  });

  test('staff reads the thread', async () => {
    const db = await as('support');
    await assertSucceeds(db.collection('tickets').doc('t1').collection('messages').get());
  });

  test('DENY a stranger reading the thread', async () => {
    const db = await as('rider2');
    await assertFails(db.collection('tickets').doc('t1').collection('messages').get());
  });

  test('the owner replies', async () => {
    const db = await as('rider');
    await assertSucceeds(
      db.collection('tickets').doc('t1').collection('messages').doc('m2')
        .set({ senderId: 'rider', text: 'Any update?' }),
    );
  });

  test('staff replies', async () => {
    const db = await as('support');
    await assertSucceeds(
      db.collection('tickets').doc('t1').collection('messages').doc('m2')
        .set({ senderId: 'support', text: 'Looking into it' }),
    );
  });

  test('DENY a stranger replying', async () => {
    const db = await as('rider2');
    await assertFails(
      db.collection('tickets').doc('t1').collection('messages').doc('m2')
        .set({ senderId: 'rider2', text: 'me too' }),
    );
  });

  test('DENY editing a ticket message', async () => {
    const db = await as('rider');
    await assertFails(
      db.collection('tickets').doc('t1').collection('messages').doc('m1')
        .update({ text: 'rewritten' }),
    );
  });

  test('DENY deleting a ticket message, even as staff', async () => {
    const db = await as('admin');
    await assertFails(
      db.collection('tickets').doc('t1').collection('messages').doc('m1').delete(),
    );
  });
});

describe('appeals', () => {
  test('the blocked author reads their own appeal', async () => {
    const db = await as('blocked');
    await assertSucceeds(db.collection('appeals').doc('ap1').get());
  });

  test('staff reads any appeal', async () => {
    const db = await as('admin');
    await assertSucceeds(db.collection('appeals').doc('ap1').get());
  });

  test('DENY another user reading it', async () => {
    const db = await as('rider');
    await assertFails(db.collection('appeals').doc('ap1').get());
  });

  test('a blocked user files an appeal — the account is suspended, not gone', async () => {
    const db = await as('blocked');
    await assertSucceeds(
      db.collection('appeals').doc('ap2').set({ userId: 'blocked', reason: 'Second try', status: 'pending' }),
    );
  });

  test('DENY filing an appeal in someone elses name', async () => {
    const db = await as('rider');
    await assertFails(
      db.collection('appeals').doc('ap2').set({ userId: 'blocked', reason: 'x' }),
    );
  });

  test('the author appends a reply', async () => {
    const db = await as('blocked');
    await assertSucceeds(
      db.collection('appeals').doc('ap1').update({ messages: [{ from: 'user', text: 'hello' }] }),
    );
  });

  test('staff sets the appeal status', async () => {
    const db = await as('admin');
    await assertSucceeds(db.collection('appeals').doc('ap1').update({ status: 'rejected' }));
  });

  test('DENY a stranger updating an appeal', async () => {
    const db = await as('rider');
    await assertFails(db.collection('appeals').doc('ap1').update({ status: 'approved' }));
  });

  test('DENY the author deleting their appeal', async () => {
    const db = await as('blocked');
    await assertFails(db.collection('appeals').doc('ap1').delete());
  });

  test('staff deletes an appeal', async () => {
    const db = await as('admin');
    await assertSucceeds(db.collection('appeals').doc('ap1').delete());
  });

  test('the author queries their own appeal by userId (§6.2, limit 1)', async () => {
    const db = await as('blocked');
    await assertSucceeds(
      db.collection('appeals').where('userId', '==', 'blocked').limit(1).get(),
    );
  });
});

describe('reports — write-only for the reporter (§3.12)', () => {
  test('a rider files a report', async () => {
    const db = await as('rider');
    await assertSucceeds(
      db.collection('reports').doc('rp2').set({
        reporterId: 'rider', reportedUserId: 'trainer2', reason: 'Fake profile / Scam',
        status: 'pending',
      }),
    );
  });

  test('DENY filing a report under someone elses name', async () => {
    const db = await as('rider');
    await assertFails(
      db.collection('reports').doc('rp2').set({ reporterId: 'rider2', reportedUserId: 'trainer' }),
    );
  });

  test('DENY the reporter reading back their own report', async () => {
    const db = await as('rider');
    await assertFails(db.collection('reports').doc('rp1').get());
  });

  test('DENY the reported user discovering the report', async () => {
    const db = await as('trainer');
    await assertFails(db.collection('reports').doc('rp1').get());
  });

  test('staff reads reports', async () => {
    const db = await as('admin');
    await assertSucceeds(db.collection('reports').doc('rp1').get());
  });

  test('staff resolves a report', async () => {
    const db = await as('admin');
    await assertSucceeds(db.collection('reports').doc('rp1').update({ status: 'resolved' }));
  });

  test('DENY the reporter amending their report', async () => {
    const db = await as('rider');
    await assertFails(db.collection('reports').doc('rp1').update({ reason: 'Other' }));
  });

  test('DENY the reported user deleting the report', async () => {
    const db = await as('trainer');
    await assertFails(db.collection('reports').doc('rp1').delete());
  });
});

describe('leave_reasons', () => {
  test('a user records why they left', async () => {
    const db = await as('rider');
    await assertSucceeds(
      db.collection('leave_reasons').doc('l2').set({ userId: 'rider', reason: 'Moving on' }),
    );
  });

  test('DENY recording one in someone elses name', async () => {
    const db = await as('rider');
    await assertFails(
      db.collection('leave_reasons').doc('l2').set({ userId: 'rider2', reason: 'x' }),
    );
  });

  test('DENY the author reading it back', async () => {
    const db = await as('rider');
    await assertFails(db.collection('leave_reasons').doc('l1').get());
  });

  test('staff reads leave reasons', async () => {
    const db = await as('admin');
    await assertSucceeds(db.collection('leave_reasons').doc('l1').get());
  });

  // `watchLeaveReasons()` — the console's Feedback tab. Until it existed,
  // every answer to "why are you leaving?" was written into a collection
  // that was readable in principle and read by nobody in practice.
  test('staff list the whole collection', async () => {
    const db = await as('admin');
    await assertSucceeds(db.collection('leave_reasons').get());
  });

  test('DENY a rider listing them', async () => {
    const db = await as('rider');
    await assertFails(db.collection('leave_reasons').get());
  });

  test('a departing user records one with their name and email attached',
    async () => {
      // The console cannot look the author up afterwards — the profile is
      // deleted moments later — so the document has to carry who it was.
      const db = await as('rider');
      await assertSucceeds(
        db.collection('leave_reasons').doc('l3').set({
          userId: 'rider', userName: 'Rider One', userEmail: 'rider@test.dev',
          reason: 'Moving to another spot',
        }),
      );
    });

  test('DENY editing a leave reason, even as staff', async () => {
    const db = await as('admin');
    await assertFails(db.collection('leave_reasons').doc('l1').update({ reason: 'edited' }));
  });

  test('DENY deleting a leave reason, even as staff', async () => {
    const db = await as('admin');
    await assertFails(db.collection('leave_reasons').doc('l1').delete());
  });
});
