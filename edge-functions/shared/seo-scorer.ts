/**
 * Deterministic on-page SEO scorer for blog_posts. (US-BLOG-033)
 *
 * Pure function — given a snapshot of the editorial fields plus the primary
 * keyword, return a 0-100 score, the per-component breakdown, and an ordered
 * list of human-readable hints the editor can act on.
 *
 * Used by:
 *   * admin-blog edge function — scores manual edits on save and exposes a
 *     `score_post` action for live preview in the editor.
 *   * blog-generator (publishArticle) — scores AI-generated posts at publish.
 *
 * Twelve components sum to exactly 100. Adjust weights here, not in callers.
 */

export interface ScoreableBlogPost {
  title?: string | null;
  slug?: string | null;
  excerpt?: string | null;
  content_html?: string | null;
  seo_title?: string | null;
  seo_description?: string | null;
  tags?: string[] | null;
  /** Resolved separately by callers; usually ai_meta.primary_keyword. */
  primary_keyword?: string | null;
}

export interface ScoreComponent {
  key: string;
  label: string;
  earned: number;
  max: number;
  /** One-sentence explanation of how this component scored, for the editor UI. */
  detail: string;
}

export interface SeoScoreResult {
  score: number;             // 0-100
  breakdown: ScoreComponent[];
  hints: string[];           // Ordered: highest-impact fixes first
  scored_at: string;         // ISO timestamp
  primary_keyword: string | null;
}

// =============================================================================
// Public entrypoint
// =============================================================================

export function scoreBlogPost(post: ScoreableBlogPost): SeoScoreResult {
  const title = (post.title ?? "").trim();
  const seoTitle = (post.seo_title ?? "").trim();
  const seoDescription = (post.seo_description ?? "").trim();
  const excerpt = (post.excerpt ?? "").trim();
  const html = post.content_html ?? "";
  const keyword = (post.primary_keyword ?? "").trim().toLowerCase();

  const text = stripHtml(html);
  const words = text.split(/\s+/).filter(Boolean);
  const h2Texts = extractTagText(html, "h2");
  const firstBlock = firstNonWhitespaceBlock(html);
  const introText = (firstBlock ?? text).slice(0, 280).toLowerCase();
  const internalLinks = countInternalLinks(html);
  const totalImages = countMatches(html, /<img\b[^>]*>/gi);
  const imagesWithAlt = countMatches(html, /<img\b[^>]*\balt\s*=\s*["'][^"']+["'][^>]*>/gi);

  const breakdown: ScoreComponent[] = [];

  // ---- Component 1 — Title length (15)
  breakdown.push(scoreTitleLength(title));

  // ---- Component 2 — SEO title length (10)
  breakdown.push(scoreSeoTitleLength(seoTitle));

  // ---- Component 3 — SEO description length (10)
  breakdown.push(scoreSeoDescriptionLength(seoDescription));

  // ---- Component 4 — Excerpt length (5)
  breakdown.push(scoreExcerptLength(excerpt));

  // ---- Component 5 — Keyword in title (10)
  breakdown.push(scoreKeywordInTitle(title, keyword));

  // ---- Component 6 — Keyword in intro (10)
  breakdown.push(scoreKeywordInIntro(introText, keyword));

  // ---- Component 7 — Keyword in any H2 (5)
  breakdown.push(scoreKeywordInH2(h2Texts, keyword));

  // ---- Component 8 — Word count (5)
  breakdown.push(scoreWordCount(words.length));

  // ---- Component 9 — H2 count (10)
  breakdown.push(scoreH2Count(h2Texts.length));

  // ---- Component 10 — Internal links (5)
  breakdown.push(scoreInternalLinks(internalLinks));

  // ---- Component 11 — Image alt coverage (5)
  breakdown.push(scoreImageAltCoverage(totalImages, imagesWithAlt));

  // ---- Component 12 — TL;DR blockquote at top (10)
  breakdown.push(scoreTldrBlockquote(firstBlock));

  const score = breakdown.reduce((sum, c) => sum + c.earned, 0);
  const hints = buildHints(breakdown);

  return {
    score: Math.max(0, Math.min(100, Math.round(score))),
    breakdown,
    hints,
    scored_at: new Date().toISOString(),
    primary_keyword: keyword || null,
  };
}

// =============================================================================
// Component scorers
// =============================================================================

function scoreTitleLength(title: string): ScoreComponent {
  const len = title.length;
  let earned = 0;
  let detail = "";
  if (len === 0) { earned = 0; detail = "Title is empty."; }
  else if (len >= 50 && len <= 60) { earned = 15; detail = `Title length ${len} is ideal (50–60).`; }
  else if ((len >= 45 && len < 50) || (len > 60 && len <= 65)) { earned = 12; detail = `Title length ${len} is close to ideal — aim for 50–60.`; }
  else if ((len >= 40 && len < 45) || (len > 65 && len <= 70)) { earned = 8; detail = `Title length ${len} is acceptable but tighten to 50–60.`; }
  else { earned = 0; detail = `Title length ${len} is outside the 40–70 acceptable range.`; }
  return { key: "title_length", label: "Title length (50–60)", earned, max: 15, detail };
}

