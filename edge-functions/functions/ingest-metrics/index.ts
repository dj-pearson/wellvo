/**
 * /ingest-metrics — Make.com-invoked daily metrics ingest. (US-BLOG-061)
 *
 * Make.com scenarios pull last-day GA4 + Search Console rows for each blog
 * post URL and POST a batch here. The handler resolves slugs → blog_post_id
 * and upserts into blog_post_metrics keyed by (post_id, metric_date, source).
 *
 * Auth happens upstream in server.ts via X-Webhook-Secret →
 * INGEST_METRICS_WEBHOOK_SECRET. By the time we get here the request is
 * already trusted.
 *
 * Request body:
 *   {
 *     "rows": [
 *       {
 *         "post_slug": "what-to-do-when-mom-doesnt-answer-phone",
 *         "metric_date": "2026-05-06",
 *         "source": "search_console",
 *         "impressions": 1200, "clicks": 78, "avg_position": 6.2, "ctr": 0.065
 *       },
 *       {
 *         "post_id": "5e6b...",
 *         "metric_date": "2026-05-06",
 *         "source": "ga4",
 *         "sessions": 64, "engaged_sessions": 51, "conversions": 3,
 *         "avg_time_on_page_seconds": 142.5
 *       }
 *     ]
 *   }
 *
 * Either `post_slug` or `post_id` must identify the row. Unknown slugs are
 * skipped (counted as `unresolved`) — webhook never fails on a single bad row.
 *
 * Response (200):
 *   { upserted: 12, unresolved: 1, errors: [] }
 */

import { supabaseAdmin } from "../../shared/supabase.ts";
import { logError, logInfo } from "../../shared/logger.ts";
import type { AuthResult } from "../../shared/auth.ts";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

const VALID_SOURCES = new Set(["search_console", "ga4", "internal"]);

interface MetricRow {
  post_id?: string;
  post_slug?: string;
  metric_date: string;
  source: string;
  impressions?: number;
  clicks?: number;
  avg_position?: number;
  ctr?: number;
  sessions?: number;
  engaged_sessions?: number;
  conversions?: number;
  avg_time_on_page_seconds?: number;
  raw?: Record<string, unknown>;
}

interface RequestBody {
  rows?: MetricRow[];
}

export async function handleIngestMetrics(req: Request, _auth: AuthResult): Promise<Response> {
  let body: RequestBody;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON" }, 400);
  }

  const rows = Array.isArray(body.rows) ? body.rows : [];
  if (rows.length === 0) return json({ error: "rows array required" }, 400);
  if (rows.length > 5000) return json({ error: "Batch too large — split into batches of ≤5000" }, 413);

  // Resolve any slug-only rows to post_id in a single query.
  const slugs = Array.from(new Set(
    rows.filter((r) => !r.post_id && r.post_slug).map((r) => r.post_slug as string),
  ));
  const slugMap = new Map<string, string>();
  if (slugs.length > 0) {
    const { data, error } = await supabaseAdmin
      .from("blog_posts")
      .select("id, slug")
      .in("slug", slugs);
    if (error) {
      logError("ingest-metrics: slug lookup failed", error, {});
      return json({ error: error.message }, 500);
    }
    for (const r of data ?? []) {
      slugMap.set(r.slug as string, r.id as string);
    }
  }

  const upsertRows: Array<Record<string, unknown>> = [];
  const errors: Array<{ row: MetricRow; error: string }> = [];
  let unresolved = 0;

  for (const r of rows) {
    if (!r.metric_date || !r.source) {
      errors.push({ row: r, error: "metric_date and source required" });
      continue;
    }
    if (!VALID_SOURCES.has(r.source)) {
      errors.push({ row: r, error: `source must be one of ${[...VALID_SOURCES].join(", ")}` });
      continue;
    }
    if (!isIsoDate(r.metric_date)) {
      errors.push({ row: r, error: `metric_date must be YYYY-MM-DD` });
      continue;
    }

    let postId = r.post_id;
    if (!postId && r.post_slug) postId = slugMap.get(r.post_slug);
    if (!postId) {
      unresolved++;
      continue;
    }

    upsertRows.push({
      post_id: postId,
      metric_date: r.metric_date,
      source: r.source,
      impressions: int(r.impressions),
      clicks: int(r.clicks),
      avg_position: numOrNull(r.avg_position),
      ctr: numOrNull(r.ctr),
      sessions: int(r.sessions),
      engaged_sessions: int(r.engaged_sessions),
      conversions: int(r.conversions),
      avg_time_on_page_seconds: numOrNull(r.avg_time_on_page_seconds),
      raw: r.raw ?? null,
    });
  }

  let upserted = 0;
  if (upsertRows.length > 0) {
    const { error, count } = await supabaseAdmin
      .from("blog_post_metrics")
      .upsert(upsertRows, {
        onConflict: "post_id,metric_date,source",
        count: "exact",
      });
    if (error) {
      logError("ingest-metrics: upsert failed", error, { batch_size: upsertRows.length });
      return json({ error: error.message, upserted: 0, unresolved, errors }, 500);
    }
    upserted = count ?? upsertRows.length;
  }

  logInfo("ingest-metrics: batch complete", { upserted, unresolved, errors_count: errors.length });
  return json({ upserted, unresolved, errors });
}

// =============================================================================
// Helpers
// =============================================================================

function int(v: unknown): number {
  const n = typeof v === "number" ? v : v ? parseInt(String(v), 10) : 0;
  return Number.isFinite(n) ? Math.max(0, Math.round(n)) : 0;
}

function numOrNull(v: unknown): number | null {
  if (v === null || v === undefined) return null;
  const n = typeof v === "number" ? v : parseFloat(String(v));
  return Number.isFinite(n) ? n : null;
}

function isIsoDate(s: string): boolean {
  return /^\d{4}-\d{2}-\d{2}$/.test(s);
}
