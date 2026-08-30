/**
 * Internal-link auto-injection. (US-BLOG-055)
 *
 * Runs immediately after a new post is published. Finds related published
 * posts (by tag overlap, cluster match, or keyword match), scans the body
 * for natural anchor text matching the candidates, and injects up to N
 * contextual links inline. Every proposal — accepted, auto-inserted, or
 * skipped — is logged in `blog_internal_link_suggestions` so the editor can
 * audit and revert via the regular post-revisions trail.
 *
 * Conservative by design:
 *   * Only candidates with score ≥ MIN_RELEVANCE are considered.
 *   * Anchor text must already appear in the body; we don't insert text the
 *     post doesn't already contain.
 *   * Won't link a phrase that's already inside an <a>.
 *   * Caps at MAX_INSERTS per post run.
 *   * Won't link to drafts or archived posts.
 *
 * Pure-ish — takes a SupabaseClient for DB lookups, returns the rewritten
 * body and a list of suggestion records to persist.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { logInfo, logError } from "./logger.ts";

// =============================================================================
// Types
// =============================================================================

export interface InternalLinkerOptions {
  /** Maximum number of new links to inject. */
  maxInserts?: number;
  /** Skip candidates whose relevance score is below this threshold (0–100). */
  minRelevance?: number;
  /** Maximum candidate posts to evaluate (cost cap). */
  maxCandidates?: number;
}

export interface SuggestionRecord {
  post_id: string;
  target_post_id: string;
  anchor_text: string;
  source: "tag_overlap" | "cluster_match" | "keyword_match";
  relevance_score: number;
  status: "auto_inserted" | "skipped" | "proposed";
  notes: string | null;
}

export interface LinkerResult {
  /** Rewritten content_html, with new <a> tags inserted. Same as input if nothing changed. */
  body: string;
  /** Audit records to insert into blog_internal_link_suggestions. */
  suggestions: SuggestionRecord[];
  inserted: number;
  considered: number;
}

interface SourcePost {
  id: string;
  slug: string;
  title: string;
  content_html: string;
  category: string | null;
  tags: string[];
  primary_keyword: string | null;
  cluster: string | null;
}

interface CandidatePost {
  id: string;
  slug: string;
  title: string;
  category: string | null;
  tags: string[];
  ai_meta: unknown;
}

interface ScoredCandidate {
  post: CandidatePost;
  score: number;
  source: SuggestionRecord["source"];
  /** Phrases that, if found in the body, are valid anchors for this candidate. */
  candidateAnchors: string[];
}

// =============================================================================
// Tunables
// =============================================================================

const DEFAULT_MAX_INSERTS = 3;
const DEFAULT_MIN_RELEVANCE = 35;
const DEFAULT_MAX_CANDIDATES = 30;

// =============================================================================
// Public entrypoint
// =============================================================================

export async function autoInjectInternalLinks(
  source: SourcePost,
  supabase: SupabaseClient,
  opts: InternalLinkerOptions = {},
): Promise<LinkerResult> {
  const maxInserts = opts.maxInserts ?? DEFAULT_MAX_INSERTS;
  const minRelevance = opts.minRelevance ?? DEFAULT_MIN_RELEVANCE;
  const maxCandidates = opts.maxCandidates ?? DEFAULT_MAX_CANDIDATES;

  const candidates = await fetchCandidatePosts(source, supabase, maxCandidates);
  if (candidates.length === 0) {
    return { body: source.content_html, suggestions: [], inserted: 0, considered: 0 };
  }

  const scored = candidates
    .map((c) => scoreCandidate(c, source))
    .filter((c) => c.score >= minRelevance)
    .sort((a, b) => b.score - a.score);

  let body = source.content_html;
  const suggestions: SuggestionRecord[] = [];
  let inserted = 0;
  const usedAnchorsLowercase = new Set<string>();

  for (const cand of scored) {
    if (inserted >= maxInserts) {
      suggestions.push(buildSuggestion(source, cand, cand.candidateAnchors[0] ?? cand.post.title, "skipped",
        "Cap reached — left as proposal."));
      continue;
    }

    const choice = pickAnchorAndInsert(body, cand.candidateAnchors, source.slug, cand.post.slug, usedAnchorsLowercase);
    if (choice.inserted) {
      body = choice.newBody;
      usedAnchorsLowercase.add(choice.anchor.toLowerCase());
      suggestions.push(buildSuggestion(source, cand, choice.anchor, "auto_inserted", null));
      inserted++;
    } else {
      suggestions.push(buildSuggestion(source, cand, cand.candidateAnchors[0] ?? cand.post.title, "skipped", choice.skipReason));
    }
  }

  logInfo("blog internal linker: pass complete", {
    post_id: source.id, slug: source.slug,
    considered: scored.length, inserted,
  });

  return { body, suggestions, inserted, considered: scored.length };
}

