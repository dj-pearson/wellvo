import { competitors } from '../src/data/competitors'
import { whatToDoPages } from '../src/data/whatToDo'
import { fetchBlogForPrerender } from './fetchBlogForPrerender'

// URLs Vike prerenders to real HTML at build time. Every prerendered URL
// becomes dist/client/{path}/index.html after build, and scripts/generate-
// sitemap.mjs walks that output to build sitemap.xml — so being listed here
// is what puts a page in the sitemap.
//
// Blog posts are prerendered too (US-WEB008). Each blog URL carries its post
// in pageContext so the React tree can render it synchronously during SSR
// instead of waiting on a client-side useEffect that never runs on the server.
// Vike serializes that pageContext into the HTML and hands it back on the
// client, which is what keeps hydration consistent.
//
// Admin surfaces stay client-only: they are robots-disallowed and behind auth.
export default async function onBeforePrerenderStart() {
  const staticPaths = [
    '/',
    '/pricing',
    '/elderly-care',
    '/child-safety',
    '/check-in-app-for-elderly',
    '/daily-check-in-app-for-seniors',
    '/peace-of-mind-app-for-elderly-parents',
    '/welfare-check-on-elderly-parent',
    '/privacy',
    '/terms',
    '/support',
    '/accessibility',
    '/cookies',
    '/dmca',
    '/compare',
    '/admin/login',
  ]

  const comparePaths = competitors.map((c) => `/compare/daily-ok-vs-${c.slug}`)

  const whatToDoPaths = ['/what-to-do', ...whatToDoPages.map((p) => `/what-to-do/${p.slug}`)]

  // Never throws — a blog outage degrades to an empty list rather than
  // failing the deploy. See fetchBlogForPrerender.ts.
  const blog = await fetchBlogForPrerender()

  const blogIndexEntry = {
    url: '/blog',
    pageContext: { blogIndex: blog.index },
  }

  const blogPostEntries = [...blog.posts.values()].map((post) => ({
    url: `/blog/${post.slug}`,
    pageContext: { blogPost: post },
  }))

  return [
    ...staticPaths,
    ...comparePaths,
    ...whatToDoPaths,
    blogIndexEntry,
    ...blogPostEntries,
  ]
}
