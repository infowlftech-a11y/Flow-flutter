/**
 * Free-cancellation deadline reminders — booking.com's "free cancellation
 * ends tomorrow" nudge, on FLOW's escrow policy (P1/P7).
 *
 * The policy: a held booking cancels free until 24 hours before its start;
 * inside the window it is charged in full. The one moment that changes a
 * rider's mind is the evening they can still act, so this runs nightly at
 * 18:00 Cairo — same clock, same DST-safe calendar arithmetic, and the same
 * write-a-notification-and-let-push-deliver design as reminders.ts.
 *
 * ## Why "the day after tomorrow"
 *
 * The deadline sits exactly 24 hours before the start, so it shares the
 * start's wall-clock time, one calendar day earlier. At 18:00 tonight, a
 * session on `today + 2` has its deadline *tomorrow* — still comfortably
 * ahead (6+ hours away at minimum), and "ends tomorrow at 10:00" is both
 * true and actionable. Targeting `tomorrow` instead would name deadlines
 * already gone for morning sessions; per-instant math would need the UTC
 * offset, which is the trap reminders.ts documents.
 */

import { onSchedule } from "firebase-functions/v2/scheduler";
import * as logger from "firebase-functions/logger";
import { FieldValue, getFirestore } from "firebase-admin/firestore";

const APP_TIME_ZONE = "Africa/Cairo";

/** Two writes per booking (notification + flag) — 200 stays well clear of
 * Firestore's 500-per-batch cap. */
const BOOKINGS_PER_BATCH = 200;

function ymdInAppZone(instant: Date): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: APP_TIME_ZONE,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(instant);
}

/** Calendar +1 on the date parts — never "+24 hours" on an instant. */
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

export const sendCancelWindowReminders = onSchedule(
  {
    schedule: "0 18 * * *",
    timeZone: APP_TIME_ZONE,
    retryCount: 3,
  },
  async () => {
    const today = ymdInAppZone(new Date());
    const tomorrow = nextDay(today);
    const target = tomorrow ? nextDay(tomorrow) : undefined;
    if (!target) {
      logger.error("Could not derive the target date", { today });
      return;
    }

    const db = getFirestore();
    // Equality on one field, everything else filtered below (§6.2) — a
    // single day's bookings is a tiny set.
    const snap = await db
      .collection("bookings")
      .where("date", "==", target)
      .get();

    const due = snap.docs.filter((doc) => {
      // Confirmed only: a pending request refunds in full however it dies,
      // so its holder has no deadline to warn about.
      if (doc.get("status") !== "confirmed") return false;
      // Held money is the whole subject — cash-era and walk-in bookings
      // lose nothing by cancelling late.
      if (doc.get("paymentStatus") !== "held") return false;
      if (doc.get("cancelReminderSent") === true) return false;
      const rider = readString(doc.get("kiterId"));
      if (!rider || rider === "manual_entry") return false;
      return true;
    });

    if (due.length === 0) {
      logger.info("No cancel-window reminders due", {
        date: target,
        scanned: snap.size,
      });
      return;
    }

    let sent = 0;
    for (let i = 0; i < due.length; i += BOOKINGS_PER_BATCH) {
      const chunk = due.slice(i, i + BOOKINGS_PER_BATCH);
      const batch = db.batch();

      for (const doc of chunk) {
        const rider = readString(doc.get("kiterId"));
        if (!rider) continue;

        const trainer = readString(doc.get("instructorName")) ?? "your trainer";
        const startTime = readString(doc.get("startTime"));
        const isSafari = doc.get("type") === "safari";

        // The deadline shares the start's wall-clock time, one day earlier —
        // so "tomorrow at 10:00" needs no time arithmetic at all.
        const when = startTime ? `tomorrow at ${startTime}` : "tomorrow";
        const message = isSafari
          ? `Free cancellation for your expedition with ${trainer} ends ` +
            `${when}. After that, cancelling is charged in full.`
          : `Free cancellation for your session with ${trainer} ends ` +
            `${when}. After that, cancelling is charged in full.`;

        // A notification document, not a direct send — onNewNotification
        // delivers the push, and the app's own list keeps the record either
        // way. Type 'reminder' rides the existing alarm tile and routes to
        // the booking, where the CANCEL button is.
        batch.set(db.collection("notifications").doc(), {
          targetUserId: rider,
          title: "Free cancellation ends soon",
          message,
          type: "reminder",
          bookingId: doc.id,
          read: false,
          createdAt: FieldValue.serverTimestamp(),
        });

        batch.update(doc.ref, { cancelReminderSent: true });
        sent++;
      }

      await batch.commit();
    }

    logger.info("Cancel-window reminders sent", {
      date: target,
      scanned: snap.size,
      sent,
    });
  }
);