function scoreSeoTitleLength(seoTitle: string): ScoreComponent {
  const len = seoTitle.length;
  let earned = 0;
  let detail = "";
  if (len === 0) { earned = 0; detail = "SEO title is empty — falls back to the post title in SERPs."; }
  else if (len >= 30 && len <= 60) { earned = 10; detail = `SEO title length ${len} fits SERP rendering.`; }
  else if ((len >= 20 && len < 30) || (len > 60 && len <= 70)) { earned = 6; detail = `SEO title length ${len} risks truncation; aim for 30–60.`; }
  else { earned = 0; detail = `SEO title length ${len} is outside the 20–70 range.`; }
  return { key: "seo_title_length", label: "SEO title (30–60)", earned, max: 10, detail };
}

function scoreSeoDescriptionLength(desc: string): ScoreComponent {
  const len = desc.length;
  let earned = 0;
  let detail = "";
  if (len === 0) { earned = 0; detail = "SEO description missing — Google will pick its own snippet."; }
  else if (len >= 140 && len <= 160) { earned = 10; detail = `SEO description length ${len} is ideal.`; }
  else if ((len >= 120 && len < 140) || (len > 160 && len <= 180)) { earned = 6; detail = `SEO description length ${len} is close — target 140–160.`; }
  else { earned = 0; detail = `SEO description length ${len} is outside the 120–180 range.`; }
  return { key: "seo_description_length", label: "SEO description (140–160)", earned, max: 10, detail };
}

function scoreExcerptLength(excerpt: string): ScoreComponent {
  const len = excerpt.length;
  let earned = 0;
  let detail = "";
  if (len === 0) { earned = 0; detail = "Excerpt missing — used on the blog index and in shares."; }
  else if (len >= 140 && len <= 180) { earned = 5; detail = `Excerpt length ${len} is ideal.`; }
  else if ((len >= 120 && len < 140) || (len > 180 && len <= 200)) { earned = 3; detail = `Excerpt length ${len} is close — target 140–180.`; }
  else { earned = 0; detail = `Excerpt length ${len} is outside the 120–200 range.`; }
  return { key: "excerpt_length", label: "Excerpt (140–180)", earned, max: 5, detail };
}

function scoreKeywordInTitle(title: string, keyword: string): ScoreComponent {
  if (!keyword) {
    return { key: "keyword_in_title", label: "Keyword in title", earned: 0, max: 10,
      detail: "No primary keyword set — score skipped. Capture one in ai_meta.primary_keyword." };
  }
  const present = title.toLowerCase().includes(keyword);
  return {
    key: "keyword_in_title", label: "Keyword in title",
    earned: present ? 10 : 0, max: 10,
    detail: present ? `Primary keyword "${keyword}" found in title.` : `Primary keyword "${keyword}" not in title.`,
  };
}

function scoreKeywordInIntro(introLower: string, keyword: string): ScoreComponent {
  if (!keyword) {
    return { key: "keyword_in_intro", label: "Keyword in intro", earned: 0, max: 10,
      detail: "No primary keyword set — score skipped." };
  }
  const present = introLower.includes(keyword);
  return {
    key: "keyword_in_intro", label: "Keyword in intro (first ~280 chars)",
    earned: present ? 10 : 0, max: 10,
    detail: present ? `Primary keyword "${keyword}" found in opening passage.` : `Primary keyword "${keyword}" not in opening passage — weave it into the TL;DR.`,
  };
}

function scoreKeywordInH2(h2Texts: string[], keyword: string): ScoreComponent {
  if (!keyword) {
    return { key: "keyword_in_h2", label: "Keyword in any H2", earned: 0, max: 5,
      detail: "No primary keyword set — score skipped." };
  }
  const present = h2Texts.some((t) => t.toLowerCase().includes(keyword));
  return {
    key: "keyword_in_h2", label: "Keyword in any H2",
    earned: present ? 5 : 0, max: 5,
    detail: present ? "Primary keyword appears in at least one H2." : "Primary keyword not in any H2 subhead.",
  };
}

function scoreWordCount(count: number): ScoreComponent {
  let earned = 0;
  let detail = "";
  if (count >= 1500) { earned = 5; detail = `Word count ${count} signals depth.`; }
  else if (count >= 900) { earned = 4; detail = `Word count ${count} is solid; aim for 1,500+ on pillar pieces.`; }
  else if (count >= 700) { earned = 2; detail = `Word count ${count} is short for ranking competitive keywords.`; }
  else { earned = 0; detail = `Word count ${count} is too short — minimum 700 for SEO.`; }
  return { key: "word_count", label: "Word count (≥1,500 ideal)", earned, max: 5, detail };
}

