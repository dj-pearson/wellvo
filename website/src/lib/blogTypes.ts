/**
 * Shared shapes for published blog content (US-WEB008).
 *
 * These were previously declared inline and separately in Blog.tsx and
 * BlogPost.tsx. They are shared now because the build-time prerender
 * fetcher (pages/fetchBlogForPrerender.ts) has to select exactly the same
 * columns the components read — a drift between the two silently produces
 * prerendered pages that are missing fields the client then re-fetches.
 */
import type { DOMPurify } from 'dompurify'

/** Columns the /blog index card needs. */
export interface PublicPostSummary {
  id: string
  slug: string
  title: string
  excerpt: string | null
  featured_image_url: string | null
  category: string | null
  tags: string[]
  published_at: string
}

/** Everything a single /blog/:slug page needs. */
export interface PublicPost extends PublicPostSummary {
  content_html: string
  og_image_url: string | null
  seo_title: string | null
  seo_description: string | null
  canonical_url: string | null
  updated_at: string | null
}

/** Column list for the index query — keep in sync with PublicPostSummary. */
export const POST_SUMMARY_COLUMNS =
  'id, slug, title, excerpt, featured_image_url, category, tags, published_at'

/** Column list for the single-post query — keep in sync with PublicPost. */
export const POST_COLUMNS =
  'id, slug, title, excerpt, content_html, featured_image_url, og_image_url, category, tags, seo_title, seo_description, canonical_url, published_at, updated_at'

/**
 * The allowlist applied to `content_html` before it reaches the DOM.
 *
 * Shared deliberately: the client sanitizes at render time via DOMPurify,
 * and the prerenderer sanitizes the same HTML at build time with the same
 * config (DOMPurify is a no-op under Node without a DOM, so prerendered
 * output would otherwise carry unsanitized author/LLM HTML straight into
 * static files). One config, two call sites.
 */
export const BLOG_HTML_ALLOWLIST = {
  ALLOWED_TAGS: [
    'h1', 'h2', 'h3', 'h4', 'p', 'ul', 'ol', 'li', 'strong', 'em', 'b', 'i',
    'a', 'blockquote', 'br', 'hr', 'img', 'code', 'pre', 'figure', 'figcaption',
  ],
  ALLOWED_ATTR: ['href', 'src', 'alt', 'title', 'rel', 'target'],
} as const

/** rel applied to every new-tab link in post bodies. */
export const BLOG_BLANK_TARGET_REL = 'noopener noreferrer nofollow ugc'

/**
 * Purifier instances that already carry the link hook. A WeakSet keyed on the
 * instance keeps registration idempotent across re-renders and HMR without
 * holding the instance alive.
 */
const hardened = new WeakSet<DOMPurify>()

/**
 * Registers an afterSanitizeAttributes hook so any `<a target="_blank">` that
 * survives the allowlist leaves with `rel="noopener noreferrer nofollow ugc"`.
 * The allowlist permits `target` and `rel` because authors use them, but post
 * bodies are author- and LLM-written, so the rel cannot be trusted to be
 * present or correct (reverse tabnabbing, and link equity to arbitrary sites).
 * Any author-supplied rel on such a link is replaced, not merged.
 *
 * Call it on every DOMPurify instance that sanitizes `content_html` — the
 * browser default instance in BlogPost.tsx and the jsdom-backed one in
 * pages/fetchBlogForPrerender.ts. Safe to call more than once per instance.
 */
export function hardenBlogLinks(purify: DOMPurify): DOMPurify {
  if (hardened.has(purify)) return purify
  purify.addHook('afterSanitizeAttributes', (node) => {
    // nodeName, not instanceof: the prerender instance runs against jsdom's
    // window, whose Element is not this realm's Element.
    if (node.nodeName !== 'A') return
    const el = node as Element
    if ((el.getAttribute('target') ?? '').toLowerCase() === '_blank') {
      el.setAttribute('rel', BLOG_BLANK_TARGET_REL)
    }
  })
  hardened.add(purify)
  return purify
}
