/**
 * Self-critiquing agent loop for blog post drafts. (US-BLOG-039)
 *
 * Pipeline (per PRD):
 *   generator → critic → reviser → critic → reviser, max N iterations
 *
 * The critic evaluates a draft against a fixed rubric (clarity, originality,
 * evidence, voice match, SEO compliance, factual grounding, structural
 * balance) and either declares the draft good enough or proposes specific
 * fixes. The reviser regenerates the article using those fixes as additional
 * constraints. Each iteration is captured so the final post carries the
 * critique log in ai_meta and the revisions table can show the evolution.
 *
 * The critic is a separate prompt — same model, different framing. We stop
 * early if score ≥ threshold OR no blocker-severity issues are flagged. Loop
 * costs are capped by max_iterations (default 1, configurable per workspace).
 */

import { aiGenerate, extractJson, type AiTool } from "./ai.ts";
import { logInfo } from "./logger.ts";

// =============================================================================
// Types
// =============================================================================

export interface DraftArticle {
  title: string;
  slug: string;
  excerpt: string;
  seo_title: string;
  seo_description: string;
  tags: string[];
  category: string;
  content_html: string;
  topic_rationale?: string;
  primary_keyword?: string;
}

export interface CritiqueIssue {
  severity: "blocker" | "major" | "minor";
  area:
    | "clarity" | "originality" | "evidence" | "voice_match"
    | "seo" | "factual_grounding" | "structural_balance";
  message: string;
  location?: string;
  suggested_fix: string;
}

export interface Critique {
  score: number;
  summary: string;
  issues: CritiqueIssue[];
  should_continue: boolean;
}

export interface CritiqueIteration {
  iteration: number;
  /** The draft that was critiqued (NOT the revised one). */
  draft_summary: { title: string; word_count: number; content_html_length: number };
  critique: Critique;
  /** True when this iteration produced a revised draft. */
  revised: boolean;
  tokens: { input: number; output: number; cache_read?: number; cache_creation?: number };
}

export interface CritiqueLoopResult {
  finalArticle: DraftArticle;
  /**
   * Drafts produced along the way. Index 0 = original input. Index n =
   * revision after iteration n. Always includes the final article at the end.
   */
  drafts: DraftArticle[];
  iterations: CritiqueIteration[];
  stopped_reason:
    | "no_significant_issues" | "score_threshold_met" | "max_iterations_reached"
    | "no_blocker_issues" | "critique_disabled";
}

export interface CritiqueLoopConfig {
  enabled: boolean;
  max_iterations: number;
  score_threshold: number;
}

export interface CritiqueContext {
  /** Brand voice + html rules + e-e-a-t config used by the original prompt. */
  blogConfig: Record<string, unknown>;
  primaryKeyword?: string | null;
  intentStage?: string | null;
  requiresMedicalReview?: boolean;
  eEatNotes?: string | null;
}

// =============================================================================
// Tool schemas
// =============================================================================

const CRITIQUE_TOOL: AiTool = {
  name: "submit_critique",
  description: "Evaluate the blog post draft against the rubric. Be specific, honest, and concrete. Cite locations and propose concrete revisions.",
  input_schema: {
    type: "object",
    properties: {
      score: {
        type: "integer", minimum: 0, maximum: 100,
        description: "Overall quality score 0–100 across the full rubric.",
      },
      summary: {
        type: "string",
        description: "1–2 sentence overall assessment of the draft.",
      },
      issues: {
        type: "array",
        items: {
          type: "object",
          properties: {
            severity: { type: "string", enum: ["blocker", "major", "minor"] },
            area: {
              type: "string",
              enum: ["clarity", "originality", "evidence", "voice_match", "seo", "factual_grounding", "structural_balance"],
            },
            message: { type: "string", description: "What's wrong, in one or two sentences." },
            location: { type: "string", description: "Where in the post (heading text, first paragraph, the TL;DR, etc.)." },
            suggested_fix: { type: "string", description: "Concrete, actionable revision the writer should make." },
          },
          required: ["severity", "area", "message", "suggested_fix"],
        },
      },
      should_continue: {
        type: "boolean",
        description: "True iff a revision pass is warranted. Set false when the draft is good enough or only has trivial nits.",
      },
    },
    required: ["score", "summary", "issues", "should_continue"],
  },
};

