/**
 * Auto-refresh agent. (US-BLOG-066)
 *
 * Picks a stale post (typically from blog_refresh_queue), packages its current
 * state plus the decay/refresh signal, and asks the AI to produce a fully
 * revised version. The output lands as a NEW row in blog_post_revisions with
 * reason='auto_refresh_proposal' — it does NOT overwrite the live post.
 *
 * The editor reviews the proposal via the existing History page and clicks
 * Restore to apply (which itself snapshots the current state with
 * reason='restore' before swapping). The whole flow is auditable.
 *
 * Why a proposal-only flow:
 *   * Live posts are public; mutating them silently is risky.
 *   * The Restore action already exists; this just feeds it.
 *   * Editor stays in the loop on YMYL content (caregiving / dementia / falls).
 *
 * Cost note: refresh prompts include the full current body — typically
 * ~1.5–2k tokens in. Output ~6k tokens. Caller decides when to run it; this
 * module doesn't schedule itself.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { aiGenerate, extractJson, type AiTool } from "./ai.ts";
import { logInfo, logError } from "./logger.ts";

// =============================================================================
// Tool schema — same shape as a fresh blog draft so the existing post fields
// can be replaced wholesale. The reviser tool from blog-critic.ts is a close
// cousin; we redefine here to keep this module self-contained and add a
// `change_summary` field for the queue UI.
// =============================================================================

const REFRESH_TOOL: AiTool = {
  name: "submit_refreshed_post",
  description: "Submit the refreshed blog post. Same shape as a fresh draft, plus a change_summary explaining what was updated and why.",
  input_schema: {
    type: "object",
    properties: {
      title:           { type: "string", description: "Refreshed title — usually keep close to the original; only change if the angle materially shifted." },
      slug:            { type: "string", description: "Slug — keep the existing one unless the topic genuinely changed." },
      excerpt:         { type: "string" },
      seo_title:       { type: "string" },
      seo_description: { type: "string" },
      tags:            { type: "array", items: { type: "string" } },
      category:        {
        type: "string",
        enum: ["caregiving", "elderly-care", "child-safety", "product", "how-to", "guides"],
      },
      content_html: {
        type: "string",
        description: "Full refreshed article body as raw HTML using only allowed tags. Update outdated facts, add new sub-sections where reader intent has shifted, tighten redundancies. Preserve the post's structure and voice.",
      },
      change_summary: {
        type: "string",
        description: "1–3 sentences describing what changed and why. Will be shown to the editor on the queue page.",
      },
    },
    required: ["title", "slug", "excerpt", "seo_title", "seo_description", "tags", "category", "content_html", "change_summary"],
  },
};

// =============================================================================
// Types
// =============================================================================

export interface RefreshContext {
  blogConfig: Record<string, unknown>;
  /** Reason from the queue row — drives prompt framing. */
  reason: "decay" | "serp_change" | "stale_facts" | "manual" | "periodic";
  /** Free-form metadata captured at detection time (click drops, SERP diff, etc.). */
  detectionMeta: Record<string, unknown> | null;
  /** Optional editor notes pasted into the queue. */
  editorNotes?: string | null;
}

export interface SourcePostForRefresh {
  id: string;
  slug: string;
  title: string;
  excerpt: string | null;
  content_html: string;
  seo_title: string | null;
  seo_description: string | null;
  tags: string[];
  category: string | null;
  ai_meta: unknown;
  published_at: string | null;
}

export interface RefreshProposal {
  title: string;
  slug: string;
  excerpt: string;
  seo_title: string;
  seo_description: string;
  tags: string[];
  category: string;
  content_html: string;
  change_summary: string;
}

export interface RefreshResult {
  proposal: RefreshProposal;
  /** ID of the new blog_post_revisions row carrying the proposal. */
  revision_id: string;
  ai_meta: {
    provider: string;
    model: string;
    input_tokens?: number;
    output_tokens?: number;
    cache_read_tokens?: number;
    cache_creation_tokens?: number;
    generated_at: string;
    reason: RefreshContext["reason"];
  };
}

// =============================================================================
// Public entrypoint
// =============================================================================

