/**
 * Shared blog generator — used by both the Make.com webhook
 * (/generate-next-article) and the admin UI (/admin-blog-ai
 * action=generate_next_from_bank).
 *
 * Flow:
 *   1. Claim the next pending row from blog_title_bank via
 *      claim_next_blog_title() (FOR UPDATE SKIP LOCKED).
 *   2. If a row was claimed, prompt the AI with the row's title +
 *      keywords + outline and publish the result.
 *   3. If the bank is empty (or skipBank=true), fall back to the
 *      generation config's cluster bank + the list of already-published
 *      titles — the AI picks a fresh non-competing topic.
 *
 * Reads env:
 *   BLOG_GENERATION_AUTHOR_ID  optional default author UUID
 *   SITE_ORIGIN                default https://dailyok.net
 */

import { supabaseAdmin } from "./supabase.ts";
import { aiGenerate, extractJson, type AiTool } from "./ai.ts";
import { logInfo, logError } from "./logger.ts";

/**
 * Tool schema for structured article output. Anthropic returns the tool's
 * `input` as an already-parsed object, which we serialize with JSON.stringify —
 * guaranteeing valid JSON on the way back through extractJson. This eliminates
 * the "unescaped quote inside content_html" class of parse failures that occur
 * when the model emits JSON as free text.
 */
const PUBLISH_BLOG_POST_TOOL: AiTool = {
  name: "publish_blog_post",
  description: "Submit a complete, publish-ready blog post for Daily OK. Call this exactly once with every field filled in according to the system-prompt guidance.",
  input_schema: {
    type: "object",
    properties: {
      title: { type: "string", description: "Compelling, specific title under 70 characters." },
      slug: { type: "string", description: "Kebab-case slug under 80 characters; keyword-forward." },
      excerpt: { type: "string", description: "140–180 characters, written to earn the click." },
      seo_title: { type: "string", description: "Under 60 characters; keyword-forward." },
      seo_description: { type: "string", description: "140–160 characters; answers the search intent in active voice." },
      tags: { type: "array", items: { type: "string" }, description: "3–6 lowercase tags." },
      category: {
        type: "string",
        enum: ["caregiving", "elderly-care", "child-safety", "product", "how-to", "guides"],
        description: "Exactly one of the allowed categories.",
      },
      content_html: {
        type: "string",
        description: "Full article body as raw HTML using only these tags: h2, h3, p, ul, ol, li, strong, em, a, blockquote. No markdown, no code fences, no h1, no script/iframe/style. Opens with a 40–60 word TL;DR in a <blockquote>. Subheads every 150–250 words. Ends with a practical checklist or one-step CTA.",
      },
      primary_keyword: {
        type: "string",
        description: "Only set in fallback mode: the keyword you chose from the cluster bank.",
      },
      topic_rationale: {
        type: "string",
        description: "Only set in fallback mode: one sentence naming the cluster and why this title doesn't duplicate anything already published.",
      },
    },
    required: ["title", "slug", "excerpt", "seo_title", "seo_description", "tags", "category", "content_html"],
  },
};

export interface GenerationResult {
  source: "blog_title_bank" | "fallback";
  post_id: string;
  slug: string;
  title: string;
  excerpt: string | null;
  url: string;
  content_html: string;
  topic_rationale: string | null;
  remaining_pending: number;
  ai_meta: Record<string, unknown>;
}

export interface BankStatus {
  pending: number;
  generating: number;
  published: number;
  failed: number;
  skipped: number;
  total: number;
  in_progress: Array<{ id: string; title: string; claimed_at: string | null }>;
}

export interface GenerateOptions {
  /** Overrides author_id; falls back to BLOG_GENERATION_AUTHOR_ID env, then NULL. */
  authorId?: string | null;
  /** Hint for the fallback generator when the bank is empty. */
  explicitTopic?: string;
  /** Bypass the title bank and go straight to fallback. */
  skipBank?: boolean;
}

export interface ClaimResult {
  config: Record<string, unknown>;
  row: TitleBankRow | null;  // null = fallback path
}

export interface TitleBankRow {
  id: string;
  title: string;
  primary_keyword: string;
  secondary_keywords: string[];
  cluster: string | null;
  intent_stage: string | null;
  format_hint: string | null;
  target_word_count: number;
  outline: unknown;
  internal_link_slugs: string[];
  e_e_a_t_notes: string | null;
  requires_medical_review: boolean;
  priority: number;
}