const REVISE_TOOL: AiTool = {
  name: "submit_revised_post",
  description: "Submit the revised blog post that addresses the critic's feedback. Same shape as a fresh draft.",
  input_schema: {
    type: "object",
    properties: {
      title:           { type: "string" },
      slug:            { type: "string" },
      excerpt:         { type: "string" },
      seo_title:       { type: "string" },
      seo_description: { type: "string" },
      tags:            { type: "array", items: { type: "string" } },
      category:        {
        type: "string",
        enum: ["caregiving", "elderly-care", "child-safety", "product", "how-to", "guides"],
      },
      content_html:    {
        type: "string",
        description: "Full revised article body as raw HTML using only allowed tags. Address every blocker- and major-severity issue from the critique.",
      },
    },
    required: ["title", "slug", "excerpt", "seo_title", "seo_description", "tags", "category", "content_html"],
  },
};

// =============================================================================
// Public entrypoint
// =============================================================================

export async function runCritiqueLoop(
  initial: DraftArticle,
  ctx: CritiqueContext,
  cfg: CritiqueLoopConfig,
): Promise<CritiqueLoopResult> {
  if (!cfg.enabled) {
    return {
      finalArticle: initial,
      drafts: [initial],
      iterations: [],
      stopped_reason: "critique_disabled",
    };
  }

  const maxIters = Math.max(1, Math.min(3, cfg.max_iterations));
  const threshold = Math.max(0, Math.min(100, cfg.score_threshold));
  const drafts: DraftArticle[] = [initial];
  const iterations: CritiqueIteration[] = [];
  let current = initial;

  for (let i = 1; i <= maxIters; i++) {
    const critique = await critiqueArticle(current, ctx);
    const blockers = critique.critique.issues.filter((x) => x.severity === "blocker");

    iterations.push({
      iteration: i,
      draft_summary: summarize(current),
      critique: critique.critique,
      revised: false,
      tokens: critique.tokens,
    });

    logInfo("blog critique iteration", {
      iteration: i, score: critique.critique.score, issues: critique.critique.issues.length,
      blockers: blockers.length, should_continue: critique.critique.should_continue,
    });

    if (critique.critique.score >= threshold) {
      return { finalArticle: current, drafts, iterations, stopped_reason: "score_threshold_met" };
    }
    if (!critique.critique.should_continue) {
      return { finalArticle: current, drafts, iterations, stopped_reason: "no_significant_issues" };
    }
    if (blockers.length === 0 && critique.critique.issues.every((x) => x.severity === "minor")) {
      return { finalArticle: current, drafts, iterations, stopped_reason: "no_blocker_issues" };
    }
    if (i === maxIters) break;

    // Revise based on critique feedback
    const revised = await reviseArticle(current, critique.critique, ctx);
    drafts.push(revised);
    iterations[iterations.length - 1].revised = true;
    current = revised;
  }

  return { finalArticle: current, drafts, iterations, stopped_reason: "max_iterations_reached" };
}

// =============================================================================
// Critique pass
// =============================================================================

async function critiqueArticle(
  article: DraftArticle,
  ctx: CritiqueContext,
): Promise<{ critique: Critique; tokens: CritiqueIteration["tokens"] }> {
  const system = buildCriticSystemPrompt(ctx);
  const user = buildCriticUserPrompt(article, ctx);

  const result = await aiGenerate({
    system,
    messages: [{ role: "user", content: user }],
    maxTokens: 2500,
    cacheSystem: true,
    timeoutMs: 90_000,
    maxRetries: 0,
    tools: [CRITIQUE_TOOL],
    toolChoice: { type: "tool", name: "submit_critique" },
  });

  const critique = extractJson<Critique>(result.text);
  // Defensive normalization — the model occasionally omits arrays.
  if (!Array.isArray(critique.issues)) critique.issues = [];
  if (typeof critique.score !== "number") critique.score = 0;
  if (typeof critique.should_continue !== "boolean") critique.should_continue = critique.issues.length > 0;

  return {
    critique,
    tokens: {
      input: result.inputTokens ?? 0,
      output: result.outputTokens ?? 0,
      cache_read: result.cacheReadTokens,
      cache_creation: result.cacheCreationTokens,
    },
  };
}

