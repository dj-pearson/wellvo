/**
 * /generate-next-article — Make.com-invoked blog generator.
 *
 * Flow:
 *   1. Claim the next pending row from blog_title_bank via the atomic
 *      claim_next_blog_title() RPC (FOR UPDATE SKIP LOCKED).
 *   2. If a row was claimed, build a prompt from the row's title + keywords
 *      + outline, call the shared AI client, and publish the result to
 *      blog_posts with status='published'. Mark the bank row published.
 *   3. If the bank is empty, fall back to the generation config's cluster
 *      bank + the list of already-published titles — AI picks a new,
 *      non-competing topic and writes a complete article.
 *
 * Auth: bypasses the JWT flow. server.ts validates X-Webhook-Secret against
 * the BLOG_GENERATION_WEBHOOK_SECRET env var before routing to this handler.
 *
 * Config: reads blog_generation_config (single row, id=1) for brand voice,
 * HTML rules, output contract, and fallback strategy. AI provider + model
 * come from the shared Coolify variables consumed by shared/ai.ts.
 *
 * Optional env:
 *   BLOG_GENERATION_AUTHOR_ID   UUID of a user to attribute posts to (NULL ok)
 *   SITE_ORIGIN                 public site origin (default https://dailyok.net)
 */

import { supabaseAdmin } from "../../shared/supabase.ts";
import { aiGenerate, extractJson, AiError } from "../../shared/ai.ts";
import { logInfo, logError } from "../../shared/logger.ts";
import type { AuthResult } from "../../shared/auth.ts";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

interface TitleBankRow {
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
  topic_rationale?: string;  // only present in fallback mode
  primary_keyword?: string;  // only expected in fallback mode
}

interface RequestBody {
  topic?: string;          // optional explicit topic override
  skip_bank?: boolean;     // if true, bypass bank and go straight to fallback
}

export async function handleGenerateNextArticle(_req: Request, _auth: AuthResult): Promise<Response> {
  let body: RequestBody = {};
  try {
    body = await _req.json();
  } catch {
    body = {};
  }

  // Load generation config once per run
  const { data: configRow, error: configErr } = await supabaseAdmin
    .from("blog_generation_config")
    .select("config")
    .eq("id", 1)
    .maybeSingle();

  if (configErr || !configRow?.config) {
    logError("generate-next-article: missing blog_generation_config", configErr, {});
    return json({ error: "Generation config not found. Run migration 00024." }, 500);
  }

  const config = configRow.config as Record<string, unknown>;

  try {
    if (body.skip_bank) {
      return await generateFromFallback(config, body.topic);
    }

    const { data: claimedRaw, error: claimErr } = await supabaseAdmin.rpc("claim_next_blog_title");
    if (claimErr) {
      logError("claim_next_blog_title RPC failed", claimErr, {});
      return json({ error: "Failed to claim next title", details: claimErr.message }, 500);
    }

    const claimed = claimedRaw as TitleBankRow | null;

    if (!claimed || !claimed.id) {
      logInfo("blog_title_bank empty — falling back to cluster-bank generation");
      return await generateFromFallback(config, body.topic);
    }

    return await generateFromBankRow(claimed, config);
  } catch (err) {
    if (err instanceof AiError) {
      return json({ error: err.message }, err.status && err.status >= 400 && err.status < 600 ? err.status : 502);
    }
    logError("generate-next-article unhandled error", err, {});
    return json({ error: "Generation failed", details: err instanceof Error ? err.message : String(err) }, 500);
  }
}

/**
 * Generate an article for a claimed bank row, publish it, and close out the row.
 * Failures mark the row as 'failed' so it can be retried or inspected.
 */
