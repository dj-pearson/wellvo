/**
 * Pre-publish QA pass for blog posts. (US-BLOG-040)
 *
 * Server-side checklist that runs whenever a post is being published. Errors
 * block the publish unless an editor explicitly forces it; warnings and
 * informational items are surfaced but never block.
 *
 * Used by admin-blog (qa_post action; createPost/updatePost gates) and is
 * cheap enough to run on every save without observable latency.
 *
 * Design:
 *   * Pure structural checks happen on the post object itself.
 *   * Internal-link resolution touches the DB (existence check against
 *     blog_posts.slug), so the function takes a SupabaseClient.
 *   * No mutations — strictly read-only.
 */

import type { SupabaseClient } from "@supabase/supabase-js";

// =============================================================================
// Types
// =============================================================================

export interface QaCheck {
  id: string;
  label: string;
  severity: "error" | "warning" | "info";
  passed: boolean;
  message: string;
  /** Free-form details rendered in the editor (e.g. list of broken links). */
  details?: unknown;
}

export interface QaResult {
  checks: QaCheck[];
  errorCount: number;
  warningCount: number;
  infoCount: number;
  passedCount: number;
  /** True iff zero `error`-severity checks failed. */
  canPublish: boolean;
  ranAt: string;
}

export interface QaInputPost {
  id?: string | null;
  title?: string | null;
  slug?: string | null;
  excerpt?: string | null;
  content_html?: string | null;
  seo_title?: string | null;
  seo_description?: string | null;
  og_image_url?: string | null;
  featured_image_url?: string | null;
}

// =============================================================================
// Known top-level routes the public site exposes. Hard-coded against
// website/src/App.tsx — keep in sync when public routes change.
// =============================================================================

const KNOWN_STATIC_ROUTES = new Set<string>([
  "/", "/privacy", "/terms", "/support", "/pricing", "/accessibility",
  "/elderly-care", "/child-safety", "/cookies", "/dmca", "/blog",
  "/compare", "/how-it-works",
]);

const SLUG_RE = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
const DISALLOWED_TAG_RE = /<\s*(h1|script|iframe|style|object|embed)\b/i;
const HOWITWORKS_FALLBACK = new Set(["/how-it-works"]);

// =============================================================================
// Public entrypoint
// =============================================================================

