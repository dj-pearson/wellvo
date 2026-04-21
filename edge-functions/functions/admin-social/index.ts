import { supabaseAdmin } from "../../shared/supabase.ts";
import { requireSystemAdmin, logAdminAction } from "../../shared/admin-auth.ts";
import type { AuthResult } from "../../shared/auth.ts";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

const ALLOWED_PLATFORMS = new Set(["twitter", "x", "linkedin", "facebook", "instagram", "threads", "tiktok", "youtube", "bluesky"]);

interface PostInput {
  content?: string;
  platforms?: string[];
  status?: "draft" | "scheduled" | "posted" | "failed";
  scheduled_at?: string | null;
  media_urls?: string[];
  link_url?: string | null;
}

interface Body {
  action: "list" | "get" | "create" | "update" | "delete" | "publish";
  id?: string;
  status?: "draft" | "scheduled" | "posted" | "failed" | "all";
  limit?: number;
  offset?: number;
  post?: PostInput;
}

export async function handleAdminSocial(req: Request, auth: AuthResult): Promise<Response> {
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
    case "publish":
      return publishPost(body, admin.userId, req);
    default:
      return json({ error: "Unknown action" }, 400);
  }
}

function validatePlatforms(platforms: string[] | undefined): { ok: true; platforms: string[] } | { ok: false; error: string } {
  if (!platforms || platforms.length === 0) return { ok: true, platforms: [] };
  const cleaned = platforms.map((p) => p.toLowerCase().trim()).filter(Boolean);
  for (const p of cleaned) {
    if (!ALLOWED_PLATFORMS.has(p)) return { ok: false, error: `Unsupported platform: ${p}` };
  }
  return { ok: true, platforms: [...new Set(cleaned)] };
}

async function listPosts(body: Body): Promise<Response> {
  const limit = Math.max(1, Math.min(200, body.limit ?? 50));
  const offset = Math.max(0, body.offset ?? 0);

  let query = supabaseAdmin
    .from("social_posts")
    .select("*", { count: "exact" })
    .order("updated_at", { ascending: false })
    .range(offset, offset + limit - 1);

  if (body.status && body.status !== "all") query = query.eq("status", body.status);

  const { data, error, count } = await query;
  if (error) return json({ error: error.message }, 500);
  return json({ posts: data ?? [], total: count ?? 0, limit, offset });
}

async function getPost(body: Body): Promise<Response> {
  if (!body.id) return json({ error: "id required" }, 400);
  const { data, error } = await supabaseAdmin.from("social_posts").select("*").eq("id", body.id).maybeSingle();
  if (error) return json({ error: error.message }, 500);
  if (!data) return json({ error: "Not found" }, 404);
  return json({ post: data });
}

async function createPost(body: Body, adminId: string, req: Request): Promise<Response> {
  const post = body.post;
  if (!post?.content) return json({ error: "content required" }, 400);

  const plat = validatePlatforms(post.platforms);
  if (!plat.ok) return json({ error: plat.error }, 400);

  const { data, error } = await supabaseAdmin
    .from("social_posts")
    .insert({
      content: post.content,
      platforms: plat.platforms,
      status: post.status ?? "draft",
      scheduled_at: post.scheduled_at ?? null,
      media_urls: post.media_urls ?? [],
      link_url: post.link_url ?? null,
      author_id: adminId,
    })
    .select()
    .single();

  if (error) return json({ error: error.message }, 500);
  await logAdminAction(adminId, "social.create", { resourceType: "social_post", resourceId: data.id, req });
  return json({ post: data });
}

async function updatePost(body: Body, adminId: string, req: Request): Promise<Response> {
  if (!body.id) return json({ error: "id required" }, 400);
  const post = body.post;
  if (!post) return json({ error: "post body required" }, 400);

  const patch: Record<string, unknown> = {};
  if (post.content !== undefined) patch.content = post.content;
  if (post.platforms !== undefined) {
    const plat = validatePlatforms(post.platforms);
    if (!plat.ok) return json({ error: plat.error }, 400);
    patch.platforms = plat.platforms;
  }
  if (post.status !== undefined) patch.status = post.status;
  if (post.scheduled_at !== undefined) patch.scheduled_at = post.scheduled_at;
  if (post.media_urls !== undefined) patch.media_urls = post.media_urls;
  if (post.link_url !== undefined) patch.link_url = post.link_url;

  const { data, error } = await supabaseAdmin
    .from("social_posts")
    .update(patch)
    .eq("id", body.id)
    .select()
    .single();
  if (error) return json({ error: error.message }, 500);

  await logAdminAction(adminId, "social.update", { resourceType: "social_post", resourceId: body.id, req });
  return json({ post: data });
}