function buildCriticSystemPrompt(ctx: CritiqueContext): string {
  const config = ctx.blogConfig;
  const brand = (config.brand ?? {}) as Record<string, unknown>;
  const voice = (config.voice ?? {}) as Record<string, unknown>;
  const eeat = (config.e_e_a_t ?? {}) as Record<string, unknown>;
  const seo = (config.seo ?? {}) as Record<string, unknown>;

  const parts: string[] = [];

  parts.push(
    `You are a senior editorial critic for ${brand.name ?? "Daily OK"}. You are reviewing a blog draft produced by another AI. Your job is to be specific, honest, and concrete — not encouraging. The writer cannot push back; only flag what genuinely needs to change.`,
  );

  parts.push(`Brand pillar: "${brand.tagline ?? "Presence without surveillance."}"`);
  if (brand.positioning) parts.push(`Brand positioning: ${brand.positioning}`);

  parts.push(
    `Rubric — score 0–100 across these axes weighted equally:\n` +
    `1. clarity — sentences are concrete, no filler, no throat-clearing.\n` +
    `2. originality — perspective or framing isn't generic SEO mush.\n` +
    `3. evidence — claims are supported, qualified, or honestly hedged ("many caregivers report"). No invented stats or named sources.\n` +
    `4. voice_match — matches the brand voice and avoids the AVOID list.\n` +
    `5. seo — title/H2/intro use the primary keyword naturally; structure earns featured snippets.\n` +
    `6. factual_grounding — for YMYL topics, no medical advice beyond general info; cites recognized authorities where appropriate.\n` +
    `7. structural_balance — TL;DR blockquote at top; H2s every 150–250 words; ends with checklist or CTA.`,
  );

  if (Array.isArray(voice.tone)) parts.push(`Tone targets: ${(voice.tone as string[]).join(", ")}.`);
  if (voice.must_reinforce_pillar) parts.push(`Pillar rule (must be quietly present): ${voice.must_reinforce_pillar}`);
  if (Array.isArray(voice.avoid)) parts.push(`AVOID list: ${(voice.avoid as string[]).join(" | ")}`);
  if (Array.isArray(voice.never_claim)) parts.push(`NEVER CLAIM: ${(voice.never_claim as string[]).join(" | ")}`);
  if (Array.isArray(eeat.integrity_rules) && (eeat.integrity_rules as unknown[]).length > 0) {
    parts.push(`INTEGRITY RULES (violations are blocker-severity):\n- ${(eeat.integrity_rules as string[]).join("\n- ")}`);
  }

  parts.push(
    `SEO targets: title ≤ ${seo.title_max_chars ?? 70}, seo_title ≤ ${seo.seo_title_max_chars ?? 60}, seo_description ${seo.seo_description_chars ?? "140–160"} chars.`,
  );

  parts.push(
    `Severity guide:\n` +
    `- blocker: violates an INTEGRITY RULE, contains fabricated claims, ageist/scare-tactic language, or claims a product capability we don't have.\n` +
    `- major: voice mismatch, missing TL;DR, no internal link, keyword absent from title or intro, unsupported claim.\n` +
    `- minor: tightening, redundant transitions, single missing comma. Don't list these unless asked.\n` +
    `\nBe sparing — flag at most 6 issues. Set should_continue to false when only minor issues remain.`,
  );

  return parts.filter(Boolean).join("\n\n");
}

function buildCriticUserPrompt(article: DraftArticle, ctx: CritiqueContext): string {
  const lines: string[] = [];
  lines.push("Critique the following draft. Call submit_critique exactly once.");
  lines.push("");
  if (ctx.primaryKeyword) lines.push(`Primary keyword: ${ctx.primaryKeyword}`);
  if (ctx.intentStage) lines.push(`Intent stage: ${ctx.intentStage}`);
  if (ctx.requiresMedicalReview) lines.push(`YMYL: yes — apply factual_grounding strictly.`);
  if (ctx.eEatNotes) lines.push(`Editor notes: ${ctx.eEatNotes}`);
  lines.push("");
  lines.push(`Title: ${article.title}`);
  lines.push(`SEO title: ${article.seo_title} (${article.seo_title.length} chars)`);
  lines.push(`SEO description: ${article.seo_description} (${article.seo_description.length} chars)`);
  lines.push(`Excerpt: ${article.excerpt} (${article.excerpt.length} chars)`);
  lines.push(`Tags: ${(article.tags ?? []).join(", ")}`);
  lines.push(`Category: ${article.category}`);
  lines.push("");
  lines.push("=== content_html ===");
  lines.push(article.content_html);
  return lines.join("\n");
}

