import { supabaseAdmin } from "../../shared/supabase.ts";
import { requireSystemAdmin, logAdminAction } from "../../shared/admin-auth.ts";
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
  action: "list" | "get" | "create" | "update" | "delete" | "list_templates" | "save_template" | "delete_template";
  id?: string;
  slug?: string;
  status?: "draft" | "published" | "archived" | "all";
  limit?: number;
  offset?: number;
  post?: PostInput;
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
    default:
      return json({ error: "Unknown action" }, 400);
  }
}

async function listPosts(body: Body): Promise<Response> {
  const limit = Math.max(1, Math.min(200, body.limit ?? 50));
  const offset = Math.max(0, body.offset ?? 0);

  let query = supabaseAdmin
    .from("blog_posts")
    .select("id, slug, title, excerpt, status, published_at, featured_image_url, tags, category, ai_generated, view_count, author_id, created_at, updated_at", { count: "exact" })
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
    })
    .select()
    .single();

  if (error) return json({ error: error.message }, 500);

  await logAdminAction(adminId, "blog.create", {
    resourceType: "blog_post",
    resourceId: data.id,
    metadata: { slug: data.slug, status: data.status },
    req,
  });

  return json({ post: data });
}

async function updatePost(body: Body, adminId: string, req: Request): Promise<Response> {
  if (!body.id) return json({ error: "id required" }, 400);
  const post = body.post;
  if (!post) return json({ error: "post body required" }, 400);

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
    metadata: { slug: data.slug, status: data.status },
    req,
  });

  return json({ post: data });
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
