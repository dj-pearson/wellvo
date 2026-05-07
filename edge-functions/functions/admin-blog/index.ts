import { supabaseAdmin } from "../../shared/supabase.ts";
import { requireSystemAdmin, logAdminAction } from "../../shared/admin-auth.ts";
import { scoreBlogPost, type ScoreableBlogPost } from "../../shared/seo-scorer.ts";
import { runPrePublishQA, type QaInputPost, type QaResult } from "../../shared/blog-qa.ts";
import {
  generateSyndication, SUPPORTED_PLATFORMS,
  type SyndicationPlatform, type SyndicationSourcePost,
} from "../../shared/blog-syndicator.ts";
import {
  generateRefreshProposal,
  type RefreshContext, type SourcePostForRefresh,
} from "../../shared/blog-refresh-agent.ts";
import type { AuthResult } from "../../shared/auth.ts";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
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

interface PostInput {
  slug?: string;
  title?: string;
  excerpt?: string | null;
  content_html?: string;
  content_json?: unknown;
  featured_image_url?: string | null;
  status?: "draft" | "published" | "archived";
  published_at?: string | null;
  seo_title?: string | null;
  seo_description?: string | null;
  canonical_url?: string | null;
  og_image_url?: string | null;
  tags?: string[];
  category?: string | null;
  ai_generated?: boolean;
  ai_meta?: Record<string, unknown> | null;
}

interface Body {
  action:
    | "list" | "get" | "create" | "update" | "delete"
    | "list_templates" | "save_template" | "delete_template"
    | "list_revisions" | "get_revision" | "restore_revision"
    | "score_post" | "rescore_all"
    | "qa_post"
    | "syndicate_post"
    | "list_refresh_queue" | "action_refresh_queue" | "trigger_refresh_proposal"
    | "list_post_metrics";
  platforms?: string[];
  refresh_queue_id?: string;
  refresh_action?: "in_progress" | "dismissed" | "done" | "queued";
  refresh_status_filter?: "queued" | "in_progress" | "proposed" | "done" | "dismissed" | "open" | "all";
  metric_days?: number;
  id?: string;
  slug?: string;
  status?: "draft" | "published" | "archived" | "all";
  limit?: number;
  offset?: number;
  post?: PostInput;
  reason?: string;
  /** Bypass the pre-publish QA gate. Audit-logged. */
  force?: boolean;
  template?: {
    id?: string;
    name: string;
    description?: string;
    system_prompt: string;
    user_prompt_template: string;
    slug_template?: string;
    title_template?: string;
    default_tags?: string[];
    default_category?: string;
  };
  template_id?: string;
  // Revision actions
  post_id?: string;
  revision_id?: string;
}

export async function handleAdminBlog(req: Request, auth: AuthResult): Promise<Response> {
  const admin = await requireSystemAdmin(auth);
  if (!admin.ok) return admin.response;

  const body: Body = await req.json().catch(() => ({ action: "list" }));

  switch (body.action) {
    case "list":
      return listPosts(body);
    case "get":
      return getPost(body);
    case "create":
      return createPost(body, admin.userId, req);
    case "update":
      return updatePost(body, admin.userId, req);
    case "delete":
      return deletePost(body, admin.userId, req);
    case "list_templates":
      return listTemplates();
    case "save_template":
      return saveTemplate(body, admin.userId);
    case "delete_template":
      return deleteTemplate(body);
    case "list_revisions":
      return listRevisions(body);
    case "get_revision":
      return getRevision(body);
    case "restore_revision":
      return restoreRevision(body, admin.userId, req);
    case "score_post":
      return scorePostAction(body);
    case "rescore_all":
      return rescoreAll(admin.userId, req);
    case "qa_post":
      return qaPostAction(body);
    case "syndicate_post":
      return syndicatePost(body, admin.userId, req);
    case "list_refresh_queue":
      return listRefreshQueue(body);
    case "action_refresh_queue":
      return actionRefreshQueue(body, admin.userId, req);
    case "trigger_refresh_proposal":
      return triggerRefreshProposal(body, admin.userId, req);
    case "list_post_metrics":
      return listPostMetrics(body);
    default:
      return json({ error: "Unknown action" }, 400);
  }
}

// =============================================================================
// Refresh queue (US-BLOG-063 / US-BLOG-066)
// =============================================================================