export async function generateRefreshProposal(
  source: SourcePostForRefresh,
  ctx: RefreshContext,
  supabase: SupabaseClient,
): Promise<RefreshResult> {
  const system = buildRefreshSystemPrompt(ctx.blogConfig);
  const user = buildRefreshUserPrompt(source, ctx);

  const result = await aiGenerate({
    system,
    messages: [{ role: "user", content: user }],
    maxTokens: 8000,
    cacheSystem: true,
    timeoutMs: 180_000,
    maxRetries: 0,
    tools: [REFRESH_TOOL],
    toolChoice: { type: "tool", name: "submit_refreshed_post" },
  });

  const proposal = extractJson<RefreshProposal>(result.text);
  validateProposal(proposal);

  // Persist the proposal as a new blog_post_revisions row. Editor reviews via
  // the existing History page and clicks Restore to apply.
  const { data: rev, error: revErr } = await supabase
    .from("blog_post_revisions")
    .insert({
      post_id: source.id,
      editor_id: null,
      title: proposal.title,
      slug: proposal.slug || source.slug,
      excerpt: proposal.excerpt,
      content_html: proposal.content_html,
      content_json: null,
      featured_image_url: null,
      seo_title: proposal.seo_title,
      seo_description: proposal.seo_description,
      canonical_url: null,
      og_image_url: null,
      tags: Array.isArray(proposal.tags) ? proposal.tags : [],
      category: proposal.category ?? source.category ?? null,
      status: "published",  // a refresh proposal is for a published post
      ai_meta: {
        kind: "refresh_proposal",
        reason: ctx.reason,
        change_summary: proposal.change_summary,
        provider: result.provider,
        model: result.model,
        input_tokens: result.inputTokens,
        output_tokens: result.outputTokens,
      },
      reason: "auto_refresh_proposal",
      parent_revision_id: null,
    })
    .select("id")
    .single();

  if (revErr || !rev) {
    logError("refresh-agent: revision insert failed", revErr ?? new Error("no row returned"), { post_id: source.id });
    throw new Error(`Failed to persist refresh proposal: ${revErr?.message ?? "unknown"}`);
  }

  const revisionId = rev.id as string;

  logInfo("refresh-agent: proposal generated", {
    post_id: source.id, slug: source.slug, revision_id: revisionId, reason: ctx.reason,
    input_tokens: result.inputTokens, output_tokens: result.outputTokens,
  });

  return {
    proposal,
    revision_id: revisionId,
    ai_meta: {
      provider: result.provider,
      model: result.model,
      input_tokens: result.inputTokens,
      output_tokens: result.outputTokens,
      cache_read_tokens: result.cacheReadTokens,
      cache_creation_tokens: result.cacheCreationTokens,
      generated_at: new Date().toISOString(),
      reason: ctx.reason,
    },
  };
}

// =============================================================================
// Prompt builders
// =============================================================================

function buildRefreshSystemPrompt(blogConfig: Record<string, unknown>): string {
  const brand = (blogConfig.brand ?? {}) as Record<string, unknown>;
  const voice = (blogConfig.voice ?? {}) as Record<string, unknown>;
  const html = (blogConfig.html_rules ?? {}) as Record<string, unknown>;
  const eeat = (blogConfig.e_e_a_t ?? {}) as Record<string, unknown>;

  const parts: string[] = [];

  parts.push(
    `You are the senior content editor for ${brand.name ?? "Daily OK"}. You're refreshing an existing published article. Your job is to update what's outdated and tighten what's loose — NOT to rewrite the whole post. Preserve everything that's still working: the title, the structure, the tone, the internal links.`,
  );

  parts.push(`Brand pillar: "${brand.tagline ?? "Presence without surveillance."}"`);
  if (brand.positioning) parts.push(`Brand positioning: ${brand.positioning}`);

  if (Array.isArray(voice.tone)) parts.push(`Tone: ${(voice.tone as string[]).join(", ")}.`);
  if (voice.must_reinforce_pillar) parts.push(`Pillar rule: ${voice.must_reinforce_pillar}`);
  if (Array.isArray(voice.avoid)) parts.push(`AVOID: ${(voice.avoid as string[]).join(" | ")}`);
  if (Array.isArray(voice.never_claim)) parts.push(`NEVER CLAIM: ${(voice.never_claim as string[]).join(" | ")}`);

  parts.push(
    `HTML rules: allowed tags only — ${Array.isArray(html.allowed_tags) ? (html.allowed_tags as string[]).join(", ") : ""}. ${html.no_markdown ?? "No markdown, no code fences, no <h1>."}`,
  );

  if (eeat.no_fabrication) parts.push(`Integrity: ${eeat.no_fabrication}`);
  if (Array.isArray(eeat.integrity_rules) && (eeat.integrity_rules as unknown[]).length > 0) {
    parts.push(`INTEGRITY RULES (absolute):\n- ${(eeat.integrity_rules as string[]).join("\n- ")}`);
  }

  parts.push(
    `Refresh playbook:\n` +
    `- Update outdated statistics, dates, product names, and references. Don't invent stats — qualify ("recent caregiver surveys suggest...") if you're unsure.\n` +
    `- Add a section addressing any new reader question that's emerged since publication (the user message will tell you what triggered the refresh).\n` +
    `- Tighten the intro and TL;DR — they get the most readership and the most decay.\n` +
    `- Preserve internal links (do not remove existing <a href="/blog/.../"> or <a href="/pricing/"> tags).\n` +
    `- Keep the post's slug and category. Only change the title if the angle has materially shifted.\n` +
    `- Write a short change_summary (1–3 sentences) the editor will see — be specific about what you updated and why.`,
  );

  parts.push("Call submit_refreshed_post exactly once. Return a complete, publish-ready post.");

  return parts.join("\n\n");
}

