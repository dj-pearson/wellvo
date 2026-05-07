/**
 * Per-platform syndication generator. (US-BLOG-044/045/046/048)
 *
 * Given a published blog post and a list of target platforms, ask the AI for
 * platform-tailored copy in a single tool call. The result becomes one
 * `social_posts` row per platform variant — Make.com handles actual posting.
 *
 * Platforms supported in v1:
 *   * x         — thread (≥6 tweets, hook-first, CTA last; ≤270 chars/tweet)
 *   * linkedin  — long-form post (hook + 800–1500 chars body + 3–5 hashtags + link-in-comment)
 *   * facebook  — short post (≤300 chars + link)
 *   * pinterest — 3 pin copy variants (title ≤100 + description ≤500)
 *
 * The brand voice + AVOID list + integrity rules are pulled from the existing
 * `blog_generation_config` row so syndicated copy stays on-brand.
 */

import { aiGenerate, extractJson, type AiTool } from "./ai.ts";
import { addUtm, utmBlogUrl } from "./utm.ts";
import { logInfo } from "./logger.ts";

// =============================================================================
// Types
// =============================================================================

export type SyndicationPlatform = "x" | "linkedin" | "facebook" | "pinterest";

export const SUPPORTED_PLATFORMS: readonly SyndicationPlatform[] =
  ["x", "linkedin", "facebook", "pinterest"] as const;

export interface SyndicationSourcePost {
  id: string;
  slug: string;
  title: string;
  excerpt: string | null;
  content_html: string;
  category: string | null;
  tags: string[];
  primary_keyword?: string | null;
}

interface XThread {
  hook: string;          // first tweet (≤270 chars)
  tweets: string[];      // body tweets (each ≤270 chars)
  cta: string;           // final tweet linking back (≤270 chars; we append the URL)
}

interface LinkedInPost {
  hook: string;          // first 2 lines, visible before "see more"
  body: string;          // 800–1500 chars
  hashtags: string[];    // 3–5
  first_comment: string; // copy to paste in first comment with the link
}

interface FacebookPost {
  copy: string;          // ≤300 chars
}

interface PinterestPin {
  title: string;         // ≤100 chars, keyword-forward
  description: string;   // ≤500 chars, natural language
}

interface SyndicationPayload {
  x?: XThread;
  linkedin?: LinkedInPost;
  facebook?: FacebookPost;
  pinterest?: PinterestPin[];   // expect 3 variants
}

export interface SyndicationVariantRow {
  platform: SyndicationPlatform;
  /** Single text blob ready to drop into social_posts.content. */
  content: string;
  /** Tagged URL for the variant — also stored on social_posts.link_url. */
  link_url: string;
  /** For Pinterest: which variant index (0-based); else null. */
  variant_index: number | null;
  /** Free-form metadata for Make.com to use (e.g., LinkedIn first_comment, X hook). */
  meta: Record<string, unknown>;
}

export interface SyndicationResult {
  variants: SyndicationVariantRow[];
  ai_meta: {
    provider: string;
    model: string;
    input_tokens?: number;
    output_tokens?: number;
    cache_read_tokens?: number;
    cache_creation_tokens?: number;
    generated_at: string;
    platforms_requested: SyndicationPlatform[];
  };
}

// =============================================================================
// Tool schema
// =============================================================================

const SYNDICATE_TOOL: AiTool = {
  name: "submit_syndication",
  description: "Submit per-platform copy variants for the blog post. Only fill the platform fields requested. Be platform-native — never produce one variant and reuse it.",
  input_schema: {
    type: "object",
    properties: {
      x: {
        type: "object",
        description: "X/Twitter thread. Hook is the first tweet — most readers see only this.",
        properties: {
          hook: { type: "string", description: "First tweet, ≤270 chars. No emojis unless they earn engagement. No link in this tweet." },
          tweets: {
            type: "array",
            items: { type: "string" },
            description: "Body tweets, 5–11 of them, each ≤270 chars. One idea per tweet. Build narrative momentum.",
          },
          cta: { type: "string", description: "Final tweet. ≤220 chars — we append the tagged URL. Soft CTA: 'Full piece →' rather than 'click here'." },
        },
        required: ["hook", "tweets", "cta"],
      },
      linkedin: {
        type: "object",
        description: "LinkedIn long-form post. The link goes in the first comment, not the body — LinkedIn deprioritizes posts with outbound links.",
        properties: {
          hook: { type: "string", description: "First 2 lines (≤220 chars total). Must hook BEFORE the 'see more' truncation." },
          body: { type: "string", description: "Body 800–1500 chars. Use blank lines liberally; LinkedIn formats line breaks. No outbound URL in body." },
          hashtags: { type: "array", items: { type: "string" }, description: "3–5 hashtags, lowercase, no leading #." },
          first_comment: { type: "string", description: "Copy for the first comment that contains the link. Single line, conversational." },
        },
        required: ["hook", "body", "hashtags", "first_comment"],
      },
      facebook: {
        type: "object",
        description: "Facebook short post. ≤300 chars including link callout but excluding the actual URL (we append).",
        properties: {
          copy: { type: "string", description: "≤300 chars. Conversational, low-key. End with a phrase that invites the click ('full piece' / 'we wrote this for caregivers like you')." },
        },
        required: ["copy"],
      },
      pinterest: {
        type: "array",
        description: "Pinterest pin copy. Produce exactly 3 distinct variants — different headlines and angles, NOT the same idea reworded.",
        items: {
          type: "object",
          properties: {
            title: { type: "string", description: "≤100 chars. Keyword-forward. Pinterest is search-driven — write for someone typing the query." },
            description: { type: "string", description: "≤500 chars. Natural language. Front-load the keyword." },
          },
          required: ["title", "description"],
        },
      },
    },
  },
};

