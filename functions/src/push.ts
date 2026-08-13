/**
 * Push delivery — turns a `notifications` document into an FCM push.
 *
 * The app already writes a document for every event worth telling someone
 * about (§11.1) and already stores each device's FCM token on
 * `users/{uid}.fcmToken` — but nothing read either of them, so no push had
 * ever been delivered. Every token in that database was dead weight.
 *
 * This closes that loop and nothing else. In-app notifications, the bell
 * badge, the list and its tap-routing are all client-side and already work;
 * they are not touched here.
 */

import { onDocumentCreated } from "firebase-functions/v2/firestore";
import * as logger from "firebase-functions/logger";
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";

/** Mirrors `AppNotification` in lib/data/models/social.dart. */
interface NotificationDoc {
  /** The canonical recipient field written by the app. */
  targetUserId?: unknown;
  /**
   * Legacy alias. The blueprint (§11.1, §12) pins this function's contract as
   * reading `data.userId || data.targetUserId`, so it stays honoured even
   * though the current client writes only `targetUserId`.
   */
  userId?: unknown;
  title?: unknown;
  message?: unknown;
  type?: unknown;
  bookingId?: unknown;
  /** P2 deep-link payloads — see NotificationRepository.notify. */
  ticketId?: unknown;
  chatPartnerId?: unknown;
  chatPartnerName?: unknown;
  read?: unknown;
  /** Written by lib/dev/seed_content.dart — see the guard below. */
  seeded?: unknown;
  /** Written by this function once a push has gone out. */
  pushSentAt?: unknown;
}

