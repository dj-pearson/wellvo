import { competitors } from '../src/data/competitors'
import { whatToDoPages } from '../src/data/whatToDo'

// URLs Vike prerenders to real HTML at build time. Dynamic data-driven
// routes (blog posts, admin, blog index) are deliberately omitted — they
// fall through to the SPA at runtime via the `/* /index.html 200` rule in
// public/_redirects.
//
// Every prerendered URL becomes dist/client/{path}/index.html after build.
export default async function onBeforePrerenderStart() {
  const staticPaths = [
    '/',
    '/pricing',
    '/elderly-care',
    '/child-safety',
    '/check-in-app-for-elderly',
    '/daily-check-in-app-for-seniors',
    '/peace-of-mind-app-for-elderly-parents',
    '/privacy',
    '/terms',
    '/support',
    '/accessibility',
    '/cookies',
    '/dmca',
    '/compare',
    '/blog',
    '/admin/login',
  ]

  const comparePaths = competitors.map((c) => `/compare/daily-ok-vs-${c.slug}`)

  const whatToDoPaths = ['/what-to-do', ...whatToDoPages.map((p) => `/what-to-do/${p.slug}`)]

  return [...staticPaths, ...comparePaths, ...whatToDoPaths]
}