export async function runPrePublishQA(
  post: QaInputPost,
  supabase: SupabaseClient,
): Promise<QaResult> {
  const html = post.content_html ?? "";
  const title = (post.title ?? "").trim();
  const slug = (post.slug ?? "").trim();
  const excerpt = (post.excerpt ?? "").trim();
  const seoTitle = (post.seo_title ?? "").trim();
  const seoDescription = (post.seo_description ?? "").trim();
  const ogImage = (post.og_image_url ?? post.featured_image_url ?? "").trim();

  const text = stripHtml(html);
  const wordCount = text.split(/\s+/).filter(Boolean).length;
  const stripped = text.length;
  const h2Count = countMatches(html, /<h2\b[^>]*>/gi);
  const h3WithoutH2 = hasSkippedHeadingLevels(html);

  const checks: QaCheck[] = [];

  // ----------------- ERRORS -----------------

  checks.push({
    id: "title_present",
    label: "Title is set",
    severity: "error",
    passed: title.length > 0,
    message: title.length > 0 ? `Title: "${title}".` : "Title is empty.",
  });

  const slugValid = slug.length > 0 && slug.length <= 80 && SLUG_RE.test(slug);
  checks.push({
    id: "slug_valid",
    label: "Slug is kebab-case and ≤80 chars",
    severity: "error",
    passed: slugValid,
    message: slugValid
      ? `Slug "${slug}" is well-formed.`
      : `Slug "${slug}" must match kebab-case (lowercase a–z, 0–9, hyphens) and be ≤80 chars.`,
  });

  checks.push({
    id: "body_present",
    label: "Body has at least 400 characters",
    severity: "error",
    passed: stripped >= 400,
    message: stripped >= 400
      ? `Stripped body is ${stripped} chars.`
      : `Stripped body is only ${stripped} chars — minimum 400 to publish.`,
  });

  const disallowed = html.match(DISALLOWED_TAG_RE);
  checks.push({
    id: "no_disallowed_tags",
    label: "No <h1>, <script>, <iframe>, <style>, <object>, or <embed>",
    severity: "error",
    passed: !disallowed,
    message: disallowed
      ? `Body contains a disallowed tag: ${disallowed[0]}.`
      : "All tags allowed.",
  });

  const linkResult = await validateInternalLinks(html, supabase);
  checks.push({
    id: "internal_links_resolve",
    label: "Internal links resolve",
    severity: "error",
    passed: linkResult.broken.length === 0,
    message: linkResult.broken.length === 0
      ? `${linkResult.totalChecked} internal link(s) verified.`
      : `${linkResult.broken.length} broken internal link(s).`,
    details: linkResult.broken.length > 0 ? { broken: linkResult.broken } : undefined,
  });

  // ----------------- WARNINGS -----------------

  checks.push({
    id: "og_image_set",
    label: "OG / featured image is set",
    severity: "warning",
    passed: ogImage.length > 0,
    message: ogImage.length > 0
      ? "Has an image for social shares."
      : "No og_image_url or featured_image_url — social shares will be plain.",
  });

  checks.push({
    id: "seo_title_set",
    label: "SEO title is set",
    severity: "warning",
    passed: seoTitle.length > 0,
    message: seoTitle.length > 0 ? `SEO title: "${seoTitle}".` : "SEO title empty — search engines will use the H1.",
  });

  checks.push({
    id: "seo_description_set",
    label: "SEO description is set",
    severity: "warning",
    passed: seoDescription.length > 0,
    message: seoDescription.length > 0
      ? `SEO description set (${seoDescription.length} chars).`
      : "SEO description empty — Google will pick its own snippet.",
  });

  checks.push({
    id: "excerpt_set",
    label: "Excerpt is set",
    severity: "warning",
    passed: excerpt.length > 0,
    message: excerpt.length > 0
      ? `Excerpt set (${excerpt.length} chars).`
      : "Excerpt empty — used on the blog index and in shares.",
  });

  const altResult = inspectImageAlts(html);
  checks.push({
    id: "image_alt_coverage",
    label: "Every <img> has alt text",
    severity: "warning",
    passed: altResult.totalImages === 0 || altResult.missingAlt.length === 0,
    message: altResult.totalImages === 0
      ? "No images in the body."
      : altResult.missingAlt.length === 0
        ? `All ${altResult.totalImages} image(s) have alt text.`
        : `${altResult.missingAlt.length}/${altResult.totalImages} image(s) missing alt text.`,
    details: altResult.missingAlt.length > 0 ? { missingAlt: altResult.missingAlt } : undefined,
  });

  checks.push({
    id: "title_length_ok",
    label: "Title is 40–70 characters",
    severity: "warning",
    passed: title.length >= 40 && title.length <= 70,
    message: title.length === 0
      ? "Title is empty."
      : (title.length >= 40 && title.length <= 70)
        ? `Title length ${title.length} is in range.`
        : `Title length ${title.length} is outside the 40–70 range.`,
  });

  checks.push({
    id: "seo_description_length_ok",
    label: "SEO description is 140–160 characters",
    severity: "warning",
    passed: seoDescription.length >= 140 && seoDescription.length <= 160,
    message: seoDescription.length === 0
      ? "SEO description empty."
      : (seoDescription.length >= 140 && seoDescription.length <= 160)
        ? `SEO description length ${seoDescription.length} is ideal.`
        : `SEO description length ${seoDescription.length} should be 140–160.`,
  });

  checks.push({
    id: "word_count_ok",
    label: "Word count ≥ 700",
    severity: "warning",
    passed: wordCount >= 700,
    message: wordCount >= 700
      ? `Word count: ${wordCount}.`
      : `Word count is ${wordCount} — minimum 700 for ranking.`,
  });

  checks.push({
    id: "tldr_blockquote_at_top",
    label: "Opens with a TL;DR blockquote",
    severity: "warning",
    passed: hasTldrBlockquoteAtTop(html),
    message: hasTldrBlockquoteAtTop(html)
      ? "First block is a <blockquote> — extractable by AI Overviews."
      : "First block is not a <blockquote>. AI Overviews and featured snippets prefer this.",
  });

  checks.push({
    id: "h2_count_ok",
    label: "Has ≥3 H2 subheads",
    severity: "warning",
    passed: h2Count >= 3,
    message: h2Count >= 3
      ? `${h2Count} H2 subhead(s).`
      : `Only ${h2Count} H2 subhead(s) — body needs more structure.`,
  });

  // ----------------- INFO -----------------

  checks.push({
    id: "heading_hierarchy_clean",
    label: "Heading hierarchy is clean (no H2→H4 jumps)",
    severity: "info",
    passed: !h3WithoutH2,
    message: h3WithoutH2
      ? "Heading levels skip — e.g., an H4 appears without an H3 before it."
      : "Heading hierarchy is clean.",
  });

  const anchors = inspectAnchorText(html);
  checks.push({
    id: "anchor_text_quality",
    label: "Anchor text is descriptive (no 'click here' / bare URLs)",
    severity: "info",
    passed: anchors.problems.length === 0,
    message: anchors.problems.length === 0
      ? `${anchors.total} link(s) — all with descriptive text.`
      : `${anchors.problems.length} link(s) have weak anchor text.`,
    details: anchors.problems.length > 0 ? { weak: anchors.problems } : undefined,
  });

  // ----------------- Tally -----------------

  const errorCount = checks.filter((c) => c.severity === "error" && !c.passed).length;
  const warningCount = checks.filter((c) => c.severity === "warning" && !c.passed).length;
  const infoCount = checks.filter((c) => c.severity === "info" && !c.passed).length;
  const passedCount = checks.filter((c) => c.passed).length;

  return {
    checks,
    errorCount,
    warningCount,
    infoCount,
    passedCount,
    canPublish: errorCount === 0,
    ranAt: new Date().toISOString(),
  };
}