interface GeneratedArticle {
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

// =============================================================================
// Public entry points
// =============================================================================

/**
 * Fast phase — load config and claim the next row (or resolve to fallback).
 * Safe to run in the HTTP request/response path; completes in ~50–150 ms.
 */
export async function claimNext(opts: GenerateOptions = {}): Promise<ClaimResult> {
  const config = await loadConfig();

  if (opts.skipBank) {
    return { config, row: null };
  }

  const { data: claimedRaw, error: claimErr } = await supabaseAdmin.rpc("claim_next_blog_title");
  if (claimErr) {
    logError("claim_next_blog_title RPC failed", claimErr, {});
    throw new Error(`Failed to claim next title: ${claimErr.message}`);
  }

  const row = (claimedRaw as TitleBankRow | null) ?? null;
  if (!row || !row.id) {
    logInfo("blog_title_bank empty — will use cluster-bank fallback on finish");
    return { config, row: null };
  }
  return { config, row };
}

/**
 * Slow phase — calls the AI and publishes the article. Safe to run as a
 * fire-and-forget background task after claimNext() has returned; bank row
 * state is updated to 'published' on success or 'failed' on error.
 */
export async function finishGeneration(claim: ClaimResult, opts: GenerateOptions = {}): Promise<GenerationResult> {
  return claim.row
    ? generateFromBankRow(claim.row, claim.config, opts)
    : generateFromFallback(claim.config, opts);
}

/**
 * Sync end-to-end generator — used by the Make.com webhook where a single
 * response carries the full result. Not used by the admin UI, which uses
 * claimNext + finishGeneration to return fast and poll for completion.
 */
export async function generateAndPublishNext(opts: GenerateOptions = {}): Promise<GenerationResult> {
  const claim = await claimNext(opts);
  return finishGeneration(claim, opts);
}

export async function getBankStatus(): Promise<BankStatus> {
  const { data, error } = await supabaseAdmin
    .from("blog_title_bank")
    .select("id, title, status, claimed_at");
  if (error) {
    throw new Error(error.message);
  }
  const counts: BankStatus = {
    pending: 0, generating: 0, published: 0, failed: 0, skipped: 0, total: 0,
    in_progress: [],
  };
  for (const row of data ?? []) {
    const r = row as { id: string; title: string; status: string; claimed_at: string | null };
    const s = r.status as keyof BankStatus;
    if (s === "pending" || s === "generating" || s === "published" || s === "failed" || s === "skipped") {
      (counts[s] as number)++;
    }
    counts.total++;
    if (r.status === "generating") {
      counts.in_progress.push({ id: r.id, title: r.title, claimed_at: r.claimed_at });
    }
  }
  // Newest claim first
  counts.in_progress.sort((a, b) => (b.claimed_at ?? "").localeCompare(a.claimed_at ?? ""));
  return counts;
}

// =============================================================================
// Internals
// =============================================================================

async function loadConfig(): Promise<Record<string, unknown>> {
  const { data, error } = await supabaseAdmin
    .from("blog_generation_config")
    .select("config")
    .eq("id", 1)
    .maybeSingle();
  if (error || !data?.config) {
    throw new Error("Generation config not found. Run migration 00024.");
  }
  return data.config as Record<string, unknown>;
}

async function generateFromBankRow(
  row: TitleBankRow,
  config: Record<string, unknown>,
  opts: GenerateOptions,
): Promise<GenerationResult> {
  try {
    const systemPrompt = buildSystemPrompt(config, /* fallback= */ false);
    const userPrompt = buildUserPromptForBankRow(row);

    const result = await aiGenerate({
      system: systemPrompt,
      messages: [{ role: "user", content: userPrompt }],
      maxTokens: 8000,
      cacheSystem: true,
      timeoutMs: 180_000,  // 3 min — blog generations can take 60–120s
      maxRetries: 0,       // don't stack long timeouts; fail fast for user retry
      tools: [PUBLISH_BLOG_POST_TOOL],
      toolChoice: { type: "tool", name: "publish_blog_post" },
    });

    const article = extractJson<GeneratedArticle>(result.text);
    validateArticle(article);

    const ai_meta = {
      source: "blog_title_bank",
      title_bank_id: row.id,
      cluster: row.cluster,
      intent_stage: row.intent_stage,
      requires_medical_review: row.requires_medical_review,
      provider: result.provider,
      model: result.model,
      input_tokens: result.inputTokens,
      output_tokens: result.outputTokens,
      cache_creation_tokens: result.cacheCreationTokens,
      cache_read_tokens: result.cacheReadTokens,
      generated_at: new Date().toISOString(),
    };

    const post = await publishArticle(article, ai_meta, row.primary_keyword, opts.authorId);

    const { error: updErr } = await supabaseAdmin
      .from("blog_title_bank")
      .update({ status: "published", published_post_id: post.id })
      .eq("id", row.id);
    if (updErr) logError("failed to mark blog_title_bank row published", updErr, { row_id: row.id });

    const remaining = await countPending();
    logInfo("blog generator: published from bank", {
      row_id: row.id, post_id: post.id, slug: post.slug, remaining_pending: remaining,
    });

    return {
      source: "blog_title_bank",
      post_id: post.id,
      slug: post.slug,
      title: post.title,
      excerpt: post.excerpt,
      url: buildUrl(post.slug),
      content_html: post.content_html,
      topic_rationale: null,
      remaining_pending: remaining,
      ai_meta,
    };
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    await supabaseAdmin
      .from("blog_title_bank")
      .update({ status: "failed", last_error: message.slice(0, 1000) })
      .eq("id", row.id);
    throw err;
  }
}

async function generateFromFallback(
  config: Record<string, unknown>,
  opts: GenerateOptions,
): Promise<GenerationResult> {
  const publishedTitles = await fetchPublishedTitles();
  const systemPrompt = buildSystemPrompt(config, /* fallback= */ true);
  const userPrompt = buildFallbackUserPrompt(config, publishedTitles, opts.explicitTopic);

  const result = await aiGenerate({
    system: systemPrompt,
    messages: [{ role: "user", content: userPrompt }],
    maxTokens: 8000,
    cacheSystem: true,
  });

  const article = extractJson<GeneratedArticle>(result.text);
  validateArticle(article);

  const ai_meta = {
    source: "fallback",
    topic_rationale: article.topic_rationale ?? null,
    provider: result.provider,
    model: result.model,
    input_tokens: result.inputTokens,
    output_tokens: result.outputTokens,
    cache_creation_tokens: result.cacheCreationTokens,
    cache_read_tokens: result.cacheReadTokens,
    generated_at: new Date().toISOString(),
  };

  const post = await publishArticle(article, ai_meta, article.primary_keyword ?? null, opts.authorId);
  logInfo("blog generator: published from fallback", {
    post_id: post.id, slug: post.slug, topic_rationale: article.topic_rationale,
  });

  return {
    source: "fallback",
    post_id: post.id,
    slug: post.slug,
    title: post.title,
    excerpt: post.excerpt,
    url: buildUrl(post.slug),
    content_html: post.content_html,
    topic_rationale: article.topic_rationale ?? null,
    remaining_pending: 0,
    ai_meta,
  };
}

// =============================================================================
// Prompt builders
// =============================================================================

function buildSystemPrompt(config: Record<string, unknown>, fallback: boolean): string {
  const brand = (config.brand ?? {}) as Record<string, unknown>;
  const voice = (config.voice ?? {}) as Record<string, unknown>;
  const html = (config.html_rules ?? {}) as Record<string, unknown>;
  const eeat = (config.e_e_a_t ?? {}) as Record<string, unknown>;
  const seo = (config.seo ?? {}) as Record<string, unknown>;
  const output = (config.output_contract ?? {}) as Record<string, unknown>;
  const conversion = (config.conversion ?? {}) as Record<string, unknown>;

  const parts: string[] = [];

  parts.push(
    `You are the senior content strategist and editor for ${brand.name ?? "Daily OK"}. Write a complete, publish-ready blog post that reinforces the brand's pillar narrative: "${brand.tagline ?? "Presence without surveillance."}"`,
  );

  parts.push(`Brand positioning: ${brand.positioning ?? ""}`);
  if (brand.pricing) parts.push(`Pricing: ${brand.pricing}`);
  if (Array.isArray(brand.audiences)) parts.push(`Primary audiences: ${(brand.audiences as string[]).join(" • ")}`);

  if (Array.isArray(voice.tone)) parts.push(`Tone: ${(voice.tone as string[]).join(", ")}.`);
  if (voice.must_reinforce_pillar) parts.push(`Pillar rule: ${voice.must_reinforce_pillar}`);
  if (Array.isArray(voice.avoid)) parts.push(`AVOID: ${(voice.avoid as string[]).join(" | ")}`);
  if (Array.isArray(voice.never_claim)) parts.push(`NEVER CLAIM: ${(voice.never_claim as string[]).join(" | ")}`);

  parts.push(
    `HTML rules:\n- Allowed tags only: ${Array.isArray(html.allowed_tags) ? (html.allowed_tags as string[]).join(", ") : ""}\n- ${Array.isArray(html.structure) ? (html.structure as string[]).join("\n- ") : ""}\n- ${html.no_markdown ?? "No markdown, no code fences, no <h1>."}\n- Medical disclaimer rule: ${html.medical_disclaimer ?? ""}`,
  );

  const linking = (html.linking ?? {}) as Record<string, unknown>;
  const conventions = (linking.internal_conventions ?? {}) as Record<string, string>;
  const conventionsLine = Object.entries(conventions).map(([k, v]) => `${k} → ${v}`).join(", ");
  if (conventionsLine) parts.push(`Internal link conventions: ${conventionsLine}.`);
  if (Array.isArray(linking.rules)) parts.push(`Linking rules: ${(linking.rules as string[]).join(" | ")}`);

  if (eeat.default_byline) parts.push(`Default byline: ${eeat.default_byline}.`);
  if (eeat.no_fabrication) parts.push(`Integrity: ${eeat.no_fabrication}`);

  // Only emit a reviewer line when a real, verified reviewer has been
  // contracted and their details populated in config. Until then, no line.
  const reviewer = (eeat.verified_reviewer ?? null) as {
    name?: string;
    credential?: string;
    reviewed_at?: string;
  } | null;
  if (reviewer && reviewer.name && reviewer.credential) {
    const dateStr = reviewer.reviewed_at ? ` on ${reviewer.reviewed_at}` : "";
    parts.push(
      `Verified reviewer: if the article is YMYL, append this line at the very end:\n<p><em>Medically reviewed by ${reviewer.name}, ${reviewer.credential}${dateStr}.</em></p>`,
    );
  }

  // Integrity rules are rendered as a dedicated block so the model reads
  // them as hard constraints rather than stylistic suggestions.
  if (Array.isArray(eeat.integrity_rules) && (eeat.integrity_rules as unknown[]).length > 0) {
    parts.push(
      `INTEGRITY RULES (absolute — violations will be caught by the editor and rejected):\n- ${(eeat.integrity_rules as string[]).join("\n- ")}`,
    );
  }

  parts.push(
    `SEO constraints: title ≤ ${seo.title_max_chars ?? 70} chars, seo_title ≤ ${seo.seo_title_max_chars ?? 60}, excerpt ${seo.excerpt_chars ?? "140–180"}, seo_description ${seo.seo_description_chars ?? "140–160"}, slug kebab-case, ${seo.tags_count ?? "3–6"} tags, category ∈ {${Array.isArray(seo.category_enum) ? (seo.category_enum as string[]).join(", ") : ""}}.`,
  );

  // Conversion guidance — drives the reader toward app download without sacrificing help
  if (conversion && Object.keys(conversion).length > 0) {
    const convParts: string[] = ["CONVERSION GUIDANCE:"];
    if (conversion.goal) convParts.push(`Goal: ${conversion.goal}`);

    const links = (conversion.download_links ?? {}) as Record<string, string>;
    if (Object.keys(links).length) {
      const linksLine = Object.entries(links).map(([k, v]) => `${k}=${v}`).join(" | ");
      convParts.push(`Available links: ${linksLine}. Use /pricing for commercial context; App Store / Play Store URLs only in the closing CTA when the reader is ready to install.`);
    }

    const placement = (conversion.cta_placement ?? {}) as Record<string, unknown>;
    if (placement.opening_rule) convParts.push(`Opening rule: ${placement.opening_rule}`);
    if (Array.isArray(placement.rules)) {
      convParts.push(`CTA placement rules:\n- ${(placement.rules as string[]).join("\n- ")}`);
    }
    if (Array.isArray(placement.closing_template_examples)) {
      convParts.push(`Closing CTA templates (use as inspiration, do not copy verbatim):\n${(placement.closing_template_examples as string[]).map((s, i) => `[${i + 1}] ${s}`).join("\n")}`);
    }

    const props = (conversion.value_props_by_audience ?? {}) as Record<string, string[]>;
    if (Object.keys(props).length) {
      const propsLines = Object.entries(props).map(([aud, list]) => `  ${aud}: ${list.join(" • ")}`).join("\n");
      convParts.push(`Value props (match the closest audience to this article):\n${propsLines}`);
    }

    const objections = (conversion.objection_handlers ?? {}) as Record<string, string>;
    if (Object.keys(objections).length) {
      const objLines = Object.entries(objections).map(([k, v]) => `  ${k}: ${v}`).join("\n");
      convParts.push(`Objection handlers (weave in only when the article raises the objection):\n${objLines}`);
    }

    const proof = (conversion.social_proof_rules ?? {}) as Record<string, unknown>;
    if (proof.honest_only) convParts.push(`Social proof — honesty rule: ${proof.honest_only}`);
    if (Array.isArray(proof.forbidden)) convParts.push(`Social proof — forbidden: ${(proof.forbidden as string[]).join(" | ")}`);

    if (Array.isArray(conversion.never_claim)) {
      convParts.push(`Never claim: ${(conversion.never_claim as string[]).join(" | ")}`);
    }

    if (Array.isArray(conversion.download_readiness_signals)) {
      convParts.push(`Strong moments to place a CTA near: ${(conversion.download_readiness_signals as string[]).join(" | ")}`);
    }

    if (Array.isArray(conversion.dont_do)) {
      convParts.push(`DO NOT:\n- ${(conversion.dont_do as string[]).join("\n- ")}`);
    }

    parts.push(convParts.join("\n\n"));
  }

  const shape = (output.shape ?? {}) as Record<string, string>;
  const shapeLines = Object.entries(shape).map(([k, v]) => `  "${k}": ${JSON.stringify(v)}`).join(",\n");
  parts.push(
    `Output contract: ${output.format ?? "Return ONLY a JSON object."}\n\nRespond with ONLY this JSON shape:\n{\n${shapeLines}${fallback ? `,\n  "primary_keyword": "the keyword you chose",\n  "topic_rationale": "one sentence explaining which cluster and why this title doesn't duplicate what's already published"` : ""}\n}`,
  );

  return parts.filter(Boolean).join("\n\n");
}

function buildUserPromptForBankRow(row: TitleBankRow): string {
  const lines: string[] = [];
  lines.push(`Write the full blog post for the title below. Stay on the exact title unless a small edit makes it more compelling.`);
  lines.push("");
  lines.push(`Title: ${row.title}`);
  lines.push(`Primary keyword: ${row.primary_keyword}`);
  if (row.secondary_keywords.length) lines.push(`Secondary keywords: ${row.secondary_keywords.join(", ")}`);
  if (row.intent_stage) lines.push(`Intent stage: ${row.intent_stage}`);
  if (row.format_hint) lines.push(`Format: ${row.format_hint}`);
  lines.push(`Target word count: ~${row.target_word_count} words (minimum 900).`);
  if (row.cluster) lines.push(`Cluster: ${row.cluster}`);
  if (row.e_e_a_t_notes) lines.push(`Editor notes: ${row.e_e_a_t_notes}`);
  if (row.requires_medical_review) {
    lines.push(`YMYL: yes — include the medical disclaimer paragraph near the top and keep the tone calm and source-backed.`);
  }
  if (row.internal_link_slugs.length) {
    lines.push(`Suggested internal link anchors: ${row.internal_link_slugs.join(", ")} (use the conventions from the system prompt).`);
  }
  if (row.outline) {
    lines.push(`Outline hint (JSON): ${JSON.stringify(row.outline)}`);
  }
  lines.push("");
  lines.push(`Weave the primary keyword naturally into the title, the opening TL;DR blockquote, one H2, and the first paragraph. Do not keyword-stuff.`);
  lines.push(`Return ONLY the JSON object. No prose outside it.`);
  return lines.join("\n");
}

function buildFallbackUserPrompt(
  config: Record<string, unknown>,
  publishedTitles: string[],
  explicitTopic: string | undefined,
): string {
  const fallback = (config.fallback ?? {}) as Record<string, unknown>;
  const lines: string[] = [];

  if (explicitTopic) {
    lines.push(`The editor has requested this topic: "${explicitTopic}". Use it only if it doesn't overlap with already_published_titles below. If it does, pick the closest non-competing angle and note the swap in topic_rationale.`);
  } else {
    lines.push(`The curated title queue is empty. Pick ONE fresh blog topic from the cluster_bank below and write a complete article.`);
  }

  lines.push("");
  lines.push(`Instruction: ${fallback.instruction ?? ""}`);
  lines.push(`Duplication policy: ${fallback.duplication_policy ?? ""}`);
  lines.push("");

  lines.push(`cluster_bank:\n${JSON.stringify(fallback.cluster_bank ?? [], null, 2)}`);
  lines.push("");

  const titleList = publishedTitles.length
    ? publishedTitles.map((t) => `- ${t}`).join("\n")
    : "(none yet)";
  lines.push(`already_published_titles:\n${titleList}`);
  lines.push("");

  lines.push(`Return ONLY the JSON object (with the additional primary_keyword and topic_rationale fields). Target 1,400–2,000 words. Same voice, same HTML rules.`);
  return lines.join("\n");
}

// =============================================================================
// Persistence
// =============================================================================

async function publishArticle(
  article: GeneratedArticle,
  ai_meta: Record<string, unknown>,
  primaryKeyword: string | null,
  authorIdOverride?: string | null,
): Promise<{ id: string; slug: string; title: string; excerpt: string | null; content_html: string }> {
  const slug = await uniqueSlug(article.slug || slugify(article.title));
  const authorId = authorIdOverride ?? Deno.env.get("BLOG_GENERATION_AUTHOR_ID") ?? null;

  const payload = {
    slug,
    title: article.title,
    excerpt: article.excerpt ?? null,
    content_html: article.content_html,
    status: "published" as const,
    published_at: new Date().toISOString(),
    author_id: authorId,
    seo_title: article.seo_title ?? null,
    seo_description: article.seo_description ?? null,
    tags: Array.isArray(article.tags) ? article.tags : [],
    category: article.category ?? null,
    ai_generated: true,
    ai_meta: { ...ai_meta, primary_keyword: primaryKeyword },
  };

  const { data, error } = await supabaseAdmin
    .from("blog_posts")
    .insert(payload)
    .select("id, slug, title, excerpt, content_html")
    .single();

  if (error || !data) {
    throw new Error(`Failed to insert blog_posts row: ${error?.message ?? "unknown"}`);
  }
  return data;
}

async function uniqueSlug(base: string): Promise<string> {
  const clean = base && base.length > 0 ? base : `post-${Date.now()}`;
  let candidate = clean.slice(0, 80);
  for (let n = 1; n <= 100; n++) {
    const { data } = await supabaseAdmin
      .from("blog_posts")
      .select("id")
      .eq("slug", candidate)
      .limit(1);
    if (!data || data.length === 0) return candidate;
    candidate = `${clean.slice(0, 72)}-${n + 1}`;
  }
  return `${clean.slice(0, 60)}-${Date.now()}`;
}

function slugify(input: string): string {
  return input
    .toLowerCase()
    .normalize("NFKD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 80);
}

async function fetchPublishedTitles(): Promise<string[]> {
  const { data } = await supabaseAdmin
    .from("blog_posts")
    .select("title")
    .eq("status", "published")
    .order("published_at", { ascending: false })
    .limit(200);
  return (data ?? []).map((r) => r.title as string);
}

async function countPending(): Promise<number> {
  const { count } = await supabaseAdmin
    .from("blog_title_bank")
    .select("id", { count: "exact", head: true })
    .eq("status", "pending");
  return count ?? 0;
}

function buildUrl(slug: string): string {
  const origin = Deno.env.get("SITE_ORIGIN") || "https://dailyok.net";
  return `${origin}/blog/${slug}`;
}

function validateArticle(a: GeneratedArticle): void {
  if (!a || typeof a !== "object") throw new Error("AI response is not an object");
  if (typeof a.title !== "string" || a.title.length === 0) throw new Error("Article missing title");
  if (typeof a.content_html !== "string" || a.content_html.length < 400) {
    throw new Error(`content_html too short (${a.content_html?.length ?? 0} chars)`);
  }
  if (/<(h1|script|iframe|style)\b/i.test(a.content_html)) {
    throw new Error("content_html contains disallowed tag");
  }
  if (!Array.isArray(a.tags)) a.tags = [];
}
