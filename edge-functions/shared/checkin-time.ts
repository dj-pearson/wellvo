/**
 * Time arithmetic for check-ins: which local day a check-in belongs to, when it
 * actually happened, and how to say so to a human.
 *
 * Extracted from process-checkin-response so it can be unit-tested. That
 * handler imports shared/supabase.ts, which builds a Supabase client from env
 * at module load, so importing it from a test would need a live configuration
 * to test arithmetic that needs none.
 */

const ymdFormatter = (tz: string) =>
  new Intl.DateTimeFormat("en-CA", {
    timeZone: tz,
    year: "numeric", month: "2-digit", day: "2-digit",
  });

const hmsFormatter = (tz: string) =>
  new Intl.DateTimeFormat("en-CA", {
    timeZone: tz,
    hour: "2-digit", minute: "2-digit", second: "2-digit", hourCycle: "h23",
  });

/** The UTC offset, in ms, in effect in `tz` at the instant `at`. */
function tzOffsetMs(tz: string, at: Date): number {
  const ymd = ymdFormatter(tz).format(at);
  const hms = hmsFormatter(tz).format(at);
  return at.getTime() - Date.parse(`${ymd}T${hms}Z`);
}

/**
 * The UTC instant of local midnight opening the local calendar date `ymd`.
 *
 * Resolved in two passes, and that is the whole point. A single pass using the
 * offset in effect at some other hour of the day is wrong on both DST
 * transition days: on the US spring-forward Sunday the offset at midday is
 * UTC-5 but local midnight opened at UTC-6, so a one-pass computation puts the
 * day boundary an hour early — the window then starts at 11pm the previous
 * local day and ends at 11pm this one. A check-in made at 23:30 local on that
 * Sunday falls outside its own day, so the server's dedup and the app's
 * `Calendar.current.startOfDay` disagree, which is the permanent-Pending
 * failure this function exists to prevent. Re-resolving the offset at the
 * candidate instant fixes both directions.
 */
function localMidnightUTC(tz: string, ymd: string, near: Date): number {
  const naive = Date.parse(`${ymd}T00:00:00Z`);
  const firstPass = naive + tzOffsetMs(tz, near);
  return naive + tzOffsetMs(tz, new Date(firstPass));
}

/**
 * Returns UTC ISO timestamps for the start and end of the local calendar day
 * containing `at`, in the given IANA timezone.
 *
 * The apps compute `todayCheckInStatus` using the device's local calendar day
 * (`Calendar.current.startOfDay`), so the server-side dedup must use the same
 * local day — otherwise a late-evening check-in (e.g. 23:51 local = 03:51
 * next-day UTC) gets treated as "today" by the server but "yesterday" by the
 * dashboard, producing a permanent Pending.
 *
 * `at` defaults to now. It is passed explicitly for a check-in replayed from an
 * app's offline queue, which belongs to the day it was made rather than the day
 * it arrived (US-IOS147).
 */
export function localDayBoundsUTC(tz: string, at: Date = new Date()): { startUTC: string; endUTC: string } {
  const startMs = localMidnightUTC(tz, ymdFormatter(tz).format(at), at);
  // The next local date, resolved from an instant safely inside it rather than
  // by adding 86,400,000ms — a local day is 23 or 25 hours long twice a year.
  const wellIntoNextDay = new Date(startMs + 36 * 3_600_000);
  const endMs = localMidnightUTC(tz, ymdFormatter(tz).format(wellIntoNextDay), wellIntoNextDay);
  return {
    startUTC: new Date(startMs).toISOString(),
    endUTC: new Date(endMs).toISOString(),
  };
}

/**
 * How far in the past a client-supplied `occurred_at` may reach (US-IOS147).
 * Long enough to cover a genuine offline stretch — a hospital stay, a cabin
 * weekend, a phone left on a charger in a dead-signal room — and short enough
 * that a badly-wrong device clock cannot rewrite history.
 */
export const OCCURRED_AT_MAX_AGE_MS = 7 * 86_400_000;

/**
 * How far ahead of server time an `occurred_at` may sit before it is ignored.
 * Consumer device clocks drift; a couple of minutes is not evidence of anything.
 */
export const OCCURRED_AT_MAX_SKEW_MS = 5 * 60_000;

/**
 * Resolve the instant a check-in actually happened (US-IOS147).
 *
 * The offline queue on both apps replays check-ins that were made minutes — or
 * days — earlier. Without a client timestamp the row lands at `now()`, so a
 * check-in tapped on Monday and synced on Thursday is recorded as a Thursday
 * check-in nobody made, and the owner's dashboard reads "checked in today" for
 * someone who has not touched their phone in three days. That is the one
 * failure worse than a false escalation.
 *
 * Deliberately never rejects the request. `occurred_at` is an optional field
 * that shipped clients do not send at all, and a malformed or out-of-range
 * value from a future client must degrade to today's behaviour rather than
 * 400ing a check-in — refusing a check-in is itself an escalation.
 */
export function resolveOccurredAt(raw: unknown, now: Date = new Date()): Date {
  if (typeof raw !== "string" || raw.length === 0) return now;
  const parsed = Date.parse(raw);
  if (Number.isNaN(parsed)) return now;
  const age = now.getTime() - parsed;
  // Ahead of the server by more than the skew allowance: not trustworthy.
  if (age < -OCCURRED_AT_MAX_SKEW_MS) return now;
  // Within the skew allowance but still in the future: clamp rather than store
  // a check-in that has not happened yet.
  if (age < 0) return now;
  if (age > OCCURRED_AT_MAX_AGE_MS) return now;
  return new Date(parsed);
}

/**
 * Render when a check-in happened, in the receiver's timezone.
 *
 * A backfilled check-in (US-IOS147) must never be described with a bare time:
 * "checked in at 9:03 AM" on a notification the owner receives on Thursday
 * reads as Thursday. Backfills get the weekday and date, so the owner sees a
 * late delivery for what it is rather than as reassurance about today.
 */
export function formatOccurredAt(tz: string, isoTimestamp: string, withDate: boolean): string {
  return new Intl.DateTimeFormat("en-US", {
    timeZone: tz,
    ...(withDate ? { weekday: "short" as const, month: "short" as const, day: "numeric" as const } : {}),
    hour: "numeric",
    minute: "2-digit",
  }).format(new Date(isoTimestamp));
}