/** Firestore is untyped at the edge; a malformed doc must not throw. */
function readString(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

/**
 * FCM rejects the whole message if any `data` value is not a string, so this
 * is the last gate before send.
 */
function stringData(entries: Record<string, string | undefined>) {
  const out: Record<string, string> = {};
  for (const [key, value] of Object.entries(entries)) {
    if (value !== undefined) out[key] = value;
  }
  return out;
}

/**
 * How long a failing event may keep being retried.
 *
 * `retry: true` below is what makes a transient FCM outage recoverable, but
 * on its own it is a well-known way to burn money: the platform will redeliver
 * a permanently-failing event for **seven days**. The error codes that are
 * permanent for a *token* are handled and swallowed below, but a permanent
 * error for the *project* — a disabled Messaging API, a broken service
 * account — would throw on every notification and retry all week.
 *
 * Ten minutes is long enough to ride out an outage and short enough that a
 * misconfiguration gives up on its own.
 */
const MAX_RETRY_AGE_MS = 10 * 60 * 1000;

export const onNewNotification = onDocumentCreated(
  {
    document: "notifications/{notificationId}",
    // Safe because of the `pushSentAt` guard below — that stamp is what turns
    // at-least-once delivery into at-most-one push.
    retry: true,
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return; // Deleted between write and invocation.

    const doc = snap.data() as NotificationDoc;
    const { notificationId } = event.params;

    const ageMs = Date.now() - Date.parse(event.time);
    if (Number.isFinite(ageMs) && ageMs > MAX_RETRY_AGE_MS) {
      logger.error("Giving up on notification after repeated failures", {
        notificationId,
        ageMs,
      });
      return;
    }

    // ── Guards ───────────────────────────────────────────────────────────
    // Each of these is a document that exists for a reason other than
    // "tell this person something just happened".

    // Seeded history is backdated by design — pushing "your session starts at
    // 10:00" for a lesson the seeder placed 30 hours in the past is worse than
    // sending nothing. Send a real chat message to test push end to end.
    if (doc.seeded === true) {
      logger.debug("Skipping seeded notification", { notificationId });
      return;
    }

    // Created already-read means it was written as history, not as news.
    if (doc.read === true) {
      logger.debug("Skipping notification created read", { notificationId });
      return;
    }

    // Cloud Functions are at-least-once: a retried invocation must not send a
    // second push. Best effort rather than a transaction — the window between
    // sending and stamping is small, and the failure mode is one duplicate
    // notification, which is not worth a read-modify-write on every event.
    if (doc.pushSentAt) {
      logger.debug("Push already sent", { notificationId });
      return;
    }

    const recipient = readString(doc.userId) ?? readString(doc.targetUserId);
    if (!recipient) {
      logger.warn("Notification has no recipient", { notificationId });
      return;
    }

    // ── Recipient's device token ─────────────────────────────────────────
    const db = getFirestore();
    const userSnap = await db.collection("users").doc(recipient).get();
    if (!userSnap.exists) {
      logger.warn("Recipient has no profile document", {
        notificationId,
        recipient,
      });
      await snap.ref.update({ pushSkipped: "no-profile" });
      return;
    }

    const token = readString(userSnap.get("fcmToken"));
    if (!token) {
      // Entirely normal: permission declined, a signed-out device, or a
      // profile created before the first token sync. The in-app notification
      // is already written and will be there when they next open the app.
      logger.info("Recipient has no FCM token", { notificationId, recipient });
      await snap.ref.update({ pushSkipped: "no-token" });
      return;
    }

    // ── Build the message ────────────────────────────────────────────────
    const title = readString(doc.title) ?? "FLOW";
    const body = readString(doc.message) ?? "";
    const type = readString(doc.type) ?? "system";
    const bookingId = readString(doc.bookingId);
    const ticketId = readString(doc.ticketId);
    const chatPartnerId = readString(doc.chatPartnerId);
    const chatPartnerName = readString(doc.chatPartnerName);

    try {
      await getMessaging().send({
        token,
        // A `notification` block, so Android renders it while the app is
        // killed. This is exactly why the Dart background handler is empty
        // (§11.3) — there is nothing for it to draw.
        notification: { title, body },
        // Read by PushController.handleTap in lib/services/push_service.dart.
        // `bookingId` is what lets a push land on the specific booking
        // (`/sessions?highlight=…`) instead of a bare list; `ticketId` and
        // `chatPartnerId`/`chatPartnerName` do the same for support threads
        // and conversations (P2).
        data: stringData({
          type,
          bookingId,
          ticketId,
          chatPartnerId,
          chatPartnerName,
          notificationId,
        }),
        android: {
          // These are time-critical on a beach: a booking request a trainer
          // sees an hour late is a booking they lost.
          priority: "high",
          notification: {
            // No channelId: the app declares no notification channel, and
            // naming one that does not exist on the device silently
            // suppresses the notification on Android 8+. FCM's own default
            // channel is created automatically and works.
            sound: "default",
          },
        },
        apns: {
          payload: { aps: { sound: "default" } },
        },
      });

      await snap.ref.update({ pushSentAt: FieldValue.serverTimestamp() });
      logger.info("Push sent", { notificationId, recipient, type });
    } catch (error) {
      const code =
        typeof error === "object" && error !== null && "code" in error
          ? String((error as { code: unknown }).code)
          : "unknown";

      // A token dies when the app is uninstalled, its data cleared, or the
      // token rotates while the device is offline. Nothing will ever make it
      // deliverable again, so it is removed rather than retried forever —
      // otherwise every future notification to this user pays for a failed
      // send, and `fcmToken` slowly fills with garbage across the database.
      if (
        code === "messaging/registration-token-not-registered" ||
        code === "messaging/invalid-registration-token" ||
        code === "messaging/invalid-argument"
      ) {
        logger.info("Dropping dead FCM token", { recipient, code });
        await userSnap.ref.update({ fcmToken: FieldValue.delete() });
        await snap.ref.update({ pushSkipped: "dead-token" });
        return;
      }

      // Anything else — quota, a transient FCM outage — may succeed on a
      // second attempt, so it is rethrown and the platform redelivers it
      // (`retry: true`), bounded by MAX_RETRY_AGE_MS.
      logger.error("Push failed", { notificationId, recipient, code, error });
      throw error;
    }
  }
);
