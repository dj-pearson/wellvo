import { assertEquals } from "std/assert/mod.ts";
import {
  formatOccurredAt,
  localDayBoundsUTC,
  OCCURRED_AT_MAX_AGE_MS,
  OCCURRED_AT_MAX_SKEW_MS,
  resolveOccurredAt,
} from "./checkin-time.ts";

// US-IOS147. The offline queue on both apps replays check-ins made minutes or
// days earlier. Recorded at now(), a Monday tap synced on Thursday becomes a
// Thursday check-in nobody made — and the owner's dashboard says "checked in
// today" for someone who has not touched their phone since Monday.

const now = new Date("2026-03-12T15:00:00Z");

Deno.test("no occurred_at falls back to now (shipped clients)", () => {
  assertEquals(resolveOccurredAt(undefined, now).toISOString(), now.toISOString());
});

Deno.test("empty or non-string occurred_at falls back to now", () => {
  assertEquals(resolveOccurredAt("", now).toISOString(), now.toISOString());
  assertEquals(resolveOccurredAt(42, now).toISOString(), now.toISOString());
  assertEquals(resolveOccurredAt(null, now).toISOString(), now.toISOString());
});

Deno.test("unparseable occurred_at falls back to now rather than 400ing", () => {
  // Refusing a check-in is itself an escalation, so a malformed value from a
  // future client must degrade, never reject.
  assertEquals(resolveOccurredAt("last tuesday", now).toISOString(), now.toISOString());
});

Deno.test("a valid recent occurred_at is honoured", () => {
  const made = "2026-03-09T14:30:00.000Z";
  assertEquals(resolveOccurredAt(made, now).toISOString(), made);
});

Deno.test("occurred_at at the age limit is honoured", () => {
  const made = new Date(now.getTime() - OCCURRED_AT_MAX_AGE_MS);
  assertEquals(resolveOccurredAt(made.toISOString(), now).toISOString(), made.toISOString());
});

Deno.test("occurred_at older than the age limit falls back to now", () => {
  const made = new Date(now.getTime() - OCCURRED_AT_MAX_AGE_MS - 1000);
  assertEquals(resolveOccurredAt(made.toISOString(), now).toISOString(), now.toISOString());
});

Deno.test("occurred_at slightly in the future is clamped to now, not stored ahead", () => {
  const made = new Date(now.getTime() + OCCURRED_AT_MAX_SKEW_MS - 1000);
  assertEquals(resolveOccurredAt(made.toISOString(), now).toISOString(), now.toISOString());
});

Deno.test("occurred_at far in the future is ignored", () => {
  const made = new Date(now.getTime() + 86_400_000);
  assertEquals(resolveOccurredAt(made.toISOString(), now).toISOString(), now.toISOString());
});

// Local-day bounds must follow the instant, not the wall clock, or a replayed
// check-in dedups against the wrong day.

Deno.test("bounds are computed for the supplied instant, not for today", () => {
  const monday = new Date("2026-03-09T14:30:00Z");
  const { startUTC, endUTC } = localDayBoundsUTC("America/Chicago", monday);
  assertEquals(startUTC, "2026-03-09T05:00:00.000Z"); // CDT, UTC-5
  assertEquals(endUTC, "2026-03-10T05:00:00.000Z");
});

Deno.test("a late-evening local check-in belongs to its local day, not the UTC one", () => {
  // 23:51 America/Chicago on the 9th is 04:51 UTC on the 10th.
  const lateEvening = new Date("2026-03-10T04:51:00Z");
  const { startUTC } = localDayBoundsUTC("America/Chicago", lateEvening);
  assertEquals(startUTC, "2026-03-09T05:00:00.000Z");
});

Deno.test("bounds are correct in a timezone ahead of UTC", () => {
  const { startUTC, endUTC } = localDayBoundsUTC("Asia/Tokyo", new Date("2026-03-09T14:30:00Z"));
  // 23:30 Tokyo on the 9th: the local day opened at 15:00Z on the 8th.
  assertEquals(startUTC, "2026-03-08T15:00:00.000Z");
  assertEquals(endUTC, "2026-03-09T15:00:00.000Z");
});

// The DST cases below are the reason localMidnightUTC resolves the offset
// twice. A single pass took the offset from the instant passed in — midday —
// which on a transition day is not the offset that was in effect at local
// midnight, so the whole day window slid an hour and a genuine late-evening
// check-in fell outside its own day.

Deno.test("the spring-forward local day is 23 hours and starts at local midnight", () => {
  const dstDay = new Date("2026-03-08T18:00:00Z"); // US spring-forward Sunday
  const { startUTC, endUTC } = localDayBoundsUTC("America/Chicago", dstDay);
  assertEquals(startUTC, "2026-03-08T06:00:00.000Z"); // CST, UTC-6
  assertEquals(endUTC, "2026-03-09T05:00:00.000Z");   // CDT, UTC-5
  assertEquals((Date.parse(endUTC) - Date.parse(startUTC)) / 3_600_000, 23);
});

Deno.test("the fall-back local day is 25 hours and starts at local midnight", () => {
  const dstDay = new Date("2026-11-01T18:00:00Z"); // US fall-back Sunday
  const { startUTC, endUTC } = localDayBoundsUTC("America/Chicago", dstDay);
  assertEquals(startUTC, "2026-11-01T05:00:00.000Z"); // CDT, UTC-5
  assertEquals(endUTC, "2026-11-02T06:00:00.000Z");   // CST, UTC-6
  assertEquals((Date.parse(endUTC) - Date.parse(startUTC)) / 3_600_000, 25);
});

Deno.test("a 23:30 check-in on the spring-forward day falls inside its own day", () => {
  // The regression the two-pass resolution fixes: with a one-pass offset the
  // window ended at 23:00 local and this check-in landed outside it, so the
  // server saw no check-in for a day the app said was answered.
  const lateOnDstDay = new Date("2026-03-09T04:30:00Z"); // 23:30 local, Mar 8
  const { startUTC, endUTC } = localDayBoundsUTC("America/Chicago", new Date("2026-03-08T18:00:00Z"));
  assertEquals(lateOnDstDay.getTime() >= Date.parse(startUTC), true);
  assertEquals(lateOnDstDay.getTime() < Date.parse(endUTC), true);
});

Deno.test("a backfill and today resolve to different day bounds", () => {
  const thursday = new Date("2026-03-12T15:00:00Z");
  const monday = new Date("2026-03-09T15:00:00Z");
  const a = localDayBoundsUTC("America/Chicago", thursday).startUTC;
  const b = localDayBoundsUTC("America/Chicago", monday).startUTC;
  assertEquals(a === b, false);
});

// Copy. A bare time on a late-delivered push reads as today, which is the
// reassurance this change exists to remove.

/// ICU separates the time from AM/PM with a narrow no-break space (U+202F).
/// That is correct output and correct to send; it just is not what a literal in
/// a test file contains, so compare on a normalized form.
const spaces = (value: string) => value.replace(/[\u202f\u00a0]/g, " ");

Deno.test("a same-day check-in is described with a bare time", () => {
  assertEquals(spaces(formatOccurredAt("America/Chicago", "2026-03-12T15:03:00Z", false)), "10:03 AM");
});

Deno.test("a backfilled check-in is described with its weekday and date", () => {
  assertEquals(spaces(formatOccurredAt("America/Chicago", "2026-03-09T15:03:00Z", true)), "Mon, Mar 9, 10:03 AM");
});
