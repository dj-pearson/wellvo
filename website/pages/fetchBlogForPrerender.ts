/**
 * Build-time blog fetch for prerendering (US-WEB008).
 *
 * Server-only: this module is imported exclusively by
 * +onBeforePrerenderStart.ts, which Vike runs in Node during `vike prerender`.
 * It must never be pulled into the client bundle — it imports jsdom.
 *
 * Why this exists: before US-WEB008 the blog was invisible to search engines.
 * Posts were fetched client-side only, never prerendered, never entered the
 * sitemap (which walks prerendered output), and `/blog/* / 200` in
 * public/_redirects served every post URL the *homepage's* prerendered HTML —
 * homepage title and homepage canonical included. Search Console recorded zero
 * /blog/* URLs across four months. See docs/SEARCH_CONSOLE_DIAGNOSIS.md §3.
 *
 * Failure policy: a blog outage must never fail a Cloudflare Pages build. Every
 * path here returns empty data and logs a warning rather than throwing, so a
 * deploy still ships the static marketing site.
 */
import { createClient } from '@supabase/supabase-js'
import createDOMPurify from 'dompurify'
import { JSDOM } from 'jsdom'
import {
  BLOG_HTML_ALLOWLIST,
  POST_COLUMNS,
  POST_SUMMARY_COLUMNS,
  type PublicPost,
  type PublicPostSummary,
} from '../src/lib/blogTypes'

export interface BlogPrerenderData {
  /** Newest-first list for the /blog index. */
  index: PublicPostSummary[]
  /** One entry per post, keyed by slug, with content_html already sanitized. */
  posts: Map<string, PublicPost>
}

const EMPTY: BlogPrerenderData = { index: [], posts: new Map() }

/** Matches the `.limit(100)` the /blog index has always used. */
const MAX_POSTS = 100

/**
 * DOMPurify needs a real DOM. Under Node it sets isSupported = false and
 * `sanitize()` returns its input untouched, which would put unsanitized
 * author- and LLM-authored HTML into static files. jsdom gives it a window so
 * the build applies the same allowlist the browser does.
 */
function makeSanitizer(): (html: string) => string {
  try {
    const { window } = new JSDOM('')
    const purify = createDOMPurify(window as unknown as Window & typeof globalThis)
    if (!purify.isSupported) throw new Error('DOMPurify reports isSupported = false')
    return (html: string) =>
      purify.sanitize(html, {
        ALLOWED_TAGS: [...BLOG_HTML_ALLOWLIST.ALLOWED_TAGS],
        ALLOWED_ATTR: [...BLOG_HTML_ALLOWLIST.ALLOWED_ATTR],
      })
  } catch (err) {
    // Refuse to emit unsanitized HTML. Dropping the body is recoverable (the
    // client re-fetches and sanitizes); shipping raw HTML is not.
    console.warn(
      `[blog-prerender] sanitizer unavailable (${(err as Error).message}); ` +
        'post bodies will be omitted from prerendered HTML and fetched client-side instead',
    )
    return () => ''
  }
}

export async function fetchBlogForPrerender(): Promise<BlogPrerenderData> {
  const url = process.env.VITE_SUPABASE_URL
  const anonKey = process.env.VITE_SUPABASE_ANON_KEY

  if (!url || !anonKey) {
    console.warn(
      '[blog-prerender] VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY not set; ' +
        'skipping blog prerender. Blog posts will not be in the sitemap for this build.',
    )
    return EMPTY
  }

  // Anon key only, against the public published-posts RLS policy. A service
  // role key must never appear in a build that emits static files.
  const supabase = createClient(url, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  })

  const nowIso = new Date().toISOString()

  try {
    // Same filter as src/pages/BlogPost.tsx and src/pages/Blog.tsx: published,
    // and not scheduled into the future.
    const { data, error } = await supabase
      .from('blog_posts')
      .select(POST_COLUMNS)
      .eq('status', 'published')
      .lte('published_at', nowIso)
      .order('published_at', { ascending: false })
      .limit(MAX_POSTS)

    if (error) {
      console.warn(`[blog-prerender] query failed: ${error.message}; skipping blog prerender`)
      return EMPTY
    }

    const rows = (data ?? []) as PublicPost[]
    if (rows.length === 0) {
      console.log('[blog-prerender] no published posts found')
      return EMPTY
    }

    const sanitize = makeSanitizer()
    const posts = new Map<string, PublicPost>()
    const index: PublicPostSummary[] = []

    for (const row of rows) {
      if (!row.slug) continue
      posts.set(row.slug, {
        ...row,
        tags: row.tags ?? [],
        content_html: sanitize(row.content_html ?? ''),
      })
      index.push({
        id: row.id,
        slug: row.slug,
        title: row.title,
        excerpt: row.excerpt,
        featured_image_url: row.featured_image_url,
        category: row.category,
        tags: row.tags ?? [],
        published_at: row.published_at,
      })
    }

    console.log(`[blog-prerender] ${posts.size} published posts will be prerendered`)
    return { index, posts }
  } catch (err) {
    console.warn(
      `[blog-prerender] unexpected failure: ${(err as Error).message}; skipping blog prerender`,
    )
    return EMPTY
  }
}

/** Column list re-exported so the index query stays greppable from one place. */
export { POST_SUMMARY_COLUMNS }