async function generateFromBankRow(row: TitleBankRow, config: Record<string, unknown>): Promise<Response> {
  try {
    const systemPrompt = buildSystemPrompt(config, /* fallback= */ false);
    const userPrompt = buildUserPromptForBankRow(row);

    const result = await aiGenerate({
      system: systemPrompt,
      messages: [{ role: "user", content: userPrompt }],
      maxTokens: 8000,
      cacheSystem: true,
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

    const post = await publishArticle(article, ai_meta, row.primary_keyword);

    const { error: updErr } = await supabaseAdmin
      .from("blog_title_bank")
      .update({ status: "published", published_post_id: post.id })
      .eq("id", row.id);
    if (updErr) logError("failed to mark blog_title_bank row published", updErr, { row_id: row.id });

    const remaining = await countPending();
    const siteOrigin = Deno.env.get("SITE_ORIGIN") || "https://dailyok.net";

    logInfo("generate-next-article published from bank", {
      row_id: row.id,
      post_id: post.id,
      slug: post.slug,
      remaining_pending: remaining,
    });

    return json({
      source: "blog_title_bank",
      post_id: post.id,
      slug: post.slug,
      title: post.title,
      excerpt: post.excerpt,
      url: `${siteOrigin}/blog/${post.slug}`,
      content_html: post.content_html,
      remaining_pending: remaining,
      ai_meta,
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    await supabaseAdmin
      .from("blog_title_bank")
      .update({ status: "failed", last_error: message.slice(0, 1000) })
      .eq("id", row.id);
    throw err;
  }
}

/**
 * Fallback: no pending rows, so ask the AI to pick a fresh, non-competing
 * topic from the configured cluster bank. Published just like a bank row.
 */
async function generateFromFallback(config: Record<string, unknown>, explicitTopic?: string): Promise<Response> {
  const publishedTitles = await fetchPublishedTitles();
  const systemPrompt = buildSystemPrompt(config, /* fallback= */ true);
  const userPrompt = buildFallbackUserPrompt(config, publishedTitles, explicitTopic);

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

  const post = await publishArticle(article, ai_meta, article.primary_keyword ?? null);
  const siteOrigin = Deno.env.get("SITE_ORIGIN") || "https://dailyok.net";

  logInfo("generate-next-article published from fallback", {
    post_id: post.id,
    slug: post.slug,
    topic_rationale: article.topic_rationale,
  });

  return json({
    source: "fallback",
    post_id: post.id,
    slug: post.slug,
    title: post.title,
    excerpt: post.excerpt,
    url: `${siteOrigin}/blog/${post.slug}`,
    content_html: post.content_html,
    topic_rationale: article.topic_rationale ?? null,
    remaining_pending: 0,
    ai_meta,
  });
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
  if (eeat.reviewer_line_when_ymyl) parts.push(`When YMYL, add to the end: ${eeat.reviewer_line_when_ymyl}`);
  if (eeat.no_fabrication) parts.push(`Integrity: ${eeat.no_fabrication}`);

  parts.push(
    `SEO constraints: title ≤ ${seo.title_max_chars ?? 70} chars, seo_title ≤ ${seo.seo_title_max_chars ?? 60}, excerpt ${seo.excerpt_chars ?? "140–180"}, seo_description ${seo.seo_description_chars ?? "140–160"}, slug kebab-case, ${seo.tags_count ?? "3–6"} tags, category ∈ {${Array.isArray(seo.category_enum) ? (seo.category_enum as string[]).join(", ") : ""}}.`,
  );

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

function buildFallbackUserPrompt(config: Record<string, unknown>, publishedTitles: string[], explicitTopic: string | undefined): string {
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
): Promise<{ id: string; slug: string; title: string; excerpt: string | null; content_html: string }> {
  const slug = await uniqueSlug(article.slug || slugify(article.title));
  const authorId = Deno.env.get("BLOG_GENERATION_AUTHOR_ID") || null;

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

// =============================================================================
// Validation
// =============================================================================

function validateArticle(a: GeneratedArticle): void {
  if (!a || typeof a !== "object") throw new Error("AI response is not an object");
  if (typeof a.title !== "string" || a.title.length === 0) throw new Error("Article missing title");
  if (typeof a.content_html !== "string" || a.content_html.length < 400) {
    throw new Error(`content_html too short (${a.content_html?.length ?? 0} chars)`);
  }
  // Disallow <h1> and <script> defensively — the system prompt forbids them,
  // but users of the public Blog.tsx view render content_html directly.
  if (/<(h1|script|iframe|style)\b/i.test(a.content_html)) {
    throw new Error("content_html contains disallowed tag");
  }
  if (!Array.isArray(a.tags)) a.tags = [];
}
