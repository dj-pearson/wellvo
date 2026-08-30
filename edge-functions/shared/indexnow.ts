/**
 * IndexNow submission from the edge (US-WEB009).
 *
 * The website pings IndexNow at build time (website/scripts/indexnow-ping.mjs),
 * which covers everything that exists when a deploy runs. Blog posts do not:
 * `generate-next-article` writes them straight to Supabase between deploys, so
 * without this a new post waits for the next unrelated build before Bing and
 * Yandex hear about it.
 *
 * Google ignores IndexNow — it gets the sitemap and Search Console. This is a
 * Bing/Yandex/Seznam path only.
 *
 * Non-fatal by construction: publishing a post must never fail because a
 * third-party indexing endpoint was slow or down. Every failure logs and
 * returns.
 */
import { logInfo, logError } from "./logger.ts";

const ENDPOINT = "https://api.indexnow.org/indexnow";

/** Bound on one submission. IndexNow's own cap is 10,000. */
const MAX_URLS = 100;

function siteOrigin(): string {
  return Deno.env.get("SITE_ORIGIN") || "https://dailyok.net";
}

/**
 * Submit URLs to IndexNow.
 *
 * Requires INDEXNOW_KEY — the basename of the key file served from the site
 * root (website/public/<key>.txt). Unset means "not configured": we log once
 * and skip rather than guessing, so a fork or a staging environment does not
 * submit another site's URLs under a key it does not own.
 */
export async function pingIndexNow(urls: string[]): Promise<void> {
  const key = Deno.env.get("INDEXNOW_KEY")?.trim();
  if (!key) {
    logInfo("indexnow: INDEXNOW_KEY not set; skipping submission", {
      url_count: urls.length,
    });
    return;
  }

  const origin = siteOrigin();
  const host = (() => {
    try {
      return new URL(origin).host;
    } catch {
      return null;
    }
  })();
  if (!host) {
    logError("indexnow: SITE_ORIGIN is not a valid URL; skipping", null, { origin });
    return;
  }

  // IndexNow rejects a submission containing any URL outside the declared host.
  const urlList = [...new Set(urls)]
    .filter((u) => u.startsWith(`${origin}/`))
    .slice(0, MAX_URLS);
  if (urlList.length === 0) {
    logInfo("indexnow: no submittable URLs after filtering to origin", { origin });
    return;
  }

  try {
    const res = await fetch(ENDPOINT, {
      method: "POST",
      headers: { "Content-Type": "application/json; charset=utf-8" },
      body: JSON.stringify({
        host,
        key,
        keyLocation: `${origin}/${key}.txt`,
        urlList,
      }),
    });
    // 200 and 202 both mean accepted; 4xx usually means the key file is not
    // reachable at keyLocation. Worth surfacing, never worth throwing.
    if (res.ok) {
      logInfo("indexnow: submitted", { count: urlList.length, status: res.status });
    } else {
      logError("indexnow: endpoint rejected submission", null, {
        status: res.status,
        statusText: res.statusText,
        count: urlList.length,
      });
    }
  } catch (err) {
    logError("indexnow: submission failed", err, { count: urlList.length });
  }
}

/** Convenience wrapper for the common "one post just went live" case. */
export async function pingIndexNowForSlug(slug: string): Promise<void> {
  await pingIndexNow([`${siteOrigin()}/blog/${slug}`, `${siteOrigin()}/blog`]);
}