async function listRefreshQueue(body: Body): Promise<Response> {
  const limit = Math.max(1, Math.min(200, body.limit ?? 100));
  const offset = Math.max(0, body.offset ?? 0);
  const filter = body.refresh_status_filter ?? "open";

  let query = supabaseAdmin
    .from("blog_refresh_queue")
    .select(
      "id, post_id, reason, status, detection_meta, proposal_revision_id, proposal_summary, actioned_by, actioned_at, notes, created_at, updated_at",
      { count: "exact" },
    )
    .order("created_at", { ascending: false })
    .range(offset, offset + limit - 1);

  if (filter === "open") {
    query = query.in("status", ["queued", "in_progress", "proposed"]);
  } else if (filter !== "all") {
    query = query.eq("status", filter);
  }

  const { data, error, count } = await query;
  if (error) return json({ error: error.message }, 500);

  // Hydrate post slug + title for the list view in one round trip.
  const postIds = Array.from(new Set((data ?? []).map((r) => r.post_id)));
  const postMap: Record<string, { slug: string; title: string; seo_score: number | null }> = {};
  if (postIds.length > 0) {
    const { data: posts } = await supabaseAdmin
      .from("blog_posts")
      .select("id, slug, title, seo_score")
      .in("id", postIds);
    for (const p of posts ?? []) {
      postMap[p.id as string] = {
        slug: p.slug as string,
        title: p.title as string,
        seo_score: p.seo_score as number | null,
      };
    }
  }

  const items = (data ?? []).map((r) => ({
    ...r,
    post: postMap[r.post_id as string] ?? null,
  }));

  return json({ items, total: count ?? 0, limit, offset, filter });
}

async function actionRefreshQueue(body: Body, adminId: string, req: Request): Promise<Response> {
  if (!body.refresh_queue_id) return json({ error: "refresh_queue_id required" }, 400);
  if (!body.refresh_action) return json({ error: "refresh_action required" }, 400);

  const action = body.refresh_action;
  const allowed = new Set(["in_progress", "dismissed", "done", "queued"]);
  if (!allowed.has(action)) return json({ error: `Invalid refresh_action: ${action}` }, 400);

  const { data, error } = await supabaseAdmin
    .from("blog_refresh_queue")
    .update({
      status: action,
      actioned_by: adminId,
      actioned_at: new Date().toISOString(),
      notes: body.reason ?? undefined,
    })
    .eq("id", body.refresh_queue_id)
    .select()
    .single();

  if (error || !data) return json({ error: error?.message ?? "Update failed" }, 500);

  await logAdminAction(adminId, `blog.refresh_queue.${action}`, {
    resourceType: "blog_refresh_queue",
    resourceId: body.refresh_queue_id,
    metadata: { post_id: data.post_id, reason: data.reason },
    req,
  });

  return json({ item: data });
}

async function triggerRefreshProposal(body: Body, adminId: string, req: Request): Promise<Response> {
  if (!body.refresh_queue_id) return json({ error: "refresh_queue_id required" }, 400);

  const { data: queueRow, error: qErr } = await supabaseAdmin
    .from("blog_refresh_queue")
    .select("id, post_id, reason, status, detection_meta, notes")
    .eq("id", body.refresh_queue_id)
    .maybeSingle();
  if (qErr) return json({ error: qErr.message }, 500);
  if (!queueRow) return json({ error: "Queue row not found" }, 404);

  // Mark in-progress so concurrent triggers don't double-spend tokens.
  const { error: lockErr } = await supabaseAdmin
    .from("blog_refresh_queue")
    .update({ status: "in_progress", actioned_by: adminId, actioned_at: new Date().toISOString() })
    .eq("id", body.refresh_queue_id)
    .in("status", ["queued", "proposed"]);  // only if not already in_progress
  if (lockErr) return json({ error: `Could not lock queue row: ${lockErr.message}` }, 500);

  // Fetch the post + brand config
  const { data: post, error: pErr } = await supabaseAdmin
    .from("blog_posts")
    .select("id, slug, title, excerpt, content_html, seo_title, seo_description, tags, category, ai_meta, published_at, status")
    .eq("id", queueRow.post_id)
    .maybeSingle();
  if (pErr || !post) {
    return json({ error: pErr?.message ?? "Post not found" }, 404);
  }

  const { data: cfgRow } = await supabaseAdmin
    .from("blog_generation_config")
    .select("config")
    .eq("id", 1)
    .maybeSingle();
  const blogConfig = (cfgRow?.config ?? {}) as Record<string, unknown>;

  const source: SourcePostForRefresh = {
    id: post.id,
    slug: post.slug,
    title: post.title,
    excerpt: post.excerpt,
    content_html: post.content_html,
    seo_title: post.seo_title,
    seo_description: post.seo_description,
    tags: Array.isArray(post.tags) ? post.tags : [],
    category: post.category,
    ai_meta: post.ai_meta,
    published_at: post.published_at,
  };

  const ctx: RefreshContext = {
    blogConfig,
    reason: queueRow.reason as RefreshContext["reason"],
    detectionMeta: (queueRow.detection_meta ?? null) as Record<string, unknown> | null,
    editorNotes: (queueRow.notes ?? null) as string | null,
  };

  let result;
  try {
    result = await generateRefreshProposal(source, ctx, supabaseAdmin);
  } catch (err) {
    // Roll the queue row back to 'queued' so the editor can retry.
    await supabaseAdmin
      .from("blog_refresh_queue")
      .update({ status: "queued", notes: err instanceof Error ? err.message : String(err) })
      .eq("id", body.refresh_queue_id);
    return json({ error: err instanceof Error ? err.message : "Refresh proposal failed" }, 502);
  }

  // Stamp the queue row with the proposal pointer so the UI can deep-link.
  await supabaseAdmin
    .from("blog_refresh_queue")
    .update({
      status: "proposed",
      proposal_revision_id: result.revision_id,
      proposal_summary: result.proposal.change_summary,
    })
    .eq("id", body.refresh_queue_id);

  await logAdminAction(adminId, "blog.refresh_proposal", {
    resourceType: "blog_post",
    resourceId: source.id,
    metadata: {
      queue_id: body.refresh_queue_id,
      revision_id: result.revision_id,
      reason: ctx.reason,
      input_tokens: result.ai_meta.input_tokens ?? null,
      output_tokens: result.ai_meta.output_tokens ?? null,
    },
    req,
  });

  return json({
    revision_id: result.revision_id,
    change_summary: result.proposal.change_summary,
    queue_id: body.refresh_queue_id,
    history_url: `/admin/blog/${source.id}/history`,
    ai_meta: result.ai_meta,
  });
}

