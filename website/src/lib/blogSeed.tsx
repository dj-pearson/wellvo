/**
 * Prerender seed for blog data (US-WEB008).
 *
 * The blog is Supabase-backed and was previously fetched only in a
 * `useEffect`, which never runs during server rendering — so prerendered
 * blog HTML was empty and search engines saw nothing. The prerenderer now
 * fetches posts at build time (pages/fetchBlogForPrerender.ts) and hands
 * them to the React tree through this context.
 *
 * Both renderers provide it:
 *  - +onRenderHtml.tsx  reads pageContext during prerender
 *  - +onRenderClient.tsx reads the same pageContext, which Vike serializes
 *    into the HTML, so the client's first render matches the server's and
 *    hydration stays consistent.
 *
 * On a client-side route change (or for a post published since the last
 * build) the seed is absent and the components fall back to fetching, which
 * is the behaviour that existed before this story.
 */
import { createContext, useContext, type ReactNode } from 'react'
import type { PublicPost, PublicPostSummary } from './blogTypes'

export interface BlogSeed {
  /** Seeded list for the /blog index, or null when not prerendered. */
  blogIndex: PublicPostSummary[] | null
  /** Seeded single post for /blog/:slug, or null when not prerendered. */
  blogPost: PublicPost | null
}

const EMPTY_SEED: BlogSeed = { blogIndex: null, blogPost: null }

const BlogSeedContext = createContext<BlogSeed>(EMPTY_SEED)

export function BlogSeedProvider({
  seed,
  children,
}: {
  seed: BlogSeed
  children: ReactNode
}) {
  return <BlogSeedContext.Provider value={seed}>{children}</BlogSeedContext.Provider>
}

export function useBlogSeed(): BlogSeed {
  return useContext(BlogSeedContext)
}

/**
 * Narrow an unknown pageContext into a BlogSeed. Vike round-trips this
 * through JSON, so anything absent or malformed becomes null and the
 * component falls back to fetching rather than rendering a broken page.
 */
export function seedFromPageContext(pageContext: unknown): BlogSeed {
  const ctx = (pageContext ?? {}) as Record<string, unknown>
  const blogIndex = Array.isArray(ctx.blogIndex)
    ? (ctx.blogIndex as PublicPostSummary[])
    : null
  const raw = ctx.blogPost
  const blogPost =
    raw && typeof raw === 'object' && typeof (raw as PublicPost).slug === 'string'
      ? (raw as PublicPost)
      : null
  return { blogIndex, blogPost }
}
