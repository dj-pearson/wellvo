/**
 * Copy and decisions for what co-caregivers are told about a missed check-in
 * and its all-clear. Pure (no database, no network) so it is unit-tested in
 * caregiver-alerts_test.ts; the senders are in caregiver-alerts.ts.
 */

/** Same key for the alarm and its all-clear, so iOS replaces one with the other. */
export function escalationCollapseId(requestId: string): string {
  return `escalation-${requestId}`;
}

/**
 * The last-step page to a co-caregiver. `sinceLocal` is when the check-in was
 * asked for, in the receiver's zone ("9:00 AM"); `ownerName` is who was
 * alerted before them. Either may be missing.
 */
export function viewerMissedAlertCopy(args: {
  receiverName: string;
  sinceLocal?: string | null;
  ownerName?: string | null;
  /** Someone already said "I'm on it" (claim_checkin_request, 00062). */
  claimedByName?: string | null;
}): { title: string; body: string } {
  const title = `${args.receiverName} hasn't checked in`;
  const since = args.sinceLocal ? `No answer since ${args.sinceLocal}.` : "No answer to today's check-in.";
  if (args.claimedByName) {
    return { title, body: `${since} ${args.claimedByName} is on it. Open Daily OK to see what's happening.` };
  }
  const owner = args.ownerName ? ` ${args.ownerName} was alerted too.` : "";
  return { title, body: `${since}${owner} Call them, or open Daily OK to see what's happening.` };
}

/** The all-clear. */
export function escalationResolvedCopy(args: {
  receiverName: string;
  how: "checked_in" | "stood_down";
  atLocal?: string | null;
  byName?: string | null;
}): { title: string; body: string } {
  const at = args.atLocal ? ` at ${args.atLocal}` : "";
  if (args.how === "checked_in") {
    return {
      title: `${args.receiverName} checked in ✓`,
      body: `${args.receiverName} checked in${at}. The missed check-in alert is over.`,
    };
  }
  const who = args.byName ?? "A caregiver";
  return {
    title: `${args.receiverName} was reached ✓`,
    body: `${who} reached ${args.receiverName} and stopped the alerts${at}.`,
  };
}

/**
 * Which requests a fresh check-in resolves for the co-caregivers who were
 * paged about them. A pending request that reached the viewer step (>= 3) is
 * being answered now. A missed request (the chain ran out) counts only when
 * it came after the receiver's previous check-in — otherwise it was already
 * answered and announced — and only if nobody stood it down (they were told
 * then).
 */
export function requestsResolvedByCheckIn(
  requests: { id: string; status: string; escalation_step: number | null; created_at: string; stood_down_at?: string | null }[],
  previousCheckInAt: string | null,
  allowMissed: boolean,
  answeredAt?: string | null,
): string[] {
  const prev = previousCheckInAt ? Date.parse(previousCheckInAt) : NaN;
  const answered = answeredAt ? Date.parse(answeredAt) : NaN;
  return requests
    .filter((r) => {
      if (r.status === "pending") return (r.escalation_step ?? 0) >= 3;
      if (r.status !== "missed" || !allowMissed || r.stood_down_at) return false;
      const created = Date.parse(r.created_at);
      // A replayed tap from before the request doesn't answer it.
      if (!Number.isNaN(answered) && created > answered) return false;
      return Number.isNaN(prev) || created > prev;
    })
    .map((r) => r.id);
}