// =============================================================================
// Per-post metrics (US-BLOG-061)
// =============================================================================

async function listPostMetrics(body: Body): Promise<Response> {
  if (!body.id) return json({ error: "id (post id) required" }, 400);
  const days = Math.max(1, Math.min(365, body.metric_days ?? 90));
  const sinceIso = new Date(Date.now() - days * 86_400_000).toISOString().slice(0, 10);

  const { data, error } = await supabaseAdmin
    .from("blog_post_metrics")
    .select("metric_date, source, impressions, clicks, avg_position, ctr, sessions, engaged_sessions, conversions, avg_time_on_page_seconds")
    .eq("post_id", body.id)
    .gte("metric_date", sinceIso)
    .order("metric_date", { ascending: true });

  if (error) return json({ error: error.message }, 500);

  // Pre-aggregate trailing 28d totals so the editor sidebar doesn't have to.
  const cutoff = new Date(Date.now() - 28 * 86_400_000).toISOString().slice(0, 10);
  let clicks_28d = 0, impressions_28d = 0, sessions_28d = 0, conversions_28d = 0;
  for (const r of data ?? []) {
    if ((r.metric_date as string) < cutoff) continue;
    if (r.source === "search_console") {
      clicks_28d += (r.clicks as number) ?? 0;
      impressions_28d += (r.impressions as number) ?? 0;
    } else if (r.source === "ga4") {
      sessions_28d += (r.sessions as number) ?? 0;
      conversions_28d += (r.conversions as number) ?? 0;
    }
  }

  return json({
    rows: data ?? [],
    summary: { clicks_28d, impressions_28d, sessions_28d, conversions_28d, days },
  });
}

// =============================================================================
// Syndication (US-BLOG-044/045/046/048)
// =============================================================================