function scoreH2Count(count: number): ScoreComponent {
  let earned = 0;
  let detail = "";
  if (count === 0) { earned = 0; detail = "No H2 subheads — body is one wall of text."; }
  else if (count >= 4 && count <= 12) { earned = 10; detail = `${count} H2 subheads structure the post well.`; }
  else if (count === 3 || (count >= 13 && count <= 15)) { earned = 6; detail = `${count} H2 subheads — slightly off ideal (4–12).`; }
  else if (count <= 2) { earned = 2; detail = `Only ${count} H2 subhead${count === 1 ? "" : "s"} — add more to improve scannability.`; }
  else { earned = 2; detail = `${count} H2 subheads — too many; consider consolidating.`; }
  return { key: "h2_count", label: "H2 count (4–12)", earned, max: 10, detail };
}

function scoreInternalLinks(count: number): ScoreComponent {
  let earned = 0;
  let detail = "";
  if (count === 0) { earned = 0; detail = "No internal links — add 1–5 to related posts or product pages."; }
  else if (count >= 1 && count <= 5) { earned = 5; detail = `${count} internal link${count === 1 ? "" : "s"} — ideal range.`; }
  else if (count <= 10) { earned = 3; detail = `${count} internal links — slightly heavy; aim for 1–5.`; }
  else { earned = 0; detail = `${count} internal links — too many; risks looking spammy.`; }
  return { key: "internal_links", label: "Internal links (1–5)", earned, max: 5, detail };
}

function scoreImageAltCoverage(total: number, withAlt: number): ScoreComponent {
  if (total === 0) {
    return { key: "image_alt_coverage", label: "Image alt coverage", earned: 5, max: 5,
      detail: "No images — nothing to caption." };
  }
  const ratio = withAlt / total;
  let earned = 0;
  let detail = "";
  if (ratio >= 0.999) { earned = 5; detail = `All ${total} image${total === 1 ? "" : "s"} have alt text.`; }
  else if (ratio >= 0.8) { earned = 3; detail = `${withAlt}/${total} images have alt text — fix the rest for accessibility + SEO.`; }
  else { earned = 0; detail = `Only ${withAlt}/${total} images have alt text.`; }
  return { key: "image_alt_coverage", label: "Image alt coverage", earned, max: 5, detail };
}

function scoreTldrBlockquote(firstBlock: string | null): ScoreComponent {
  if (!firstBlock) {
    return { key: "tldr_blockquote", label: "TL;DR blockquote at top", earned: 0, max: 10,
      detail: "Body is empty." };
  }
  const present = /<blockquote\b/i.test(firstBlock);
  return {
    key: "tldr_blockquote", label: "TL;DR blockquote at top",
    earned: present ? 10 : 0, max: 10,
    detail: present
      ? "Opens with a TL;DR blockquote — extractable by AI Overviews."
      : "First block is not a TL;DR blockquote. AI Overviews / featured snippets prefer this.",
  };
}

// =============================================================================
// Hints
// =============================================================================

function buildHints(breakdown: ScoreComponent[]): string[] {
  return breakdown
    .filter((c) => c.earned < c.max)
    .sort((a, b) => (b.max - b.earned) - (a.max - a.earned))
    .map((c) => `${c.label}: ${c.detail}`);
}

// =============================================================================
// HTML helpers (lightweight — no DOM parser)
// =============================================================================

function stripHtml(html: string): string {
  return html
    .replace(/<script[\s\S]*?<\/script>/gi, " ")
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/\s+/g, " ")
    .trim();
}

function extractTagText(html: string, tag: string): string[] {
  const re = new RegExp(`<${tag}\\b[^>]*>([\\s\\S]*?)</${tag}>`, "gi");
  const matches: string[] = [];
  let m: RegExpExecArray | null;
  while ((m = re.exec(html)) !== null) {
    matches.push(stripHtml(m[1]));
  }
  return matches;
}

function firstNonWhitespaceBlock(html: string): string | null {
  // Match the first block-level element. The TL;DR rule is "<blockquote> at top".
  const re = /<(blockquote|p|h2|h3|ul|ol)\b[^>]*>[\s\S]*?<\/\1>/i;
  const m = html.match(re);
  return m ? m[0] : null;
}

function countMatches(html: string, re: RegExp): number {
  let n = 0;
  // RegExp must be /g
  while (re.exec(html) !== null) n++;
  return n;
}

function countInternalLinks(html: string): number {
  // Internal = relative href OR href on dailyok.net
  const re = /<a\b[^>]*\bhref\s*=\s*["']([^"']+)["'][^>]*>/gi;
  let n = 0;
  let m: RegExpExecArray | null;
  while ((m = re.exec(html)) !== null) {
    const href = m[1].trim();
    if (!href || href.startsWith("#") || href.startsWith("mailto:") || href.startsWith("tel:")) continue;
    if (href.startsWith("/")) { n++; continue; }
    try {
      const u = new URL(href);
      if (/(^|\.)dailyok\.net$/i.test(u.hostname)) n++;
    } catch {
      // Malformed URL — treat as not internal.
    }
  }
  return n;
}