async function deletePost(body: Body, adminId: string, req: Request): Promise<Response> {
  if (!body.id) return json({ error: "id required" }, 400);
  const { error } = await supabaseAdmin.from("social_posts").delete().eq("id", body.id);
  if (error) return json({ error: error.message }, 500);
  await logAdminAction(adminId, "social.delete", { resourceType: "social_post", resourceId: body.id, req });
  return json({ success: true });
}

async function publishPost(body: Body, adminId: string, req: Request): Promise<Response> {
  if (!body.id) return json({ error: "id required" }, 400);

  const webhookUrl = Deno.env.get("SOCIAL_WEBHOOK_URL");
  if (!webhookUrl || webhookUrl.trim() === "") {
    return json({ error: "SOCIAL_WEBHOOK_URL not configured" }, 500);
  }

  const { data: post, error: fetchErr } = await supabaseAdmin
    .from("social_posts")
    .select("*")
    .eq("id", body.id)
    .maybeSingle();
  if (fetchErr) return json({ error: fetchErr.message }, 500);
  if (!post) return json({ error: "Not found" }, 404);

  // Flip to publishing
  await supabaseAdmin
    .from("social_posts")
    .update({ status: "publishing", webhook_url: webhookUrl, webhook_error: null })
    .eq("id", body.id);

  const payload = {
    id: post.id,
    content: post.content,
    platforms: post.platforms,
    media_urls: post.media_urls,
    link_url: post.link_url,
    scheduled_at: post.scheduled_at,
    triggered_by: adminId,
    triggered_at: new Date().toISOString(),
  };

  const webhookSecret = Deno.env.get("SOCIAL_WEBHOOK_SECRET");
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (webhookSecret) headers["X-Webhook-Secret"] = webhookSecret;

  let webhookResponse: unknown = null;
  let webhookError: string | null = null;
  let okStatus = false;

  try {
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), 30_000);
    const res = await fetch(webhookUrl, {
      method: "POST",
      headers,
      body: JSON.stringify(payload),
      signal: ctrl.signal,
    });
    clearTimeout(timer);

    const text = await res.text();
    try {
      webhookResponse = text ? JSON.parse(text) : { status: res.status };
    } catch {
      webhookResponse = { status: res.status, text: text.slice(0, 2000) };
    }

    if (!res.ok) webhookError = `Webhook returned ${res.status}`;
    okStatus = res.ok;
  } catch (err) {
    webhookError = err instanceof Error ? err.message : String(err);
  }

  const postUrls = extractPostUrls(webhookResponse);
  const update: Record<string, unknown> = {
    status: okStatus ? "posted" : "failed",
    webhook_response: webhookResponse,
    webhook_error: webhookError,
  };
  if (okStatus) update.posted_at = new Date().toISOString();
  if (postUrls) update.post_urls = postUrls;

  const { data: updated, error: updateErr } = await supabaseAdmin
    .from("social_posts")
    .update(update)
    .eq("id", body.id)
    .select()
    .single();

  await logAdminAction(adminId, okStatus ? "social.publish" : "social.publish_failed", {
    resourceType: "social_post",
    resourceId: body.id,
    metadata: { webhook_error: webhookError },
    req,
  });

  if (updateErr) return json({ error: updateErr.message }, 500);
  if (!okStatus) return json({ error: webhookError || "Publish failed", post: updated }, 502);

  return json({ post: updated });
}

/**
 * If Make returns a JSON body containing URLs keyed by platform, surface them.
 * Shape is lenient: { post_urls: { twitter: "..." } } or { twitter: "..." }.
 */
function extractPostUrls(response: unknown): Record<string, string> | null {
  if (!response || typeof response !== "object") return null;
  const obj = response as Record<string, unknown>;
  if (obj.post_urls && typeof obj.post_urls === "object") {
    return obj.post_urls as Record<string, string>;
  }
  const urls: Record<string, string> = {};
  for (const key of Object.keys(obj)) {
    if (ALLOWED_PLATFORMS.has(key) && typeof obj[key] === "string") {
      urls[key] = obj[key] as string;
    }
  }
  return Object.keys(urls).length > 0 ? urls : null;
}