async function syndicatePost(body: Body, adminId: string, req: Request): Promise<Response> {
  if (!body.id) return json({ error: "id (post id) required" }, 400);
  const platformsRaw = (body.platforms ?? []).map((p) => String(p).toLowerCase());
  if (platformsRaw.length === 0) return json({ error: "platforms array required" }, 400);

  const platforms: SyndicationPlatform[] = [];
  for (const p of platformsRaw) {
    if (!SUPPORTED_PLATFORMS.includes(p as SyndicationPlatform)) {
      return json({ error: `Unsupported syndication platform: ${p}. Allowed: ${SUPPORTED_PLATFORMS.join(", ")}` }, 400);
    }
    platforms.push(p as SyndicationPlatform);
  }

  // Load the source post
  const { data: post, error: postErr } = await supabaseAdmin
    .from("blog_posts")
    .select("id, slug, title, excerpt, content_html, category, tags, ai_meta, status")
    .eq("id", body.id)
    .maybeSingle();
  if (postErr) return json({ error: postErr.message }, 500);
  if (!post) return json({ error: "Post not found" }, 404);

  const source: SyndicationSourcePost = {
    id: post.id,
    slug: post.slug,
    title: post.title,
    excerpt: post.excerpt,
    content_html: post.content_html,
    category: post.category,
    tags: Array.isArray(post.tags) ? post.tags : [],
    primary_keyword: primaryKeywordFromAiMeta(post.ai_meta),
  };

  // Load brand voice config
  const { data: cfgRow } = await supabaseAdmin
    .from("blog_generation_config")
    .select("config")
    .eq("id", 1)
    .maybeSingle();
  const blogConfig = (cfgRow?.config ?? {}) as Record<string, unknown>;

  // Generate
  let result;
  try {
    result = await generateSyndication(source, platforms, blogConfig);
  } catch (err) {
    return json({ error: err instanceof Error ? err.message : "Syndication generation failed" }, 502);
  }

  // Insert one social_posts row per variant. status='draft' so the editor
  // can review before pushing through the publish webhook.
  const insertRows = result.variants.map((v) => ({
    content: v.content,
    platforms: [v.platform],
    status: "draft" as const,
    link_url: v.link_url,
    media_urls: [],
    author_id: adminId,
    source_post_id: source.id,
    variant_meta: {
      ...v.meta,
      variant_index: v.variant_index,
      generated_from_blog: true,
      ai_meta: result.ai_meta,
    },
  }));

  const { data: inserted, error: insErr } = await supabaseAdmin
    .from("social_posts")
    .insert(insertRows)
    .select();
  if (insErr) return json({ error: insErr.message }, 500);

  await logAdminAction(adminId, "blog.syndicate", {
    resourceType: "blog_post",
    resourceId: source.id,
    metadata: {
      slug: source.slug,
      platforms,
      variants_created: inserted?.length ?? 0,
      input_tokens: result.ai_meta.input_tokens ?? null,
      output_tokens: result.ai_meta.output_tokens ?? null,
    },
    req,
  });

  return json({
    drafts: inserted ?? [],
    variant_count: inserted?.length ?? 0,
    ai_meta: result.ai_meta,
  });
}

// =============================================================================
// QA helpers (US-BLOG-040)
// =============================================================================

function toQaInput(post: PostInput, slug: string): QaInputPost {
  return {
    title: post.title ?? null,
    slug,
    excerpt: post.excerpt ?? null,
    content_html: post.content_html ?? null,
    seo_title: post.seo_title ?? null,
    seo_description: post.seo_description ?? null,
    og_image_url: post.og_image_url ?? null,
    featured_image_url: post.featured_image_url ?? null,
  };
}

async function qaPostAction(body: Body): Promise<Response> {
  let input: QaInputPost;
  if (body.post) {
    const slug = (body.post.slug ?? "").trim() || "(unsaved)";
    input = toQaInput(body.post, slug);
  } else if (body.id) {
    const { data, error } = await supabaseAdmin
      .from("blog_posts")
      .select("id, title, slug, excerpt, content_html, seo_title, seo_description, og_image_url, featured_image_url")
      .eq("id", body.id)
      .maybeSingle();
    if (error) return json({ error: error.message }, 500);
    if (!data) return json({ error: "Not found" }, 404);
    input = data as QaInputPost;
  } else {
    return json({ error: "Either id or post body required" }, 400);
  }

  const result = await runPrePublishQA(input, supabaseAdmin);
  return json({ result });
}

// =============================================================================
// SEO scorer integration (US-BLOG-033)
// =============================================================================

function primaryKeywordFromAiMeta(ai_meta: unknown): string | null {
  if (ai_meta && typeof ai_meta === "object") {
    const m = ai_meta as Record<string, unknown>;
    if (typeof m.primary_keyword === "string" && m.primary_keyword) return m.primary_keyword;
  }
  return null;
}

function scoreFields(post: PostInput, ai_meta?: unknown): { seo_score: number; seo_score_meta: Record<string, unknown> } {
  const scoreable: ScoreableBlogPost = {
    title: post.title ?? null,
    slug: post.slug ?? null,
    excerpt: post.excerpt ?? null,
    content_html: post.content_html ?? null,
    seo_title: post.seo_title ?? null,
    seo_description: post.seo_description ?? null,
    tags: post.tags ?? null,
    primary_keyword: primaryKeywordFromAiMeta(ai_meta ?? post.ai_meta),
  };
  const result = scoreBlogPost(scoreable);
  return {
    seo_score: result.score,
    seo_score_meta: {
      breakdown: result.breakdown,
      hints: result.hints,
      scored_at: result.scored_at,
      primary_keyword: result.primary_keyword,
    },
  };
}

async function listPosts(body: Body): Promise<Response> {
  const limit = Math.max(1, Math.min(200, body.limit ?? 50));
  const offset = Math.max(0, body.offset ?? 0);

  let query = supabaseAdmin
    .from("blog_posts")
    .select("id, slug, title, excerpt, status, published_at, featured_image_url, tags, category, ai_generated, view_count, seo_score, author_id, created_at, updated_at", { count: "exact" })
    .order("updated_at", { ascending: false })
    .range(offset, offset + limit - 1);

  if (body.status && body.status !== "all") {
    query = query.eq("status", body.status);
  }

  const { data, error, count } = await query;
  if (error) return json({ error: error.message }, 500);
  return json({ posts: data ?? [], total: count ?? 0, limit, offset });
}