/**
 * Persist the suggestion records and (when body changed) write the new body
 * back to blog_posts. Snapshots the prior state to blog_post_revisions with
 * reason='auto_internal_link' so the change is auditable.
 *
 * Failures here are non-fatal — the post is already published and the
 * automation should not block on bookkeeping issues.
 */
export async function applyLinkerResult(
  postId: string,
  originalBody: string,
  result: LinkerResult,
  supabase: SupabaseClient,
): Promise<void> {
  // 1. Insert suggestion rows. Use upsert-on-conflict so re-running on the
  // same post → target → anchor doesn't blow up the unique constraint.
  if (result.suggestions.length > 0) {
    const { error: insErr } = await supabase
      .from("blog_internal_link_suggestions")
      .upsert(result.suggestions, {
        onConflict: "post_id,target_post_id,anchor_text",
        ignoreDuplicates: true,
      });
    if (insErr) {
      logError("internal-linker: suggestion insert failed", insErr, { postId });
    }
  }

  // 2. If the body changed, snapshot prior state then update.
  if (result.body !== originalBody && result.inserted > 0) {
    const { error: snapErr } = await supabase.rpc("snapshot_blog_post_revision", {
      p_post_id: postId,
      p_editor_id: null,
      p_reason: "auto_internal_link",
      p_parent_revision_id: null,
    });
    if (snapErr) {
      logError("internal-linker: snapshot failed", snapErr, { postId });
    }

    const { error: updErr } = await supabase
      .from("blog_posts")
      .update({ content_html: result.body })
      .eq("id", postId);
    if (updErr) {
      logError("internal-linker: body update failed", updErr, { postId });
    }
  }
}

// =============================================================================
// Candidate fetching + scoring
// =============================================================================

async function fetchCandidatePosts(
  source: SourcePost,
  supabase: SupabaseClient,
  limit: number,
): Promise<CandidatePost[]> {
  // Pull recently published posts (excluding the source itself) — order by
  // published_at desc so newer related content is preferred. Limit caps cost.
  const { data, error } = await supabase
    .from("blog_posts")
    .select("id, slug, title, category, tags, ai_meta")
    .eq("status", "published")
    .neq("id", source.id)
    .order("published_at", { ascending: false })
    .limit(limit);

  if (error) {
    logError("internal-linker: candidate fetch failed", error, { source_id: source.id });
    return [];
  }
  return (data ?? []) as CandidatePost[];
}

function scoreCandidate(candidate: CandidatePost, source: SourcePost): ScoredCandidate {
  let score = 0;
  let bestSource: SuggestionRecord["source"] = "tag_overlap";
  const anchors = new Set<string>();

  // Tag overlap — strong signal of editorial relatedness.
  const sourceTags = new Set((source.tags ?? []).map((t) => t.toLowerCase()));
  const candTags = (candidate.tags ?? []).map((t) => t.toLowerCase());
  let tagOverlap = 0;
  for (const tag of candTags) {
    if (sourceTags.has(tag)) tagOverlap++;
  }
  score += tagOverlap * 15;
  if (tagOverlap > 0) bestSource = "tag_overlap";

  // Category match — same content cluster.
  if (candidate.category && source.category && candidate.category === source.category) {
    score += 20;
    if (bestSource !== "tag_overlap") bestSource = "cluster_match";
  }

  // Cluster match via ai_meta.cluster (set by generate-next-article)
  const candCluster = (candidate.ai_meta as Record<string, unknown> | null)?.cluster;
  if (typeof candCluster === "string" && source.cluster && candCluster === source.cluster) {
    score += 25;
    if (bestSource === "tag_overlap" && tagOverlap === 0) bestSource = "cluster_match";
  }

  // Title-word overlap — the title itself is a candidate anchor.
  anchors.add(candidate.title);

  // Primary keyword from the candidate is also a strong anchor candidate.
  const candKeyword = primaryKeywordFromAiMeta(candidate.ai_meta);
  if (candKeyword) {
    anchors.add(candKeyword);
    if (source.content_html.toLowerCase().includes(candKeyword.toLowerCase())) {
      score += 30;
      bestSource = "keyword_match";
    }
  }

  // Tag-as-anchor: if a tag overlaps and appears in the body, that's a strong fit.
  for (const tag of candTags) {
    if (sourceTags.has(tag) && source.content_html.toLowerCase().includes(tag.toLowerCase())) {
      anchors.add(tag);
    }
  }

  return {
    post: candidate,
    score: Math.max(0, Math.min(100, Math.round(score))),
    source: bestSource,
    candidateAnchors: Array.from(anchors)
      .filter((a) => a && a.length >= 3 && a.length <= 90)
      .sort((a, b) => b.length - a.length), // prefer longer/more specific anchors
  };
}

