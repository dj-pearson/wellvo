/**
 * Every value of the Postgres `checkin_source` ENUM (00001, 00012, 00037,
 * 00046). `checkins.source` is that ENUM, so an unknown value makes the INSERT
 * fail and the whole check-in answer 500.
 *
 * iOS exposes the Siri / Shortcuts intent's "Source" as a free-text parameter
 * in the Shortcuts editor. A shortcut built with anything else in that field
 * failed every check-in it sent, and the receiver was escalated daily with no
 * clue why. Unknown values are recorded as "app" instead: more tolerant, never
 * stricter, so every shipped client keeps working unchanged.
 */
export const CHECKIN_SOURCES = new Set([
  "app",
  "notification",
  "on_demand",
  "need_help",
  "call_me",
  "watch",
  "widget",
  "control",
  "siri",
]);

export function normalizeCheckinSource(raw: unknown): string {
  if (typeof raw !== "string") return "app";
  const value = raw.trim().toLowerCase();
  return CHECKIN_SOURCES.has(value) ? value : "app";
}
