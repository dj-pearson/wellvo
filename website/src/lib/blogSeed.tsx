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
import type { ReactNode } from 'react'
import { BlogSeedContext, type BlogSeed } from './blogSeedContext'

export function BlogSeedProvider({
  seed,
  children,
}: {
  seed: BlogSeed
  children: ReactNode
}) {
  return <BlogSeedContext.Provider value={seed}>{children}</BlogSeedContext.Provider>
}