async function getPost(body: Body): Promise<Response> {
  if (!body.id && !body.slug) return json({ error: "id or slug required" }, 400);

  let query = supabaseAdmin.from("blog_posts").select("*");
  query = body.id ? query.eq("id", body.id) : query.eq("slug", body.slug!);

  const { data, error } = await query.maybeSingle();
  if (error) return json({ error: error.message }, 500);
  if (!data) return json({ error: "Not found" }, 404);
  return json({ post: data });
}

async function resolveUniqueSlug(base: string, excludeId?: string): Promise<string> {
  let slug = base;
  let n = 1;
  while (true) {
    let q = supabaseAdmin.from("blog_posts").select("id").eq("slug", slug).limit(1);
    if (excludeId) q = q.neq("id", excludeId);
    const { data } = await q;
    if (!data || data.length === 0) return slug;
    n += 1;
    slug = `${base}-${n}`;
    if (n > 100) return `${base}-${Date.now()}`;
  }
}

async function createPost(body: Body, adminId: string, req: Request): Promise<Response> {
  const post = body.post;
  if (!post?.title) return json({ error: "title required" }, 400);

  const baseSlug = slugify(post.slug || post.title);
  if (!baseSlug) return json({ error: "could not derive slug" }, 400);
  const slug = await resolveUniqueSlug(baseSlug);

  const status = post.status ?? "draft";
  const publishedAt =
    status === "published"
      ? (post.published_at ?? new Date().toISOString())
      : post.published_at ?? null;

  // Pre-publish QA gate: if creating in published state, every error-severity
  // check must pass unless body.force === true. Force is audit-logged below.
  let qaResult: QaResult | null = null;
  if (status === "published") {
    qaResult = await runPrePublishQA(toQaInput(post, slug), supabaseAdmin);
    if (!qaResult.canPublish && !body.force) {
      return json({ error: "Pre-publish QA failed. Fix errors or pass force=true to override.", qa: qaResult }, 422);
    }
  }

  const scored = scoreFields({ ...post, slug, title: post.title }, post.ai_meta);

  const { data, error } = await supabaseAdmin
    .from("blog_posts")
    .insert({
      slug,
      title: post.title,
      excerpt: post.excerpt ?? null,
      content_html: post.content_html ?? "",
      content_json: post.content_json ?? null,
      featured_image_url: post.featured_image_url ?? null,
      status,
      published_at: publishedAt,
      author_id: adminId,
      seo_title: post.seo_title ?? null,
      seo_description: post.seo_description ?? null,
      canonical_url: post.canonical_url ?? null,
      og_image_url: post.og_image_url ?? null,
      tags: post.tags ?? [],
      category: post.category ?? null,
      ai_generated: post.ai_generated ?? false,
      ai_meta: post.ai_meta ?? null,
      seo_score: scored.seo_score,
      seo_score_meta: scored.seo_score_meta,
    })
    .select()
    .single();

  if (error) return json({ error: error.message }, 500);

  await logAdminAction(adminId, "blog.create", {
    resourceType: "blog_post",
    resourceId: data.id,
    metadata: {
      slug: data.slug,
      status: data.status,
      qa_forced: !!(body.force && qaResult && !qaResult.canPublish),
      qa_error_count: qaResult?.errorCount ?? null,
    },
    req,
  });

  return json({ post: data, qa: qaResult });
}