// =============================================================================
// Internal link validation
// =============================================================================

interface LinkValidation {
  totalChecked: number;
  broken: Array<{ href: string; reason: string }>;
}

async function validateInternalLinks(
  html: string,
  supabase: SupabaseClient,
): Promise<LinkValidation> {
  const re = /<a\b[^>]*\bhref\s*=\s*["']([^"']+)["'][^>]*>/gi;
  const broken: Array<{ href: string; reason: string }> = [];
  const slugsToCheck = new Set<string>();
  const internalPaths: string[] = [];
  let m: RegExpExecArray | null;

  while ((m = re.exec(html)) !== null) {
    const href = m[1].trim();
    if (!href) continue;
    if (href.startsWith("#") || href.startsWith("mailto:") || href.startsWith("tel:")) continue;

    let path: string | null = null;
    if (href.startsWith("/")) {
      path = href.split(/[?#]/)[0];
    } else {
      try {
        const u = new URL(href);
        if (/(^|\.)dailyok\.net$/i.test(u.hostname)) path = u.pathname.split(/[?#]/)[0] || "/";
      } catch {
        // Malformed URL — skip; not our problem to flag here.
      }
    }
    if (!path) continue;

    internalPaths.push(path);

    // Resolve route. Compare on the bare form so both /pricing and /pricing/
    // validate: production serves the trailing-slash form (US-WEB010) and is
    // what new content uses, while older generated posts carry the bare one.
    const routeKey = path.length > 1 ? path.replace(/\/$/, "") : path;
    if (KNOWN_STATIC_ROUTES.has(routeKey) || HOWITWORKS_FALLBACK.has(routeKey)) continue;

    if (path.startsWith("/blog/")) {
      const slug = path.slice("/blog/".length).replace(/\/$/, "");
      if (!slug) {
        broken.push({ href, reason: "Empty blog slug." });
        continue;
      }
      slugsToCheck.add(slug);
    } else if (path.startsWith("/compare/")) {
      // Compare pages have a separate routing scheme; skip strict validation
      // for now — better to under-block than over-block.
      continue;
    } else {
      broken.push({ href, reason: `No known route for ${path}.` });
    }
  }

  if (slugsToCheck.size > 0) {
    const slugs = Array.from(slugsToCheck);
    const { data, error } = await supabase
      .from("blog_posts")
      .select("slug, status")
      .in("slug", slugs);

    if (error) {
      // Treat DB error as a failed check rather than silently passing.
      broken.push({ href: "(any /blog/* link)", reason: `Could not verify slugs: ${error.message}` });
    } else {
      const found = new Map<string, string>();
      for (const r of data ?? []) {
        found.set(r.slug as string, r.status as string);
      }
      for (const slug of slugs) {
        const status = found.get(slug);
        if (!status) {
          broken.push({ href: `/blog/${slug}`, reason: "No matching blog_posts row." });
        } else if (status !== "published") {
          broken.push({ href: `/blog/${slug}`, reason: `Linked post is "${status}", not published.` });
        }
      }
    }
  }

  return { totalChecked: internalPaths.length, broken };
}

// =============================================================================
// HTML inspectors
// =============================================================================

function inspectImageAlts(html: string): { totalImages: number; missingAlt: string[] } {
  const re = /<img\b[^>]*>/gi;
  let total = 0;
  const missing: string[] = [];
  let m: RegExpExecArray | null;
  while ((m = re.exec(html)) !== null) {
    total++;
    const tag = m[0];
    const altMatch = tag.match(/\balt\s*=\s*["']([^"']*)["']/i);
    if (!altMatch || altMatch[1].trim().length === 0) {
      const srcMatch = tag.match(/\bsrc\s*=\s*["']([^"']+)["']/i);
      missing.push(srcMatch ? srcMatch[1] : "(unknown image)");
    }
  }
  return { totalImages: total, missingAlt: missing };
}

function inspectAnchorText(html: string): { total: number; problems: Array<{ href: string; anchor: string }> } {
  const re = /<a\b[^>]*\bhref\s*=\s*["']([^"']+)["'][^>]*>([\s\S]*?)<\/a>/gi;
  let total = 0;
  const problems: Array<{ href: string; anchor: string }> = [];
  let m: RegExpExecArray | null;
  while ((m = re.exec(html)) !== null) {
    total++;
    const href = m[1].trim();
    const anchor = stripHtml(m[2]).trim();
    if (!anchor) {
      problems.push({ href, anchor: "(empty)" });
      continue;
    }
    if (/^(click here|here|read more|learn more|this|link)$/i.test(anchor)) {
      problems.push({ href, anchor });
      continue;
    }
    // Bare URL anchor — treat as weak.
    if (/^https?:\/\//i.test(anchor) || anchor === href) {
      problems.push({ href, anchor });
      continue;
    }
  }
  return { total, problems };
}

function hasTldrBlockquoteAtTop(html: string): boolean {
  const re = /<(blockquote|p|h2|h3|ul|ol)\b[^>]*>/i;
  const m = html.match(re);
  return !!m && m[1].toLowerCase() === "blockquote";
}

function hasSkippedHeadingLevels(html: string): boolean {
  // Walk all headings in document order. Flag if level jumps by >1 from the
  // previous heading (e.g., H2 → H4 with no H3 between).
  const re = /<h([1-6])\b[^>]*>/gi;
  let prev = 0;
  let m: RegExpExecArray | null;
  while ((m = re.exec(html)) !== null) {
    const level = parseInt(m[1], 10);
    if (prev > 0 && level - prev > 1) return true;
    prev = level;
  }
  return false;
}

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

function countMatches(html: string, re: RegExp): number {
  let n = 0;
  while (re.exec(html) !== null) n++;
  return n;
}
