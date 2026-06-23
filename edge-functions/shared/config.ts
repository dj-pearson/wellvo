/**
 * Backward-compatibility version floors for installed mobile clients.
 *
 * Per CLAUDE.md, the backend must be able to tell an old build to update so the
 * API can evolve safely. These floors gate the edge endpoints: a client whose
 * reported app version is BELOW the floor for its platform receives a 426
 * (Upgrade Required) force-update payload instead of the normal response.
 *
 * IMPORTANT (CLAUDE.md): bump a floor ONLY when a force-update build has shipped
 * and you intend to cut off everything below it. The default "0.0.0" disables
 * the gate (blocks nothing) so this is dormant until deliberately raised. Floors
 * can be raised at runtime via the env vars without a code deploy.
 *
 * Note the chicken-and-egg: only builds that ship WITH force-update handling can
 * render the blocking screen, so the first such build is the effective baseline;
 * future floors should be >= it.
 */

export const MIN_SUPPORTED_IOS_APP_VERSION =
  Deno.env.get("MIN_SUPPORTED_IOS_APP_VERSION")?.trim() || "0.0.0";

export const MIN_SUPPORTED_ANDROID_APP_VERSION =
  Deno.env.get("MIN_SUPPORTED_ANDROID_APP_VERSION")?.trim() || "0.0.0";

export const IOS_APP_STORE_URL =
  Deno.env.get("IOS_APP_STORE_URL")?.trim() ||
  "https://apps.apple.com/us/app/dailyok-daily-check-in/id6760836697";

export const ANDROID_STORE_URL =
  Deno.env.get("ANDROID_STORE_URL")?.trim() ||
  "https://play.google.com/store/apps/details?id=net.dailyok.android";

/**
 * Compare two dotted numeric versions (e.g. "1.4.2"). Missing trailing segments
 * are treated as 0 ("1.4" == "1.4.0"). Returns <0 if a<b, 0 if equal, >0 if a>b.
 * Non-numeric segments are coerced to 0 so a malformed version never throws.
 */
export function compareVersions(a: string, b: string): number {
  const pa = a.split(".");
  const pb = b.split(".");
  const len = Math.max(pa.length, pb.length);
  for (let i = 0; i < len; i++) {
    const na = parseInt(pa[i] ?? "0", 10) || 0;
    const nb = parseInt(pb[i] ?? "0", 10) || 0;
    if (na !== nb) return na - nb;
  }
  return 0;
}

export type ClientPlatform = "ios" | "android";

/**
 * True when a known client version is strictly below its platform floor.
 * Fails OPEN: an unknown/empty version (older builds that don't send the
 * header) or a disabled floor ("0.0.0") never blocks.
 */
export function isBelowMinimum(platform: string | null | undefined, version: string | null | undefined): boolean {
  if (!version || version.trim() === "") return false;
  const floor = platform === "android"
    ? MIN_SUPPORTED_ANDROID_APP_VERSION
    : MIN_SUPPORTED_IOS_APP_VERSION;
  if (floor === "0.0.0") return false;
  return compareVersions(version.trim(), floor) < 0;
}

/** The JSON body returned with a 426 so clients can render a clear update CTA. */
export function forceUpdatePayload(platform: string | null | undefined): Record<string, unknown> {
  const isAndroid = platform === "android";
  return {
    error: "update_required",
    force_update: true,
    min_version: isAndroid ? MIN_SUPPORTED_ANDROID_APP_VERSION : MIN_SUPPORTED_IOS_APP_VERSION,
    update_url: isAndroid ? ANDROID_STORE_URL : IOS_APP_STORE_URL,
  };
}