async function updatePost(body: Body, adminId: string, req: Request): Promise<Response> {
  if (!body.id) return json({ error: "id required" }, 400);
  const post = body.post;
  if (!post) return json({ error: "post body required" }, 400);

  // Snapshot the current state BEFORE applying the patch so the new revision
  // captures what was about to be replaced. Failure here is non-fatal — we'd
  // rather log and proceed than block edits on history bookkeeping.
  const reason = body.reason && typeof body.reason === "string" ? body.reason : "manual_edit";
  const { error: snapErr } = await supabaseAdmin.rpc("snapshot_blog_post_revision", {
    p_post_id: body.id,
    p_editor_id: adminId,
    p_reason: reason,
    p_parent_revision_id: null,
  });
  if (snapErr) {
    console.warn(`snapshot_blog_post_revision failed for ${body.id}: ${snapErr.message}`);
  }

  const patch: Record<string, unknown> = {};

  if (post.title !== undefined) patch.title = post.title;
  if (post.slug !== undefined) {
    const base = slugify(post.slug);
    if (base) patch.slug = await resolveUniqueSlug(base, body.id);
  }
  if (post.excerpt !== undefined) patch.excerpt = post.excerpt;
  if (post.content_html !== undefined) patch.content_html = post.content_html;
  if (post.content_json !== undefined) patch.content_json = post.content_json;
  if (post.featured_image_url !== undefined) patch.featured_image_url = post.featured_image_url;
  if (post.seo_title !== undefined) patch.seo_title = post.seo_title;
  if (post.seo_description !== undefined) patch.seo_description = post.seo_description;
  if (post.canonical_url !== undefined) patch.canonical_url = post.canonical_url;
  if (post.og_image_url !== undefined) patch.og_image_url = post.og_image_url;
  if (post.tags !== undefined) patch.tags = post.tags;
  if (post.category !== undefined) patch.category = post.category;
  if (post.ai_meta !== undefined) patch.ai_meta = post.ai_meta;

  if (post.status !== undefined) {
    patch.status = post.status;
    if (post.status === "published" && !post.published_at) {
      // Only set published_at if not already set
      const { data: existing } = await supabaseAdmin
        .from("blog_posts")
        .select("published_at")
        .eq("id", body.id)
        .maybeSingle();
      if (!existing?.published_at) patch.published_at = new Date().toISOString();
    } else if (post.published_at !== undefined) {
      patch.published_at = post.published_at;
    }
  } else if (post.published_at !== undefined) {
    patch.published_at = post.published_at;
  }

  // Re-score against the merged state (existing row + patch). We need the
  // current values for any field the patch didn't touch.
  const { data: existingForScore } = await supabaseAdmin
    .from("blog_posts")
    .select("title, slug, excerpt, content_html, seo_title, seo_description, og_image_url, featured_image_url, tags, ai_meta, status")
    .eq("id", body.id)
    .maybeSingle();
  let mergedForGate: PostInput | null = null;
  if (existingForScore) {
    const merged: PostInput = {
      title: (patch.title as string | undefined) ?? (existingForScore.title as string),
      slug: (patch.slug as string | undefined) ?? (existingForScore.slug as string),
      excerpt: (patch.excerpt as string | null | undefined) ?? (existingForScore.excerpt as string | null),
      content_html: (patch.content_html as string | undefined) ?? (existingForScore.content_html as string),
      seo_title: (patch.seo_title as string | null | undefined) ?? (existingForScore.seo_title as string | null),
      seo_description: (patch.seo_description as string | null | undefined) ?? (existingForScore.seo_description as string | null),
      og_image_url: (patch.og_image_url as string | null | undefined) ?? (existingForScore.og_image_url as string | null),
      featured_image_url: (patch.featured_image_url as string | null | undefined) ?? (existingForScore.featured_image_url as string | null),
      tags: (patch.tags as string[] | undefined) ?? (existingForScore.tags as string[] | null) ?? [],
      ai_meta: (patch.ai_meta as Record<string, unknown> | null | undefined) ?? (existingForScore.ai_meta as Record<string, unknown> | null),
    };
    const scored = scoreFields(merged, merged.ai_meta);
    patch.seo_score = scored.seo_score;
    patch.seo_score_meta = scored.seo_score_meta;
    mergedForGate = merged;
  }

  // Pre-publish QA gate. Runs whenever the post will be in 'published' state
  // after this update — both transitioning to published and re-saving an
  // already-published post. body.force === true bypasses with audit log entry.
  const willBePublished =
    (patch.status as string | undefined) === "published"
    || (patch.status === undefined && (existingForScore?.status as string | undefined) === "published");
  let qaResult: QaResult | null = null;
  if (willBePublished && mergedForGate) {
    qaResult = await runPrePublishQA(toQaInput(mergedForGate, mergedForGate.slug ?? ""), supabaseAdmin);
    if (!qaResult.canPublish && !body.force) {
      return json({ error: "Pre-publish QA failed. Fix errors or pass force=true to override.", qa: qaResult }, 422);
    }
  }

  const { data, error } = await supabaseAdmin
    .from("blog_posts")
    .update(patch)
    .eq("id", body.id)
    .select()
    .single();

  if (error) return json({ error: error.message }, 500);

  await logAdminAction(adminId, "blog.update", {
    resourceType: "blog_post",
    resourceId: body.id,
    metadata: {
      slug: data.slug,
      status: data.status,
      qa_forced: !!(body.force && qaResult && !qaResult.canPublish),
      qa_error_count: qaResult?.errorCount ?? null,
    },
    req,
  });

  return json({ post: data, qa: qaResult });
}

