/**
 * /generate-next-article — Make.com-invoked blog generator.
 *
 * Thin wrapper around shared/blog-generator.ts. Auth happens in server.ts via
 * the X-Webhook-Secret → BLOG_GENERATION_WEBHOOK_SECRET check; by the time we
 * get here the request is already trusted.
 *
 * Request body (all optional):
 *   { "topic": "optional fallback topic hint", "skip_bank": false }
 *
 * Response (200):
 *   { source, post_id, slug, title, excerpt, url, content_html,
 *     topic_rationale, remaining_pending, ai_meta }
 */

import { generateAndPublishNext } from "../../shared/blog-generator.ts";
import { AiError } from "../../shared/ai.ts";
import { logError } from "../../shared/logger.ts";
import type { AuthResult } from "../../shared/auth.ts";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

interface RequestBody {
  topic?: string;
  skip_bank?: boolean;
}

export async function handleGenerateNextArticle(req: Request, _auth: AuthResult): Promise<Response> {
  let body: RequestBody = {};
  try {
    body = await req.json();
  } catch {
    body = {};
  }

  try {
    const result = await generateAndPublishNext({
      explicitTopic: body.topic,
      skipBank: body.skip_bank === true,
    });
    return json(result);
  } catch (err) {
    if (err instanceof AiError) {
      return json({ error: err.message }, err.status && err.status >= 400 && err.status < 600 ? err.status : 502);
    }
    logError("generate-next-article failed", err, {});
    return json({ error: "Generation failed", details: err instanceof Error ? err.message : String(err) }, 500);
  }
}
