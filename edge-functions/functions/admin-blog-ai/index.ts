import { requireSystemAdmin, logAdminAction } from "../../shared/admin-auth.ts";
import { aiGenerate, renderTemplate, extractJson, AiError } from "../../shared/ai.ts";
import { supabaseAdmin } from "../../shared/supabase.ts";
import { generateAndPublishNext, getBankStatus } from "../../shared/blog-generator.ts";
import type { AuthResult } from "../../shared/auth.ts";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

/**
 * Article generation prompt: produces a structured JSON response with title,
 * slug, excerpt, HTML body, SEO meta, and tags. HTML uses a small, semantic
 * subset that TipTap can round-trip.
 */
const ARTICLE_SYSTEM_PROMPT = `You are a senior content strategist and SEO writer for Daily OK, a family daily check-in app that helps caregivers monitor loved ones.

Audience: caregivers, adult children of elderly parents, parents of teens, and safety-conscious families.
Tone: warm, reassuring, practical, never alarmist. Prefer concrete examples over abstractions. Avoid medical advice disclaimers unless the topic requires it.

When asked to write an article, respond with ONLY a JSON object in this exact shape:

{
  "title": "string — under 70 chars, compelling, specific",
  "slug": "kebab-case-string — under 80 chars, matches title",
  "excerpt": "string — 140–180 chars, written to earn the click",
  "seo_title": "string — under 60 chars, keyword-forward",
  "seo_description": "string — 140–160 chars, answers the search intent",
  "tags": ["3–6 lowercase tags"],
  "category": "string — one of: caregiving, elderly-care, child-safety, product, how-to, guides",
  "content_html": "string — HTML using only these tags: <h2>, <h3>, <p>, <ul>, <ol>, <li>, <strong>, <em>, <a href>, <blockquote>. 700–1500 words. Open with a hook, use subheads every 150–250 words, end with a practical checklist or next-step CTA."
}

Do not include markdown. Do not wrap in code fences. Output only the JSON object.`;

const IMPROVE_SYSTEM_PROMPT = `You improve short passages of marketing copy for Daily OK (a family check-in app) while keeping the original meaning. Return only the improved passage — no preamble.`;

const SEO_META_SYSTEM_PROMPT = `You generate SEO metadata for a blog post. Respond with ONLY a JSON object:
{
  "seo_title": "under 60 chars, keyword-forward",
  "seo_description": "140–160 chars, active voice, answers the search intent"
}`;

interface Body {
  action:
    | "generate_article"
    | "generate_from_template"
    | "batch_generate"
    | "improve_text"
    | "generate_seo_meta"
    | "generate_next_from_bank"
    | "bank_status";

  // generate_article
  prompt?: string;
  keyword?: string;

  // generate_from_template / batch_generate
  template_id?: string;
  variables?: Record<string, string>;
  batch?: Array<Record<string, string>>;  // for batch_generate
  save_as_draft?: boolean;                // if true, persist to blog_posts

  // improve_text / generate_seo_meta
  text?: string;
  instruction?: string;
  title?: string;

  // generate_next_from_bank
  topic?: string;
  skip_bank?: boolean;
}

export async function handleAdminBlogAi(req: Request, auth: AuthResult): Promise<Response> {
  const admin = await requireSystemAdmin(auth);
  if (!admin.ok) return admin.response;

  const body: Body = await req.json().catch(() => ({ action: "generate_article" }));

  try {
    switch (body.action) {
      case "generate_article":
        return await generateArticle(body, admin.userId, req);
      case "generate_from_template":
        return await generateFromTemplate(body, admin.userId, req);
      case "batch_generate":
        return await batchGenerate(body, admin.userId, req);
      case "improve_text":
        return await improveText(body);
      case "generate_seo_meta":
        return await generateSeoMeta(body);
      case "generate_next_from_bank":
        return await generateNextFromBank(body, admin.userId, req);
      case "bank_status":
        return await bankStatus();
      default:
        return json({ error: "Unknown action" }, 400);
    }
  } catch (err) {
    if (err instanceof AiError) {
      return json({ error: err.message }, err.status && err.status >= 400 && err.status < 600 ? err.status : 502);
    }
    return json({ error: "AI request failed", details: err instanceof Error ? err.message : String(err) }, 500);
  }
}