// =============================================================================
// Public entrypoint
// =============================================================================

export async function generateSyndication(
  post: SyndicationSourcePost,
  platforms: SyndicationPlatform[],
  blogConfig: Record<string, unknown>,
): Promise<SyndicationResult> {
  if (platforms.length === 0) throw new Error("No platforms requested");
  for (const p of platforms) {
    if (!SUPPORTED_PLATFORMS.includes(p)) throw new Error(`Unsupported platform: ${p}`);
  }

  const system = buildSyndicationSystemPrompt(blogConfig);
  const user = buildSyndicationUserPrompt(post, platforms);

  const result = await aiGenerate({
    system,
    messages: [{ role: "user", content: user }],
    maxTokens: 4500,
    cacheSystem: true,
    timeoutMs: 120_000,
    maxRetries: 0,
    tools: [SYNDICATE_TOOL],
    toolChoice: { type: "tool", name: "submit_syndication" },
  });

  const payload = extractJson<SyndicationPayload>(result.text);
  const variants = buildVariantRows(post, platforms, payload);

  logInfo("blog syndicator: generated variants", {
    post_id: post.id, slug: post.slug, platforms, variant_count: variants.length,
  });

  return {
    variants,
    ai_meta: {
      provider: result.provider,
      model: result.model,
      input_tokens: result.inputTokens,
      output_tokens: result.outputTokens,
      cache_read_tokens: result.cacheReadTokens,
      cache_creation_tokens: result.cacheCreationTokens,
      generated_at: new Date().toISOString(),
      platforms_requested: platforms,
    },
  };
}

// =============================================================================
// Variant row construction
// =============================================================================