function buildRefreshUserPrompt(source: SourcePostForRefresh, ctx: RefreshContext): string {
  const lines: string[] = [];
  lines.push(`Refresh the published post below.`);
  lines.push("");
  lines.push(`Trigger: ${ctx.reason}`);
  if (ctx.detectionMeta) {
    lines.push(`Detection signal: ${JSON.stringify(ctx.detectionMeta)}`);
  }
  if (ctx.editorNotes) {
    lines.push(`Editor notes: ${ctx.editorNotes}`);
  }
  lines.push("");

  if (ctx.reason === "decay") {
    lines.push(
      `Likely causes of decay (think through these — the user message detection signal will tell you which apply):\n` +
      `- The information has aged out. Check dates, statistics, product names, screenshot references.\n` +
      `- Reader intent has shifted. New questions exist; old framings feel dated.\n` +
      `- A competitor now ranks for this query with a fresher angle.\n` +
      `- The TL;DR isn't extractable enough for AI Overviews.`,
    );
    lines.push("");
  } else if (ctx.reason === "serp_change") {
    lines.push(`SERP shift: a competitor's content or a SERP feature change is suspected. Adjust the angle and structure to better serve the current intent.`);
    lines.push("");
  } else if (ctx.reason === "stale_facts") {
    lines.push(`Stale facts: stats, dates, or product references are out of date. Update them or qualify them.`);
    lines.push("");
  }

  lines.push(`=== Current published post ===`);
  if (source.published_at) lines.push(`Published: ${source.published_at}`);
  lines.push(`Slug: ${source.slug}`);
  lines.push(`Title: ${source.title}`);
  lines.push(`SEO title: ${source.seo_title ?? "(none)"}`);
  lines.push(`SEO description: ${source.seo_description ?? "(none)"}`);
  lines.push(`Excerpt: ${source.excerpt ?? "(none)"}`);
  lines.push(`Tags: ${(source.tags ?? []).join(", ")}`);
  lines.push(`Category: ${source.category ?? "(none)"}`);
  lines.push("");
  lines.push("content_html:");
  lines.push(source.content_html);
  return lines.join("\n");
}

// =============================================================================
// Validation
// =============================================================================

function validateProposal(p: RefreshProposal): void {
  if (!p || typeof p !== "object") throw new Error("Refresh response is not an object");
  if (typeof p.title !== "string" || p.title.length === 0) throw new Error("Refresh proposal missing title");
  if (typeof p.content_html !== "string" || p.content_html.length < 400) {
    throw new Error(`Refresh content_html too short (${p.content_html?.length ?? 0} chars)`);
  }
  if (/<(h1|script|iframe|style)\b/i.test(p.content_html)) {
    throw new Error("Refresh content_html contains disallowed tag");
  }
  if (typeof p.change_summary !== "string" || p.change_summary.length === 0) {
    throw new Error("Refresh proposal missing change_summary");
  }
  if (!Array.isArray(p.tags)) p.tags = [];
}
