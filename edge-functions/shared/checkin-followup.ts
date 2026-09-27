/**
 * Follow-up signals on a day (or window) that already has a check-in.
 *
 * process-checkin-response dedups by the receiver's local day (and slot), and
 * it used to answer a duplicate with the existing row before looking at what
 * the new request said. So "I Need Help" at 3 PM after "I'm OK" at 9 AM
 * returned 200 with the 9 AM row: no alert, no push, the request closed as
 * answered. These helpers decide what a follow-up changes on the stored row.
 * Pure, so they are unit-testable without a database.
 */

export type ResponseType = "ok" | "need_help" | "call_me";

const RESPONSE_RANK: Record<string, number> = { ok: 0, call_me: 1, need_help: 2 };
const KID_RANK: Record<string, number> = { can_stay_longer: 1, picking_me_up: 2, sos: 3 };

/** need_help / call_me, or a kid SOS. Reaches caregivers at once, never queued. */
export function isUrgentSignal(responseType: string | null | undefined, kidType: string | null | undefined): boolean {
  return responseType === "need_help" || responseType === "call_me" || kidType === "sos";
}

/** A kid quick reply that is information, not an emergency. */
export function isKidInfoSignal(kidType: string | null | undefined): boolean {
  return kidType === "picking_me_up" || kidType === "can_stay_longer";
}

/**
 * The column changes a follow-up makes to an existing check-in row. Only ever
 * upward: a later plain "ok" never erases a help request, and "can I stay
 * longer?" never replaces an SOS. Empty when nothing changes.
 */
export function followUpUpgrade(
  existing: { response_type?: string | null; kid_response_type?: string | null },
  incomingResponse: string | null | undefined,
  incomingKid: string | null | undefined,
): { response_type?: string; kid_response_type?: string } {
  const changes: { response_type?: string; kid_response_type?: string } = {};
  const currentRank = RESPONSE_RANK[existing.response_type ?? "ok"] ?? 0;
  const incomingRank = incomingResponse != null ? (RESPONSE_RANK[incomingResponse] ?? -1) : -1;
  if (incomingResponse != null && incomingRank > currentRank) {
    changes.response_type = incomingResponse;
  }
  const currentKid = existing.kid_response_type ? (KID_RANK[existing.kid_response_type] ?? 0) : 0;
  const incomingKidRank = incomingKid ? (KID_RANK[incomingKid] ?? 0) : 0;
  if (incomingKid && incomingKidRank > currentKid) {
    changes.kid_response_type = incomingKid;
  }
  return changes;
}

/**
 * How long a repeat of the same signal on the same row counts as a retry of
 * the one already delivered (NetworkRetry re-sends after a client timeout the
 * server may already have answered). A second "I need help" after this is a
 * new request and alerts again.
 */
export const FOLLOW_UP_REPEAT_WINDOW_MS = 2 * 60 * 1000;

/** Whether an alert already raised for this row and type covers this request. */
export function isRepeatOfRecentAlert(
  recentAlertCreatedAt: string | null | undefined,
  now: Date = new Date(),
  windowMs: number = FOLLOW_UP_REPEAT_WINDOW_MS,
): boolean {
  if (!recentAlertCreatedAt) return false;
  const created = Date.parse(recentAlertCreatedAt);
  if (Number.isNaN(created)) return false;
  return now.getTime() - created < windowMs;
}

/**
 * Whether undo-checkin may reverse this row. A help request, a call-me or an
 * SOS has already paged the family; deleting the row and its alert would
 * erase it from their dashboard and history while the push stands.
 */
export function isUndoableRow(row: { response_type?: string | null; kid_response_type?: string | null }): boolean {
  return !isUrgentSignal(row.response_type ?? "ok", row.kid_response_type ?? null);
}