function primaryKeywordFromAiMeta(ai_meta: unknown): string | null {
  if (ai_meta && typeof ai_meta === "object") {
    const m = ai_meta as Record<string, unknown>;
    if (typeof m.primary_keyword === "string" && m.primary_keyword) return m.primary_keyword;
  }
  return null;
}

// =============================================================================
// Anchor selection + insertion
// =============================================================================

interface InsertChoice {
  inserted: true;
  anchor: string;
  newBody: string;
}
interface InsertSkip {
  inserted: false;
  skipReason: string;
}

function pickAnchorAndInsert(
  body: string,
  candidateAnchors: string[],
  sourceSlug: string,
  targetSlug: string,
  usedAnchorsLowercase: Set<string>,
): InsertChoice | InsertSkip {
  if (sourceSlug === targetSlug) return { inserted: false, skipReason: "Same slug." };

  for (const anchor of candidateAnchors) {
    if (usedAnchorsLowercase.has(anchor.toLowerCase())) continue;
    // Trailing slash: production 308s /blog/<slug> to /blog/<slug>/, so a
    // no-slash href makes every injected internal link cost a redirect
    // (US-WEB010). Matches canonicalPath() in website/src/lib/canonical.ts.
    const result = injectFirstOccurrence(body, anchor, `/blog/${targetSlug}/`);
    if (result) return { inserted: true, anchor, newBody: result };
  }
  return { inserted: false, skipReason: "No natural anchor occurrence found in body." };
}

/**
 * Replace the first occurrence of `phrase` in `html` with an <a> tag — but
 * only if the phrase appears OUTSIDE any existing tag (no nested anchors)
 * and isn't inside a heading (h1–h6) or already an anchor's text.
 *
 * Returns the new HTML or null when no safe spot was found.
 */
function injectFirstOccurrence(html: string, phrase: string, href: string): string | null {
  if (!phrase || !html) return null;
  const phraseLower = phrase.toLowerCase();

  // Walk the HTML in tag-aware chunks. Track depth into <a> and heading tags.
  // When we're outside any anchor and outside headings, look for a
  // case-insensitive match of `phrase`.
  const tagRe = /<\/?[a-z][^>]*>/gi;
  let cursor = 0;
  let inAnchor = false;
  let inHeading = false;
  let m: RegExpExecArray | null;

  const chunks: Array<{ start: number; end: number; outside: boolean }> = [];

  while ((m = tagRe.exec(html)) !== null) {
    if (m.index > cursor) {
      chunks.push({ start: cursor, end: m.index, outside: !inAnchor && !inHeading });
    }
    const tag = m[0].toLowerCase();
    if (/^<a\b/.test(tag)) inAnchor = true;
    else if (/^<\/a>/.test(tag)) inAnchor = false;
    else if (/^<h[1-6]\b/.test(tag)) inHeading = true;
    else if (/^<\/h[1-6]>/.test(tag)) inHeading = false;
    cursor = m.index + m[0].length;
  }
  if (cursor < html.length) {
    chunks.push({ start: cursor, end: html.length, outside: !inAnchor && !inHeading });
  }

  for (const chunk of chunks) {
    if (!chunk.outside) continue;
    const slice = html.slice(chunk.start, chunk.end);
    const idx = slice.toLowerCase().indexOf(phraseLower);
    if (idx === -1) continue;

    // Word-boundary check — avoid linking inside a longer word.
    const before = slice[idx - 1];
    const after = slice[idx + phrase.length];
    if (before && /\w/.test(before)) continue;
    if (after && /\w/.test(after)) continue;

    const matched = slice.slice(idx, idx + phrase.length);
    const newSlice =
      slice.slice(0, idx) +
      `<a href="${href}">${matched}</a>` +
      slice.slice(idx + phrase.length);

    return html.slice(0, chunk.start) + newSlice + html.slice(chunk.end);
  }
  return null;
}

// =============================================================================
// Suggestion record builder
// =============================================================================

function buildSuggestion(
  source: SourcePost,
  cand: ScoredCandidate,
  anchor: string,
  status: SuggestionRecord["status"],
  notes: string | null,
): SuggestionRecord {
  return {
    post_id: source.id,
    target_post_id: cand.post.id,
    anchor_text: anchor,
    source: cand.source,
    relevance_score: cand.score,
    status,
    notes,
  };
}
