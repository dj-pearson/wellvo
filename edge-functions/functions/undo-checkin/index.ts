import { supabaseAdmin } from "../../shared/supabase.ts";
import type { AuthResult } from "../../shared/auth.ts";
import { isValidUUID } from "../../shared/validation.ts";
import { UNDO_GRACE_SECONDS } from "../../shared/config.ts";
import { isUndoableRow } from "../../shared/checkin-followup.ts";

// How long a request reopened by Undo waits before escalation resumes: long
// enough to check in again properly, short enough that a real miss still
// reaches the owner promptly.
const UNDO_ESCALATION_RESUME_MS = 15 * 60 * 1000;

interface UndoCheckinRequest {
  family_id?: string;
  receiver_id?: string;
  checkin_id?: string;
}

/**
 * Undo an accidental check-in within a short grace window (US-IOS048).
 *
 * Reverses the most recent check-in for the receiver+family (or a specific
 * `checkin_id`) provided it was created within `UNDO_GRACE_SECONDS`:
 *   1. deletes any alert rows that referenced it (urgent / kid responses),
 *   2. re-opens the check-in requests it just closed so escalation can resume,
 *   3. deletes the check-in row itself.
 *
 * The grace window is deliberately short so an undo can't silently erase a
 * check-in the owner may already have acted on. Idempotent-ish: a second undo
 * just finds nothing recent and returns a clear error.
 */
export async function handleUndoCheckin(req: Request, auth: AuthResult): Promise<Response> {
  const body: UndoCheckinRequest = await req.json();

  let receiverId = body.receiver_id;
  let familyId = body.family_id;
  const checkinId = body.checkin_id;

  if (receiverId && !isValidUUID(receiverId)) {
    return json({ error: "Invalid receiver_id format" }, 400);
  }
  if (familyId && !isValidUUID(familyId)) {
    return json({ error: "Invalid family_id format" }, 400);
  }
  if (checkinId && !isValidUUID(checkinId)) {
    return json({ error: "Invalid checkin_id format" }, 400);
  }

  // Default the receiver to the authenticated user (the common case: a receiver
  // undoing their own tap). Service-role callers must pass receiver_id.
  if (!receiverId && auth.userId) receiverId = auth.userId;
  receiverId = receiverId?.toLowerCase();
  familyId = familyId?.toLowerCase();

  if (!receiverId || !familyId) {
    return json({ error: "receiver_id and family_id are required" }, 400);
  }

  // AUTHORIZATION: a non-service caller may only undo their own check-in.
  if (!auth.isServiceRole) {
    if (!auth.userId || auth.userId.toLowerCase() !== receiverId) {
      return json({ error: "You can only undo your own check-in" }, 403);
    }
  }

  // Find the target check-in: the explicit id, else the most recent for this
  // receiver+family.
  let query = supabaseAdmin
    .from("checkins")
    .select("id, checked_in_at, response_type, kid_response_type")
    .eq("receiver_id", receiverId)
    .eq("family_id", familyId);
  if (checkinId) {
    query = query.eq("id", checkinId);
  }
  const { data: checkIn } = await query
    .order("checked_in_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (!checkIn) {
    return json({ error: "No check-in found to undo" }, 404);
  }

  // Enforce the grace window.
  const checkedInAt = new Date(checkIn.checked_in_at as string).getTime();
  const ageSeconds = (Date.now() - checkedInAt) / 1000;
  if (ageSeconds > UNDO_GRACE_SECONDS) {
    return json(
      { error: "undo_window_expired", grace_seconds: UNDO_GRACE_SECONDS },
      409,
    );
  }

  // A help request, call-me or SOS has already paged the family. Undo would
  // delete the alert from their dashboard and history while the push stands,
  // and reopen the request as if nothing had been asked. Refused with a new
  // error code on the status undo already uses for "too late" (409), which
  // every shipped client treats as a failed undo.
  if (!isUndoableRow(checkIn as { response_type?: string | null; kid_response_type?: string | null })) {
    return json({ error: "urgent_not_undoable" }, 409);
  }

  // 1) Remove any alerts created from this check-in (urgent / kid responses).
  await supabaseAdmin
    .from("alerts")
    .delete()
    .eq("family_id", familyId)
    .eq("receiver_id", receiverId)
    .eq("data->>checkin_id", checkIn.id);

  // 2) Re-open requests this check-in closed so escalation can resume. We don't
  //    track the exact request id, so reopen any this receiver+family closed
  //    around the check-in time. A short lookback covers the case where the
  //    request's responded_at was stamped just before the check-in row.
  //    The escalation clock restarts from now: the reopened request's
  //    next_escalation_at is usually already in the past, so leaving it would
  //    fire the next reminder — or the owner alert — within a minute of the
  //    receiver pressing Undo.
  const reopenThreshold = new Date(checkedInAt - 60_000).toISOString();
  const resumeEscalationAt = new Date(Date.now() + UNDO_ESCALATION_RESUME_MS).toISOString();
  await supabaseAdmin
    .from("checkin_requests")
    .update({ status: "pending", responded_at: null, next_escalation_at: resumeEscalationAt })
    .eq("receiver_id", receiverId)
    .eq("family_id", familyId)
    .eq("status", "checked_in")
    .gte("responded_at", reopenThreshold);

  // 3) Delete the check-in row itself.
  const { error: deleteError } = await supabaseAdmin
    .from("checkins")
    .delete()
    .eq("id", checkIn.id);

  if (deleteError) {
    return json({ error: "Failed to undo check-in" }, 500);
  }

  return json({ success: true, undone_checkin_id: checkIn.id }, 200);
}

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