async function deletePost(body: Body, adminId: string, req: Request): Promise<Response> {
  if (!body.id) return json({ error: "id required" }, 400);

  const { error } = await supabaseAdmin.from("blog_posts").delete().eq("id", body.id);
  if (error) return json({ error: error.message }, 500);

  await logAdminAction(adminId, "blog.delete", {
    resourceType: "blog_post",
    resourceId: body.id,
    req,
  });

  return json({ success: true });
}

async function listTemplates(): Promise<Response> {
  const { data, error } = await supabaseAdmin
    .from("blog_templates")
    .select("*")
    .order("updated_at", { ascending: false });
  if (error) return json({ error: error.message }, 500);
  return json({ templates: data ?? [] });
}

async function saveTemplate(body: Body, adminId: string): Promise<Response> {
  const t = body.template;
  if (!t?.name || !t?.system_prompt || !t?.user_prompt_template) {
    return json({ error: "name, system_prompt, user_prompt_template required" }, 400);
  }

  const payload = {
    name: t.name,
    description: t.description ?? null,
    system_prompt: t.system_prompt,
    user_prompt_template: t.user_prompt_template,
    slug_template: t.slug_template ?? null,
    title_template: t.title_template ?? null,
    default_tags: t.default_tags ?? [],
    default_category: t.default_category ?? null,
    created_by: adminId,
  };

  if (t.id) {
    const { data, error } = await supabaseAdmin
      .from("blog_templates")
      .update(payload)
      .eq("id", t.id)
      .select()
      .single();
    if (error) return json({ error: error.message }, 500);
    return json({ template: data });
  }

  const { data, error } = await supabaseAdmin
    .from("blog_templates")
    .insert(payload)
    .select()
    .single();
  if (error) return json({ error: error.message }, 500);
  return json({ template: data });
}

async function deleteTemplate(body: Body): Promise<Response> {
  if (!body.template_id) return json({ error: "template_id required" }, 400);
  const { error } = await supabaseAdmin.from("blog_templates").delete().eq("id", body.template_id);
  if (error) return json({ error: error.message }, 500);
  return json({ success: true });
}

// =============================================================================
// Revisions (US-BLOG-009)
// =============================================================================

async function listRevisions(body: Body): Promise<Response> {
  const postId = body.post_id ?? body.id;
  if (!postId) return json({ error: "post_id required" }, 400);

  const limit = Math.max(1, Math.min(200, body.limit ?? 50));
  const offset = Math.max(0, body.offset ?? 0);

  const { data, error, count } = await supabaseAdmin
    .from("blog_post_revisions")
    .select(
      "id, post_id, editor_id, title, slug, status, reason, parent_revision_id, created_at",
      { count: "exact" },
    )
    .eq("post_id", postId)
    .order("created_at", { ascending: false })
    .range(offset, offset + limit - 1);

  if (error) return json({ error: error.message }, 500);

  // Hydrate editor display names in one round trip
  const editorIds = Array.from(
    new Set((data ?? []).map((r) => r.editor_id).filter((v): v is string => !!v)),
  );
  const editors: Record<string, { display_name: string | null; email: string | null }> = {};
  if (editorIds.length > 0) {
    const { data: users } = await supabaseAdmin
      .from("users")
      .select("id, display_name, email")
      .in("id", editorIds);
    for (const u of users ?? []) {
      editors[u.id as string] = {
        display_name: (u.display_name as string | null) ?? null,
        email: (u.email as string | null) ?? null,
      };
    }
  }

  const revisions = (data ?? []).map((r) => ({
    ...r,
    editor: r.editor_id ? editors[r.editor_id] ?? null : null,
  }));

  return json({ revisions, total: count ?? 0, limit, offset });
}

async function getRevision(body: Body): Promise<Response> {
  if (!body.revision_id) return json({ error: "revision_id required" }, 400);

  const { data, error } = await supabaseAdmin
    .from("blog_post_revisions")
    .select("*")
    .eq("id", body.revision_id)
    .maybeSingle();

  if (error) return json({ error: error.message }, 500);
  if (!data) return json({ error: "Revision not found" }, 404);

  return json({ revision: data });
}

/**
 * Stateless scorer — used by the editor to preview the score as the draft
 * changes without touching the DB. Body either references an existing post
 * (id) or supplies a fresh PostInput.
 */
