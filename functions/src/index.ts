/**
 * FLOW — Cloud Functions.
 *
 * The parts of the application that cannot live in the client:
 *
 *   onNewNotification          (push.ts)          notification document → FCM push
 *   sendSessionReminders       (reminders.ts)     nightly "your session is tomorrow"
 *   sendCancelWindowReminders  (cancel_window.ts) nightly "free cancellation ends tomorrow"
 *
 * They compose: the reminder jobs write notification documents, which the
 * push trigger then delivers. None of them knows about the others.
 *
 * Deploy:  npm --prefix functions run deploy
 * Logs:    npm --prefix functions run logs
 */

import { setGlobalOptions } from "firebase-functions/v2";
import { initializeApp } from "firebase-admin/app";

initializeApp();

/**
 * A cap, not a target. These functions do trivial work per invocation and a
 * marketplace this size will never legitimately need hundreds of concurrent
 * instances — but a bad loop writing notifications in a tight cycle could,
 * and the bill for that arrives before anyone notices. Ten is generous.
 */
setGlobalOptions({ maxInstances: 10 });

/**
 * NOTE ON REGION — deliberately unset, so these deploy to `us-central1`.
 *
 * A v2 Firestore trigger must sit in a region compatible with the database's
 * own location. If `firebase deploy` rejects this with a location mismatch,
 * the fix is to add the database's region here (and only here):
 *
 *   setGlobalOptions({ maxInstances: 10, region: "europe-west1" });
 *
 * Find it under Firestore → ⚙ → Location in the console. Guessing wrong
 * costs a failed deploy, which is why this is documented rather than assumed.
 */

// Imported *after* initializeApp so no handler module can touch the Admin SDK
// before it is configured.
export { onNewNotification } from "./push";
export { sendSessionReminders } from "./reminders";
export { sendCancelWindowReminders } from "./cancel_window";
