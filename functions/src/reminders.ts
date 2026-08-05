/**
 * Session reminders — the evening-before nudge.
 *
 * `NotificationKind.reminder` has always existed: the notifications screen
 * renders it with an alarm icon and routes a tap to the right booking, and
 * `Booking.reminderSent` has been read by the model since 3.0. Nothing ever
 * wrote either of them, so the whole path was dead. This is the writer.
 *
 * ## Why a nightly job at a fixed hour, and not "24 hours before the start"
 *
 * Per-booking instant math would need the booking's wall-clock time resolved
 * to a real instant, and bookings store a local `YYYY-MM-DD` plus an `HH:mm`
 * with no offset. Reconstructing that on a server running in UTC means
 * hard-coding Egypt's offset — which is +2, except when it is +3, because
 * Egypt reinstated DST in 2023. Getting that wrong sends reminders an hour
 * out twice a year, in opposite directions.
 *
 * Running once a day at 18:00 Africa/Cairo and reminding everyone about
 * *tomorrow* sidesteps it entirely: Cloud Scheduler owns the timezone
 * (including DST), and the only date arithmetic left is "add one calendar
 * day", which needs no offset at all. It also matches the wording the
 * blueprint specified for this notification — "Session tomorrow".
 */

import { onSchedule } from "firebase-functions/v2/scheduler";
import * as logger from "firebase-functions/logger";
import { FieldValue, getFirestore } from "firebase-admin/firestore";

/**
 * Every kite spot in the app is on the Egyptian Red Sea (§13), so the
 * marketplace has exactly one local timezone. If FLOW ever opens a second
 * country this becomes per-spot and this job has to be rethought.
 */
const APP_TIME_ZONE = "Africa/Cairo";

/**
 * Firestore allows 500 writes per batch. Each booking costs two — the
 * notification document and the `reminderSent` flag — so 200 bookings per
 * batch leaves comfortable headroom.
 */
const BOOKINGS_PER_BATCH = 200;

/** `YYYY-MM-DD` for an instant, as read on a clock in Egypt. */
function ymdInAppZone(instant: Date): string {
  // en-CA formats as YYYY-MM-DD, which is the format the app stores.
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: APP_TIME_ZONE,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(instant);
}

/**
 * The calendar day after [ymd].
 *
 * Pure calendar arithmetic on the date parts — never "+24 hours" on an
 * instant, which is wrong on the two days a year the clocks move.
 */
function nextDay(ymd: string): string | undefined {
  const parts = ymd.split("-").map((p) => Number.parseInt(p, 10));
  const [year, month, day] = parts;
  if (
    year === undefined ||
    month === undefined ||
    day === undefined ||
    !Number.isFinite(year) ||
    !Number.isFinite(month) ||
    !Number.isFinite(day)
  ) {
    return undefined;
  }
  // Date.UTC rolls month and year over for us.
  const next = new Date(Date.UTC(year, month - 1, day + 1));
  const y = next.getUTCFullYear().toString().padStart(4, "0");
  const m = (next.getUTCMonth() + 1).toString().padStart(2, "0");
  const d = next.getUTCDate().toString().padStart(2, "0");
  return `${y}-${m}-${d}`;
}

function readString(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

export const sendSessionReminders = onSchedule(
  {
    // 18:00 the evening before — late enough that the day's plans are settled,
    // early enough to still rearrange gear or a lift to the beach.
    schedule: "0 18 * * *",
    timeZone: APP_TIME_ZONE,
    retryCount: 3,
  },
  async () => {
    const today = ymdInAppZone(new Date());
    const tomorrow = nextDay(today);
    if (!tomorrow) {
      logger.error("Could not derive tomorrow's date", { today });
      return;
    }

    const db = getFirestore();
    // Equality on one field — no composite index required, which is the same
    // reason the app sorts client-side (§6.2). Everything else is filtered
    // below: a single day's bookings is a tiny set.
    const snap = await db
      .collection("bookings")
      .where("date", "==", tomorrow)
      .get();

    const due = snap.docs.filter((doc) => {
      if (doc.get("status") !== "confirmed") return false;
      // Already reminded — the flag is why this job is safe to re-run.
      if (doc.get("reminderSent") === true) return false;
      const rider = readString(doc.get("kiterId"));
      // Walk-ins have no account behind them and never notify (§11.1).
      if (!rider || rider === "manual_entry") return false;
      return true;
    });

    if (due.length === 0) {
      logger.info("No reminders due", { date: tomorrow, scanned: snap.size });
      return;
    }

    let sent = 0;
    for (let i = 0; i < due.length; i += BOOKINGS_PER_BATCH) {
      const chunk = due.slice(i, i + BOOKINGS_PER_BATCH);
      const batch = db.batch();

      for (const doc of chunk) {
        const rider = readString(doc.get("kiterId"));
        if (!rider) continue; // Re-checked: the filter above narrowed, TS did not.

        const trainer = readString(doc.get("instructorName")) ?? "your trainer";
        const startTime = readString(doc.get("startTime"));
        const isSafari = doc.get("type") === "safari";

        // Expeditions have no hour grid, so they have no start time to quote.
        const message = isSafari
          ? `Your expedition with ${trainer} departs tomorrow.`
          : startTime
            ? `Your session with ${trainer} starts at ${startTime}.`
            : `Your session with ${trainer} is tomorrow.`;

        // Written to `notifications`, not sent directly — onNewNotification
        // picks it up and delivers the push. That keeps every notification in
        // the app's own list whether or not the push ever lands.
        batch.set(db.collection("notifications").doc(), {
          targetUserId: rider,
          title: "Session tomorrow",
          message,
          type: "reminder",
          bookingId: doc.id,
          read: false,
          createdAt: FieldValue.serverTimestamp(),
        });

        // Same batch as the notification, so a partial failure can never
        // leave a booking marked as reminded without one being written.
        batch.update(doc.ref, { reminderSent: true });
        sent++;
      }

      await batch.commit();
    }

    logger.info("Session reminders sent", {
      date: tomorrow,
      scanned: snap.size,
      sent,
    });
  }
);