function buildVariantRows(
  post: SyndicationSourcePost,
  platforms: SyndicationPlatform[],
  payload: SyndicationPayload,
): SyndicationVariantRow[] {
  const out: SyndicationVariantRow[] = [];

  if (platforms.includes("x") && payload.x) {
    const link = utmBlogUrl(post.slug, "x");
    const tweets = [payload.x.hook, ...payload.x.tweets, `${payload.x.cta} ${link}`.trim()];
    const numbered = tweets.map((t, i) => `${i + 1}/ ${t.trim()}`).join("\n\n");
    out.push({
      platform: "x",
      content: numbered,
      link_url: link,
      variant_index: null,
      meta: {
        hook: payload.x.hook,
        tweet_count: tweets.length,
        cta: payload.x.cta,
      },
    });
  }

  if (platforms.includes("linkedin") && payload.linkedin) {
    const link = utmBlogUrl(post.slug, "linkedin");
    const tags = (payload.linkedin.hashtags ?? [])
      .map((h) => h.replace(/^#+/, "").trim().toLowerCase())
      .filter(Boolean)
      .map((h) => `#${h}`)
      .join(" ");
    const composed = [
      payload.linkedin.hook,
      "",
      payload.linkedin.body,
      "",
      tags,
    ].filter((p) => p !== undefined).join("\n").trim();
    out.push({
      platform: "linkedin",
      content: composed,
      link_url: link,
      variant_index: null,
      meta: {
        hook: payload.linkedin.hook,
        first_comment: `${payload.linkedin.first_comment}\n${link}`,
        hashtags: payload.linkedin.hashtags,
      },
    });
  }

  if (platforms.includes("facebook") && payload.facebook) {
    const link = utmBlogUrl(post.slug, "facebook");
    out.push({
      platform: "facebook",
      content: `${payload.facebook.copy.trim()}\n\n${link}`,
      link_url: link,
      variant_index: null,
      meta: {},
    });
  }

  if (platforms.includes("pinterest") && Array.isArray(payload.pinterest)) {
    payload.pinterest.slice(0, 3).forEach((pin, idx) => {
      const link = addUtm(`https://dailyok.net/blog/${post.slug}`, {
        source: "pinterest",
        campaign: post.slug,
        content: `pin_${idx + 1}`,
      });
      out.push({
        platform: "pinterest",
        content: `${pin.title}\n\n${pin.description}`,
        link_url: link,
        variant_index: idx,
        meta: {
          title: pin.title,
          description: pin.description,
          variant: `pin_${idx + 1}`,
        },
      });
    });
  }

  return out;
}

// =============================================================================
// Prompt builders
// =============================================================================

function buildSyndicationSystemPrompt(blogConfig: Record<string, unknown>): string {
  const brand = (blogConfig.brand ?? {}) as Record<string, unknown>;
  const voice = (blogConfig.voice ?? {}) as Record<string, unknown>;

  const parts: string[] = [];

  parts.push(
    `You are the head of social for ${brand.name ?? "Daily OK"}. You translate a long-form blog post into platform-native copy. Each platform has a different culture and reading pattern — do NOT produce one variant and rephrase it for the others.`,
  );

  parts.push(`Brand pillar: "${brand.tagline ?? "Presence without surveillance."}"`);
  if (brand.positioning) parts.push(`Brand positioning: ${brand.positioning}`);
  if (Array.isArray(brand.audiences)) parts.push(`Audiences: ${(brand.audiences as string[]).join(" • ")}`);

  if (Array.isArray(voice.tone)) parts.push(`Tone targets: ${(voice.tone as string[]).join(", ")}.`);
  if (voice.must_reinforce_pillar) parts.push(`Pillar rule: ${voice.must_reinforce_pillar}`);
  if (Array.isArray(voice.avoid)) parts.push(`AVOID: ${(voice.avoid as string[]).join(" | ")}`);
  if (Array.isArray(voice.never_claim)) parts.push(`NEVER CLAIM: ${(voice.never_claim as string[]).join(" | ")}`);

  parts.push(
    `Platform rules (hard constraints):\n` +
    `- X: hook tweet ≤270 chars, NO link in the hook. Body 5–11 tweets, ≤270 chars each. Final CTA tweet ≤220 chars (we append the URL). Numbering format "N/" is added by us — don't include it yourself.\n` +
    `- LinkedIn: hook ≤220 chars (must hook before the 'see more' fold). Body 800–1500 chars. NEVER put outbound URLs in the body — they go in the first comment. 3–5 hashtags lowercase.\n` +
    `- Facebook: ≤300 chars copy. We append the URL on a new line. Conversational, low-key.\n` +
    `- Pinterest: title ≤100 chars, keyword-forward (Pinterest is search-driven). Description ≤500 chars, front-load the keyword. 3 variants must be genuinely different — different headline angles, different starting hooks, NOT the same sentence reworded.`,
  );

  parts.push(
    `Integrity: never invent statistics, named sources, or product capabilities the brand doesn't have. If unsure, be qualitative ("many caregivers report") rather than specific.`,
  );

  parts.push(
    `Call submit_syndication exactly once. Only fill platform fields requested in the user message — leave others undefined.`,
  );

  return parts.join("\n\n");
}

function buildSyndicationUserPrompt(
  post: SyndicationSourcePost,
  platforms: SyndicationPlatform[],
): string {
  const lines: string[] = [];
  lines.push(`Generate syndication copy for the following platforms: ${platforms.join(", ")}.`);
  lines.push("");
  lines.push(`Post slug: ${post.slug}`);
  lines.push(`Post title: ${post.title}`);
  if (post.primary_keyword) lines.push(`Primary keyword: ${post.primary_keyword}`);
  if (post.category) lines.push(`Category: ${post.category}`);
  if (post.tags.length > 0) lines.push(`Tags: ${post.tags.join(", ")}`);
  if (post.excerpt) {
    lines.push(`Excerpt: ${post.excerpt}`);
  }
  lines.push("");
  lines.push("=== Article body ===");
  // Cap to keep token use predictable on long pillar posts.
  const text = stripHtml(post.content_html).slice(0, 9000);
  lines.push(text);
  return lines.join("\n");
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