async function generateArticle(body: Body, adminId: string, req: Request): Promise<Response> {
  const userPrompt = body.prompt?.trim();
  const keyword = body.keyword?.trim();
  if (!userPrompt && !keyword) return json({ error: "prompt or keyword required" }, 400);

  const instruction = userPrompt
    ? userPrompt
    : `Write an article targeting the search query: "${keyword}". Be specific and action-oriented.`;

  const result = await aiGenerate({
    system: ARTICLE_SYSTEM_PROMPT,
    messages: [{ role: "user", content: instruction }],
    maxTokens: 4096,
    cacheSystem: true,
  });

  const article = extractJson<Record<string, unknown>>(result.text);

  await logAdminAction(adminId, "blog.ai_generate", {
    metadata: {
      provider: result.provider,
      model: result.model,
      input_tokens: result.inputTokens,
      output_tokens: result.outputTokens,
      cache_read: result.cacheReadTokens,
    },
    req,
  });

  const ai_meta = {
    provider: result.provider,
    model: result.model,
    prompt: instruction,
    input_tokens: result.inputTokens,
    output_tokens: result.outputTokens,
    cache_creation_tokens: result.cacheCreationTokens,
    cache_read_tokens: result.cacheReadTokens,
    generated_at: new Date().toISOString(),
  };

  return json({ article, ai_meta });
}

async function generateFromTemplate(body: Body, adminId: string, req: Request): Promise<Response> {
  if (!body.template_id) return json({ error: "template_id required" }, 400);
  if (!body.variables) return json({ error: "variables required" }, 400);

  const { data: template, error } = await supabaseAdmin
    .from("blog_templates")
    .select("*")
    .eq("id", body.template_id)
    .maybeSingle();

  if (error) return json({ error: error.message }, 500);
  if (!template) return json({ error: "Template not found" }, 404);

  const userPrompt = renderTemplate(template.user_prompt_template, body.variables);

  const result = await aiGenerate({
    system: template.system_prompt,
    messages: [{ role: "user", content: userPrompt }],
    maxTokens: 4096,
    cacheSystem: true,
  });

  const article = extractJson<Record<string, unknown>>(result.text);

  // Apply template overrides for slug/title if present
  if (template.slug_template && !article.slug) {
    article.slug = renderTemplate(template.slug_template, body.variables);
  }
  if (template.title_template && !article.title) {
    article.title = renderTemplate(template.title_template, body.variables);
  }
  if (template.default_tags?.length && (!Array.isArray(article.tags) || article.tags.length === 0)) {
    article.tags = template.default_tags;
  }
  if (template.default_category && !article.category) {
    article.category = template.default_category;
  }

  const ai_meta = {
    provider: result.provider,
    model: result.model,
    template_id: template.id,
    template_name: template.name,
    variables: body.variables,
    input_tokens: result.inputTokens,
    output_tokens: result.outputTokens,
    cache_read_tokens: result.cacheReadTokens,
    generated_at: new Date().toISOString(),
  };

  await logAdminAction(adminId, "blog.ai_template_generate", {
    metadata: { template_id: template.id, ...body.variables },
    req,
  });

  if (body.save_as_draft) {
    const saved = await saveArticleAsDraft(article, ai_meta, adminId);
    return json({ article, ai_meta, post: saved });
  }

  return json({ article, ai_meta });
}

async function batchGenerate(body: Body, adminId: string, req: Request): Promise<Response> {
  if (!body.template_id) return json({ error: "template_id required" }, 400);
  if (!Array.isArray(body.batch) || body.batch.length === 0) {
    return json({ error: "batch (non-empty array of variable sets) required" }, 400);
  }
  if (body.batch.length > 25) {
    return json({ error: "batch size limited to 25" }, 400);
  }

  const { data: template, error } = await supabaseAdmin
    .from("blog_templates")
    .select("*")
    .eq("id", body.template_id)
    .maybeSingle();
  if (error) return json({ error: error.message }, 500);
  if (!template) return json({ error: "Template not found" }, 404);

  const results: Array<{ variables: Record<string, string>; post_id?: string; slug?: string; error?: string }> = [];

  for (const vars of body.batch) {
    try {
      const userPrompt = renderTemplate(template.user_prompt_template, vars);
      const aiRes = await aiGenerate({
        system: template.system_prompt,
        messages: [{ role: "user", content: userPrompt }],
        maxTokens: 4096,
        cacheSystem: true,
      });
      const article = extractJson<Record<string, unknown>>(aiRes.text);

      if (template.slug_template && !article.slug) article.slug = renderTemplate(template.slug_template, vars);
      if (template.title_template && !article.title) article.title = renderTemplate(template.title_template, vars);
      if (template.default_tags?.length && (!Array.isArray(article.tags) || article.tags.length === 0)) {
        article.tags = template.default_tags;
      }
      if (template.default_category && !article.category) article.category = template.default_category;

      const ai_meta = {
        provider: aiRes.provider,
        model: aiRes.model,
        template_id: template.id,
        template_name: template.name,
        variables: vars,
        input_tokens: aiRes.inputTokens,
        output_tokens: aiRes.outputTokens,
        cache_read_tokens: aiRes.cacheReadTokens,
        generated_at: new Date().toISOString(),
      };

      const saved = await saveArticleAsDraft(article, ai_meta, adminId);
      results.push({ variables: vars, post_id: saved?.id, slug: saved?.slug });
    } catch (err) {
      results.push({ variables: vars, error: err instanceof Error ? err.message : String(err) });
    }
  }

  await logAdminAction(adminId, "blog.ai_batch_generate", {
    metadata: { template_id: template.id, batch_size: body.batch.length, succeeded: results.filter((r) => r.post_id).length },
    req,
  });

  return json({ results });
}

