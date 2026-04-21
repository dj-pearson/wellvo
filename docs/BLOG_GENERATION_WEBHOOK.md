# Automated Blog Generation — Make.com Webhook Contract

`/generate-next-article` is a webhook-authenticated edge function that pops the
next title from `blog_title_bank`, drafts a full article through the shared AI
client, and publishes it to `blog_posts` with `status='published'`. When the
title bank is empty, it falls back to the cluster bank in
`blog_generation_config` and generates a fresh, non-competing topic.

The public site (`website/src/pages/Blog.tsx`) queries `blog_posts` directly
via the Supabase client on every page load, so **newly published articles
appear under `/blog` immediately — no rebuild or deploy is needed**.

---

## Endpoint

| Field  | Value                                          |
| ------ | ---------------------------------------------- |
| URL    | `https://functions.dailyok.net/generate-next-article` |
| Method | `POST`                                         |
| Auth   | `X-Webhook-Secret` header                      |

### Required headers

```
Content-Type: application/json
X-Webhook-Secret: <value of BLOG_GENERATION_WEBHOOK_SECRET>
```

### Request body

The body is optional. Send an empty JSON object on normal invocations:

```json
{}
```

Two optional fields are accepted:

| Field       | Type    | Purpose                                                     |
| ----------- | ------- | ----------------------------------------------------------- |
| `topic`     | string  | Nudge the fallback generator toward a specific angle. Ignored when a bank row was claimed. |
| `skip_bank` | boolean | Bypass `blog_title_bank` entirely and go straight to fallback. Useful for testing fallback without draining the queue. |

### Response (200)

```json
{
  "source": "blog_title_bank",
  "post_id": "5e6b…",
  "slug": "how-often-should-you-check-on-an-aging-parent",
  "title": "How Often Should You Check On an Aging Parent?",
  "excerpt": "…",
  "url": "https://dailyok.net/blog/how-often-should-you-check-on-an-aging-parent",
  "content_html": "<blockquote>…</blockquote><h2>…</h2>…",
  "remaining_pending": 29,
  "ai_meta": {
    "source": "blog_title_bank",
    "title_bank_id": "…",
    "cluster": "jtbd",
    "provider": "anthropic",
    "model": "claude-sonnet-4-6",
    "input_tokens": 1842,
    "output_tokens": 3650,
    "generated_at": "2026-04-21T14:22:11.000Z"
  }
}
```

`source` is either `"blog_title_bank"` (a curated row was claimed) or
`"fallback"` (cluster-bank pick, includes a `topic_rationale` field).

### Error responses

| Status | Body                                         | Meaning                                     |
| ------ | -------------------------------------------- | ------------------------------------------- |
| 401    | `{ "error": "Unauthorized" }`                | Missing or wrong `X-Webhook-Secret`         |
| 429    | `{ "error": "Too many requests" }`           | Service-role rate limit hit                 |
| 500    | `{ "error": "Generation config not found" }` | Migration 00024 hasn't been applied         |
| 500    | `{ "error": "Generation failed", … }`        | DB or validation failure after claim        |
| 502    | `{ "error": "Anthropic 529: …" }`            | Upstream AI provider error; safe to retry   |

On any post-claim failure the bank row is marked `status='failed'` with the
error stored in `last_error`. Flip it back to `pending` in the admin UI to
retry.

---

## Environment variables (Coolify Team Shared Variables)

Already present from the existing blog AI flow — no new provider config needed:

| Variable                         | Purpose                                     |
| -------------------------------- | ------------------------------------------- |
| `AI_DEFAULT_PROVIDER`            | `anthropic` (preferred) or `openai`         |
| `ANTHROPIC_API_KEY`              | Anthropic key                               |
| `OPENAI_GLOBAL_API`              | OpenAI key (fallback)                       |
| `DEFAULT_AI_MODEL`               | e.g. `claude-sonnet-4-6`                    |
| `AI_ENABLE_CACHING`              | `true` to enable Anthropic system-prompt caching (recommended) |
| `AI_TIMEOUT_MS`                  | Default 60000 — bump to 120000 for long articles |

**New for this feature** — add these to Coolify:

| Variable                           | Required | Purpose                                                     |
| ---------------------------------- | -------- | ----------------------------------------------------------- |
| `BLOG_GENERATION_WEBHOOK_SECRET`   | yes      | Random 32+ char secret. Make.com sends it in `X-Webhook-Secret`. |
| `BLOG_GENERATION_AUTHOR_ID`        | no       | UUID of a `users` row to attribute posts to. Leave unset to store `author_id = NULL`. |
| `SITE_ORIGIN`                      | no       | Public site origin for the `url` in the response. Defaults to `https://dailyok.net`. |

---

## Make.com scenario

Minimum viable scenario — one HTTP module:

1. **Trigger** — scheduler (e.g., every 12 hours), webhook, or manual.
2. **HTTP > Make a request**:
   - URL: `https://functions.dailyok.net/generate-next-article`
   - Method: `POST`
   - Headers:
     - `Content-Type: application/json`
     - `X-Webhook-Secret: {{env.BLOG_GENERATION_WEBHOOK_SECRET}}`
   - Body type: `Raw`, Content type: `JSON (application/json)`, body: `{}`
   - Parse response: `Yes`
3. **Optional**: chain downstream modules that consume `post_id`, `slug`, `url`,
   or `content_html` (e.g., email the result, queue a social post, notify
   Slack).

### Stopping condition

When `remaining_pending` hits `0` the endpoint still produces articles (via
fallback). If you want Make.com to stop after the curated 30, add a filter
after the HTTP module: `remaining_pending > 0` OR `source = "blog_title_bank"`.

---

## Adding more titles to the bank

Insert rows into `blog_title_bank` via the Supabase SQL editor (or future
admin UI). Minimum shape:

```sql
INSERT INTO blog_title_bank
  (title, primary_keyword, secondary_keywords, cluster, intent_stage,
   format_hint, target_word_count, requires_medical_review, priority)
VALUES
  ('Your new title',
   'primary keyword',
   ARRAY['secondary one','secondary two'],
   'jtbd',            -- or comparison, teens, dementia, …
   'MOFU',            -- TOFU | MOFU | BOFU
   'Decision tree',
   1800,
   FALSE,             -- TRUE for YMYL (dementia, falls, welfare checks)
   50);
```

`priority` controls order — lower fires first. Setting a `priority` higher
than any existing row parks it at the end of the queue.

### Reviving failed rows

```sql
UPDATE blog_title_bank
SET status = 'pending', last_error = NULL, claimed_at = NULL
WHERE status = 'failed';
```

### Skipping a row

```sql
UPDATE blog_title_bank SET status = 'skipped' WHERE id = '…';
```

---

## Tuning voice, HTML rules, or the fallback cluster bank

Everything the model sees about the brand lives in the
`blog_generation_config` table (single row, `id = 1`). Edit the JSONB column
to change tone rules, pillar framing, the output contract, or the fallback
cluster bank.

Example — add a new cluster to fallback:

```sql
UPDATE blog_generation_config
SET config = jsonb_set(
  config,
  '{fallback,cluster_bank}',
  (config->'fallback'->'cluster_bank') ||
  jsonb_build_array(jsonb_build_object(
    'name','Medicare and insurance',
    'examples', jsonb_build_array(
      'Medicare Advantage daily check in benefit',
      'does Medicare cover check in services'
    )
  ))
)
WHERE id = 1;
```

---

## What happens after the curated 30 run out

1. `claim_next_blog_title()` returns `NULL`.
2. The edge function reads `blog_generation_config.config.fallback`, plus
   every already-published title.
3. The AI picks a fresh angle from the `cluster_bank` that doesn't duplicate
   anything already published, and returns the article plus a
   `topic_rationale` string naming the cluster + keyword it chose.
4. The article is published identically to a bank row.

To keep cadence and quality high, seed the bank with the next wave of titles
before the 30 run out — the fallback is designed as a safety net, not the
primary path. The `source` field in the response lets you monitor the mix.

---

## Manual test

Trigger a run from the server running the edge function:

```bash
curl -X POST https://functions.dailyok.net/generate-next-article \
  -H "Content-Type: application/json" \
  -H "X-Webhook-Secret: $BLOG_GENERATION_WEBHOOK_SECRET" \
  -d '{}'
```

Then open `https://dailyok.net/blog` — the new post is visible on the next
page load.