async function scorePostAction(body: Body): Promise<Response> {
  let scoreable: ScoreableBlogPost;
  if (body.post) {
    scoreable = {
      title: body.post.title ?? null,
      slug: body.post.slug ?? null,
      excerpt: body.post.excerpt ?? null,
      content_html: body.post.content_html ?? null,
      seo_title: body.post.seo_title ?? null,
      seo_description: body.post.seo_description ?? null,
      tags: body.post.tags ?? null,
      primary_keyword: primaryKeywordFromAiMeta(body.post.ai_meta),
    };
  } else if (body.id) {
    const { data, error } = await supabaseAdmin
      .from("blog_posts")
      .select("title, slug, excerpt, content_html, seo_title, seo_description, tags, ai_meta")
      .eq("id", body.id)
      .maybeSingle();
    if (error) return json({ error: error.message }, 500);
    if (!data) return json({ error: "Not found" }, 404);
    scoreable = {
      title: data.title as string | null,
      slug: data.slug as string | null,
      excerpt: data.excerpt as string | null,
      content_html: data.content_html as string | null,
      seo_title: data.seo_title as string | null,
      seo_description: data.seo_description as string | null,
      tags: data.tags as string[] | null,
      primary_keyword: primaryKeywordFromAiMeta(data.ai_meta),
    };
  } else {
    return json({ error: "Either id or post body required" }, 400);
  }

  return json({ result: scoreBlogPost(scoreable) });
}

/**
 * Re-score every post and persist the updated score + meta. Useful after a
 * scoring rule change or to backfill rows from before the seo_score columns
 * existed.
 */
async function rescoreAll(adminId: string, req: Request): Promise<Response> {
  const { data: posts, error } = await supabaseAdmin
    .from("blog_posts")
    .select("id, title, slug, excerpt, content_html, seo_title, seo_description, tags, ai_meta");
  if (error) return json({ error: error.message }, 500);

  let updated = 0;
  let failed = 0;
  for (const p of posts ?? []) {
    const result = scoreBlogPost({
      title: p.title as string | null,
      slug: p.slug as string | null,
      excerpt: p.excerpt as string | null,
      content_html: p.content_html as string | null,
      seo_title: p.seo_title as string | null,
      seo_description: p.seo_description as string | null,
      tags: p.tags as string[] | null,
      primary_keyword: primaryKeywordFromAiMeta(p.ai_meta),
    });
    const { error: updErr } = await supabaseAdmin
      .from("blog_posts")
      .update({
        seo_score: result.score,
        seo_score_meta: {
          breakdown: result.breakdown,
          hints: result.hints,
          scored_at: result.scored_at,
          primary_keyword: result.primary_keyword,
        },
      })
      .eq("id", p.id);
    if (updErr) failed++;
    else updated++;
  }

  await logAdminAction(adminId, "blog.rescore_all", {
    metadata: { updated, failed, total: (posts ?? []).length },
    req,
  });

  return json({ updated, failed, total: (posts ?? []).length });
}

async function restoreRevision(body: Body, adminId: string, req: Request): Promise<Response> {
  if (!body.revision_id) return json({ error: "revision_id required" }, 400);

  const { data: rev, error: revErr } = await supabaseAdmin
    .from("blog_post_revisions")
    .select("*")
    .eq("id", body.revision_id)
    .maybeSingle();

  if (revErr) return json({ error: revErr.message }, 500);
  if (!rev) return json({ error: "Revision not found" }, 404);

  // Snapshot the current state with reason='restore' and parent pointing at the
  // revision we're rolling back to. The snapshot lands BEFORE we apply the
  // restore so the trail reads: "<old state> → restored from <revision_id>".
  const { error: snapErr } = await supabaseAdmin.rpc("snapshot_blog_post_revision", {
    p_post_id: rev.post_id,
    p_editor_id: adminId,
    p_reason: "restore",
    p_parent_revision_id: rev.id,
  });
  if (snapErr) {
    return json({ error: `Failed to snapshot pre-restore state: ${snapErr.message}` }, 500);
  }

  const { data: updated, error: updErr } = await supabaseAdmin
    .from("blog_posts")
    .update({
      title: rev.title,
      slug: rev.slug,
      excerpt: rev.excerpt,
      content_html: rev.content_html,
      content_json: rev.content_json,
      featured_image_url: rev.featured_image_url,
      seo_title: rev.seo_title,
      seo_description: rev.seo_description,
      canonical_url: rev.canonical_url,
      og_image_url: rev.og_image_url,
      tags: rev.tags ?? [],
      category: rev.category,
      status: rev.status,
      // Note: ai_meta is intentionally restored too so analytics dashboards see
      // the historical generation context, not the most recent edit's context.
      ai_meta: rev.ai_meta,
    })
    .eq("id", rev.post_id)
    .select()
    .single();

  if (updErr || !updated) return json({ error: updErr?.message ?? "Restore failed" }, 500);

  await logAdminAction(adminId, "blog.restore_revision", {
    resourceType: "blog_post",
    resourceId: rev.post_id,
    metadata: { revision_id: rev.id, slug: updated.slug, status: updated.status },
    req,
  });

  return json({ post: updated, restored_from: rev.id });
}