// =============================================================================
// Revision pass
// =============================================================================

async function reviseArticle(
  current: DraftArticle,
  critique: Critique,
  ctx: CritiqueContext,
): Promise<DraftArticle> {
  const system = buildReviserSystemPrompt(ctx);
  const user = buildReviserUserPrompt(current, critique);

  const result = await aiGenerate({
    system,
    messages: [{ role: "user", content: user }],
    maxTokens: 8000,
    cacheSystem: true,
    timeoutMs: 180_000,
    maxRetries: 0,
    tools: [REVISE_TOOL],
    toolChoice: { type: "tool", name: "submit_revised_post" },
  });

  const revised = extractJson<DraftArticle>(result.text);
  // Carry forward fields the reviser tool doesn't have (rationale, primary keyword)
  return {
    ...current,
    ...revised,
    topic_rationale: current.topic_rationale,
    primary_keyword: current.primary_keyword,
  };
}

function buildReviserSystemPrompt(ctx: CritiqueContext): string {
  // Re-use the same brand voice / rules used by the original generator so the
  // reviser is held to the same standards. Pass the existing config-derived
  // text through.
  const config = ctx.blogConfig;
  const brand = (config.brand ?? {}) as Record<string, unknown>;
  const voice = (config.voice ?? {}) as Record<string, unknown>;
  const html = (config.html_rules ?? {}) as Record<string, unknown>;

  const parts: string[] = [];
  parts.push(
    `You are the senior content strategist and editor for ${brand.name ?? "Daily OK"}. You are revising an existing draft based on a critic's feedback. Address every blocker- and major-severity issue. Preserve everything that's working — do not regenerate from scratch.`,
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
  parts.push("Call submit_revised_post exactly once with the full revised article. Do not output prose outside the tool call.");

  return parts.join("\n\n");
}

function buildReviserUserPrompt(current: DraftArticle, critique: Critique): string {
  const lines: string[] = [];
  lines.push(`Revise the draft below. Address every blocker and major issue from the critic. Leave minor issues alone unless they're trivial to fix while you're in there.`);
  lines.push("");
  lines.push(`Critic's overall assessment: ${critique.summary}`);
  lines.push(`Critic's score: ${critique.score}/100`);
  lines.push("");
  lines.push("Issues to address:");
  for (const issue of critique.issues) {
    lines.push(`- [${issue.severity.toUpperCase()} · ${issue.area}] ${issue.message}${issue.location ? ` (at: ${issue.location})` : ""} — Fix: ${issue.suggested_fix}`);
  }
  lines.push("");
  lines.push("=== current draft ===");
  lines.push(`Title: ${current.title}`);
  lines.push(`SEO title: ${current.seo_title}`);
  lines.push(`SEO description: ${current.seo_description}`);
  lines.push(`Excerpt: ${current.excerpt}`);
  lines.push(`Tags: ${(current.tags ?? []).join(", ")}`);
  lines.push(`Category: ${current.category}`);
  lines.push("");
  lines.push("content_html:");
  lines.push(current.content_html);
  return lines.join("\n");
}

// =============================================================================
// Helpers
// =============================================================================

function summarize(article: DraftArticle): CritiqueIteration["draft_summary"] {
  const text = (article.content_html ?? "").replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim();
  return {
    title: article.title,
    word_count: text.split(/\s+/).filter(Boolean).length,
    content_html_length: (article.content_html ?? "").length,
  };
}

// =============================================================================
// Config helper
// =============================================================================

export function readCritiqueLoopConfig(blogConfig: Record<string, unknown>): CritiqueLoopConfig {
  const raw = (blogConfig.critique_loop ?? {}) as Record<string, unknown>;
  const enabled = raw.enabled === undefined ? true : raw.enabled === true;
  const max = typeof raw.max_iterations === "number" ? raw.max_iterations : 1;
  const threshold = typeof raw.score_threshold === "number" ? raw.score_threshold : 80;
  return {
    enabled,
    max_iterations: Math.max(1, Math.min(3, Math.round(max))),
    score_threshold: Math.max(0, Math.min(100, Math.round(threshold))),
  };
}
