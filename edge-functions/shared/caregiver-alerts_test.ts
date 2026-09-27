import { assertEquals } from "std/assert/mod.ts";
import {
  careTeamRecipientIds,
  caregiverCheckedOnCopy,
  escalationCollapseId,
  escalationResolvedCopy,
  requestsResolvedByCheckIn,
  viewerMissedAlertCopy,
} from "./caregiver-alerts-copy.ts";
import { pickBilledFamily } from "./subscription-policy.ts";

Deno.test("the co-caregiver page says who, since when, and that the owner knows", () => {
  const copy = viewerMissedAlertCopy({ receiverName: "Mom", sinceLocal: "9:00 AM", ownerName: "Sarah" });
  assertEquals(copy.title, "Mom hasn't checked in");
  assertEquals(copy.body.startsWith("No answer since 9:00 AM. Sarah was alerted too."), true);
});

Deno.test("the page says when someone is already on it", () => {
  const copy = viewerMissedAlertCopy({ receiverName: "Mom", sinceLocal: "9:00 AM", ownerName: "Sarah", claimedByName: "Tom" });
  assertEquals(copy.body.startsWith("No answer since 9:00 AM. Tom is on it."), true);
});

Deno.test("the page still reads without a time or an owner name", () => {
  const copy = viewerMissedAlertCopy({ receiverName: "Dad" });
  assertEquals(copy.body.startsWith("No answer to today's check-in."), true);
  assertEquals(copy.body.includes("alerted too"), false);
});

Deno.test("all-clear copy for a check-in and for a stand-down", () => {
  assertEquals(
    escalationResolvedCopy({ receiverName: "Mom", how: "checked_in", atLocal: "10:45 AM" }),
    { title: "Mom checked in ✓", body: "Mom checked in at 10:45 AM. The missed check-in alert is over." },
  );
  assertEquals(
    escalationResolvedCopy({ receiverName: "Mom", how: "stood_down", byName: "Sarah" }).body,
    "Sarah reached Mom and stopped the alerts.",
  );
  assertEquals(
    escalationResolvedCopy({ receiverName: "Mom", how: "stood_down" }).body,
    "A caregiver reached Mom and stopped the alerts.",
  );
});

Deno.test("the alarm and its all-clear share a collapse id", () => {
  assertEquals(escalationCollapseId("abc"), "escalation-abc");
});

const req = (id: string, status: string, step: number, created: string, stoodDown: string | null = null) => ({
  id, status, escalation_step: step, created_at: created, stood_down_at: stoodDown,
});

Deno.test("only pending requests that reached the co-caregivers count", () => {
  const rows = [
    req("a", "pending", 2, "2026-09-27T09:00:00Z"), // owner only so far
    req("b", "pending", 3, "2026-09-27T09:00:00Z"), // viewers paged
  ];
  assertEquals(requestsResolvedByCheckIn(rows, null, false), ["b"]);
});

Deno.test("a missed request counts once, only on a fresh check-in after it", () => {
  const missed = req("m", "missed", 3, "2026-09-27T09:00:00Z");
  // Duplicate/follow-up path: never.
  assertEquals(requestsResolvedByCheckIn([missed], null, false), []);
  // First check-in since the miss.
  assertEquals(requestsResolvedByCheckIn([missed], "2026-09-26T08:00:00Z", true, "2026-09-27T11:00:00Z"), ["m"]);
  // A check-in already answered it (and was announced then).
  assertEquals(requestsResolvedByCheckIn([missed], "2026-09-27T10:00:00Z", true, "2026-09-27T11:00:00Z"), []);
  // A replayed tap from before the request doesn't answer it.
  assertEquals(requestsResolvedByCheckIn([missed], null, true, "2026-09-27T08:55:00Z"), []);
});

Deno.test("a stood-down miss was already announced", () => {
  const missed = req("m", "missed", 3, "2026-09-27T09:00:00Z", "2026-09-27T09:40:00Z");
  assertEquals(requestsResolvedByCheckIn([missed], null, true, "2026-09-27T11:00:00Z"), []);
});

Deno.test("App Store notifications go to the payer's family, not the oldest claimant", () => {
  const attacker = { id: "b", billing_user_id: "viewer", billing_verified_at: null };
  const payer = { id: "a", billing_user_id: "payer", billing_verified_at: "2026-09-01T00:00:00Z" };
  // Oldest first, as the query orders them.
  assertEquals(pickBilledFamily([attacker, payer], "payer")?.id, "a");
  // Receipt owner unknown: a verified billing wins over an unverified claim.
  assertEquals(pickBilledFamily([attacker, payer], null)?.id, "a");
  // Nothing verified: oldest, as before.
  assertEquals(pickBilledFamily([attacker], null)?.id, "b");
  assertEquals(pickBilledFamily([], "payer"), null);
});

Deno.test("an owner's stand-down reaches only the co-caregivers who were paged", () => {
  assertEquals(
    careTeamRecipientIds({ ownerId: "owner", viewerIds: ["tom", "ann"], pagedIds: ["tom"], actorId: "owner", wholeTeam: false }),
    ["tom"],
  );
});

Deno.test("a co-caregiver's action reaches the owner and every other active co-caregiver, not themselves", () => {
  assertEquals(
    careTeamRecipientIds({ ownerId: "owner", viewerIds: ["tom", "ann"], pagedIds: [], actorId: "tom", wholeTeam: true }),
    ["owner", "ann"],
  );
  // A paged-but-since-removed co-caregiver (not in viewerIds) hears nothing.
  assertEquals(
    careTeamRecipientIds({ ownerId: "owner", viewerIds: ["tom"], pagedIds: ["gone"], actorId: "tom", wholeTeam: true }),
    ["owner"],
  );
  // Ids compare case-insensitively (auth ids vs stored ids).
  assertEquals(
    careTeamRecipientIds({ ownerId: "OWNER", viewerIds: ["Tom"], pagedIds: [], actorId: "tom", wholeTeam: true }),
    ["OWNER"],
  );
});

Deno.test("check-on notice says who asked, and when nothing was delivered", () => {
  assertEquals(
    caregiverCheckedOnCopy({ actorName: "Tom", receiverName: "Mom", delivered: true }),
    { title: "Tom checked on Mom", body: "Tom sent Mom a check-in. Open Daily OK to see when they answer." },
  );
  assertEquals(
    caregiverCheckedOnCopy({ receiverName: "Mom", delivered: false }).body,
    "A caregiver sent Mom a check-in, but their phone couldn't be notified. You may want to call.",
  );
});
