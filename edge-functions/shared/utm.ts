/**
 * UTM tagging for syndicated links. (US-BLOG-053)
 *
 * Default convention:
 *   utm_source   = platform (x, linkedin, facebook, pinterest, ...)
 *   utm_medium   = "social" (override-able for newsletter/community variants)
 *   utm_campaign = post_slug (the canonical slug — never the title)
 *
 * Everything lowercased so GA4 doesn't split "Twitter" and "twitter" into
 * separate sources. Existing query / fragment on the URL is preserved; if a
 * UTM param of the same name is already present, ours wins (last-write-wins
 * inside URLSearchParams).
 *
 * Pure helper — no DB access, no env reads. Used by the syndicator for every
 * link it produces, and exposed as an `addUtm` shortcut for ad-hoc tagging.
 */

export interface UtmParams {
  /** Platform name. Lowercased automatically. */
  source: string;
  /** "social" by default. Override for "email" / "community" / "newsletter" etc. */
  medium?: string;
  /** Canonical post slug. Lowercased automatically. */
  campaign: string;
  /** Optional content variant id (e.g., "hook_a", "thread_v2"). Lowercased. */
  content?: string;
  /** Optional keyword. Lowercased. */
  term?: string;
}

const DEFAULT_MEDIUM = "social";

/**
 * Append UTM params to a URL, returning the tagged URL string.
 * Preserves existing query string and hash. Existing utm_* params are
 * overwritten by the values supplied here.
 */
export function addUtm(url: string, params: UtmParams): string {
  const u = parseUrlSafely(url);
  if (!u) return url;

  const set = (k: string, v: string | undefined) => {
    if (v === undefined || v === null) return;
    const trimmed = String(v).trim().toLowerCase();
    if (!trimmed) return;
    u.searchParams.set(k, trimmed);
  };

  set("utm_source", params.source);
  set("utm_medium", params.medium ?? DEFAULT_MEDIUM);
  set("utm_campaign", params.campaign);
  set("utm_content", params.content);
  set("utm_term", params.term);

  return u.toString();
}

/**
 * Convenience: build a tagged URL for a Daily OK blog post by slug.
 * SITE_ORIGIN env var (or https://dailyok.net) is used as the base.
 */
export function utmBlogUrl(slug: string, platform: string, opts: { medium?: string; content?: string } = {}): string {
  const origin = (typeof Deno !== "undefined" && Deno.env?.get?.("SITE_ORIGIN")) || "https://dailyok.net";
  const baseUrl = `${origin.replace(/\/$/, "")}/blog/${encodeURIComponent(slug)}`;
  return addUtm(baseUrl, {
    source: platform,
    medium: opts.medium,
    campaign: slug,
    content: opts.content,
  });
}

/**
 * Bulk-tag every URL referenced in an HTML/Markdown blob. Touches `href` /
 * raw URLs that point at the SITE_ORIGIN host; leaves third-party links alone.
 *
 * Currently used to tag the blog post body when it's pasted into a syndication
 * channel — internal links inside the body should also be measurable.
 */
export function rewriteInternalLinks(html: string, params: UtmParams): string {
  if (!html) return html;
  const origin = (typeof Deno !== "undefined" && Deno.env?.get?.("SITE_ORIGIN")) || "https://dailyok.net";
  const host = parseUrlSafely(origin)?.hostname.toLowerCase();
  if (!host) return html;

  return html.replace(/\bhref\s*=\s*"([^"]+)"/gi, (match, href: string) => {
    const target = parseUrlSafely(href, origin);
    if (!target) return match;
    const matchesHost = target.hostname.toLowerCase() === host;
    const isRelative = href.startsWith("/");
    if (!matchesHost && !isRelative) return match;
    const absolute = isRelative ? `${origin.replace(/\/$/, "")}${href}` : href;
    return `href="${addUtm(absolute, params)}"`;
  });
}

// =============================================================================
// Helpers
// =============================================================================

function parseUrlSafely(input: string, base?: string): URL | null {
  try {
    return base ? new URL(input, base) : new URL(input);
  } catch {
    return null;
  }
}