async function saveArticleAsDraft(
  article: Record<string, unknown>,
  ai_meta: Record<string, unknown>,
  adminId: string,
): Promise<{ id: string; slug: string } | null> {
  const title = typeof article.title === "string" ? article.title : "Untitled";
  const slugBase =
    typeof article.slug === "string" && article.slug
      ? article.slug
      : title.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 80);

  // Ensure unique slug
  let slug = slugBase;
  let n = 1;
  while (true) {
    const { data: existing } = await supabaseAdmin
      .from("blog_posts")
      .select("id")
      .eq("slug", slug)
      .limit(1);
    if (!existing || existing.length === 0) break;
    n += 1;
    slug = `${slugBase}-${n}`;
    if (n > 100) {
      slug = `${slugBase}-${Date.now()}`;
      break;
    }
  }

  const { data, error } = await supabaseAdmin
    .from("blog_posts")
    .insert({
      slug,
      title,
      excerpt: typeof article.excerpt === "string" ? article.excerpt : null,
      content_html: typeof article.content_html === "string" ? article.content_html : "",
      featured_image_url: null,
      status: "draft",
      author_id: adminId,
      seo_title: typeof article.seo_title === "string" ? article.seo_title : null,
      seo_description: typeof article.seo_description === "string" ? article.seo_description : null,
      tags: Array.isArray(article.tags) ? article.tags : [],
      category: typeof article.category === "string" ? article.category : null,
      ai_generated: true,
      ai_meta,
    })
    .select("id, slug")
    .single();

  if (error) return null;
  return data;
}

async function improveText(body: Body): Promise<Response> {
  if (!body.text) return json({ error: "text required" }, 400);
  const instruction = body.instruction?.trim() || "Improve this passage — tighter, clearer, more specific. Preserve meaning.";

  const result = await aiGenerate({
    system: IMPROVE_SYSTEM_PROMPT,
    messages: [{ role: "user", content: `${instruction}\n\n---\n${body.text}` }],
    maxTokens: 2048,
    modelSize: "lightweight",
  });

  return json({
    text: result.text.trim(),
    provider: result.provider,
    model: result.model,
  });
}

async function generateNextFromBank(body: Body, adminId: string, req: Request): Promise<Response> {
  const result = await generateAndPublishNext({
    authorId: adminId,
    explicitTopic: body.topic,
    skipBank: body.skip_bank === true,
  });

  await logAdminAction(adminId, "blog.generate_next_from_bank", {
    resourceType: "blog_post",
    resourceId: result.post_id,
    metadata: {
      source: result.source,
      slug: result.slug,
      remaining_pending: result.remaining_pending,
      ai_provider: (result.ai_meta as Record<string, unknown>).provider,
      ai_model: (result.ai_meta as Record<string, unknown>).model,
    },
    req,
  });

  return json(result);
}

async function bankStatus(): Promise<Response> {
  const status = await getBankStatus();
  return json(status);
}

async function generateSeoMeta(body: Body): Promise<Response> {
  if (!body.title && !body.text) return json({ error: "title or text required" }, 400);

  const prompt = [
    body.title ? `Title: ${body.title}` : null,
    body.text ? `Content:\n${body.text.slice(0, 4000)}` : null,
  ]
    .filter(Boolean)
    .join("\n\n");

  const result = await aiGenerate({
    system: SEO_META_SYSTEM_PROMPT,
    messages: [{ role: "user", content: prompt }],
    maxTokens: 500,
    modelSize: "lightweight",
    json: true,
  });

  const meta = extractJson<{ seo_title: string; seo_description: string }>(result.text);
  return json({ ...meta, provider: result.provider, model: result.model });
}
