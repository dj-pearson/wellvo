/**
 * Build-time sitemap generator (US-WEB007).
 *
 * Vike 0.4.258 has no `onPrerenderEnd` hook, so the "equivalent" per the
 * story AC is this post-prerender step in the build pipeline. It runs AFTER
 * `vike prerender` and walks the actual emitted dist/client/**\/index.html
 * — i.e. the canonical final URL list — rather than a hand-maintained file.
 *
 * Behaviour:
 *  - <loc> from the prerendered path, <lastmod> from `git log` of the route's
 *    source file (fallback: latest commit touching website/, then today),
 *    plus heuristic <changefreq>/<priority> by section. Blog posts are the
 *    exception: their <lastmod> comes from the post's own updated_at /
 *    published_at, read from the pageContext Vike emits beside each one
 *    (US-WEB009) — a git date would just be "when Blog.tsx last changed".
 *  - A route opts OUT of the sitemap if its prerendered HTML carries a
 *    `<meta name="robots" content="...noindex...">` tag, or if its path
 *    matches NOINDEX_PREFIXES (admin surfaces). Any page can therefore
 *    exclude itself just by emitting a noindex robots meta (e.g. via SEO
 *    component / Helmet) — the +config.ts-flag equivalent.
 *  - If the indexable URL count exceeds SITEMAP_SPLIT_THRESHOLD (500) the
 *    output is a sitemap index (sitemap.xml → sitemap-core.xml,
 *    sitemap-pseo.xml, sitemap-blog.xml); otherwise a single sitemap.xml.
 */
import { readFileSync, writeFileSync, readdirSync, statSync, existsSync } from 'fs'
import { join, dirname, relative } from 'path'
import { fileURLToPath } from 'url'
import { execSync } from 'child_process'

const __dirname = dirname(fileURLToPath(import.meta.url))
const websiteDir = join(__dirname, '..')
const distClient = join(websiteDir, 'dist', 'client')

const SITE_ORIGIN = 'https://dailyok.net'
const SITEMAP_SPLIT_THRESHOLD = 500
const NOINDEX_PREFIXES = ['/admin']

// Best-effort route → source file map for accurate <lastmod>. Routes not
// listed fall back to the latest commit touching website/src or pages/.
const ROUTE_SOURCE = {
  '/': 'src/pages/Home.tsx',
  '/pricing': 'src/pages/Pricing.tsx',
  '/support': 'src/pages/Support.tsx',
  '/elderly-care': 'src/pages/ElderlyCare.tsx',
  '/child-safety': 'src/pages/ChildSafety.tsx',
  '/check-in-app-for-elderly': 'src/pages/CheckInAppForElderly.tsx',
  '/daily-check-in-app-for-seniors': 'src/pages/DailyCheckInAppForSeniors.tsx',
  '/peace-of-mind-app-for-elderly-parents': 'src/pages/PeaceOfMindAppForElderlyParents.tsx',
  '/compare': 'src/pages/Compare.tsx',
  '/what-to-do': 'src/data/whatToDo.ts',
  '/blog': 'src/pages/Blog.tsx',
  '/privacy': 'src/pages/Privacy.tsx',
  '/terms': 'src/pages/Terms.tsx',
  '/accessibility': 'src/pages/Accessibility.tsx',
  '/cookies': 'src/pages/Cookies.tsx',
  '/dmca': 'src/pages/DMCA.tsx',
}

function gitDate(relPath) {
  try {
    const out = execSync(`git log -1 --format=%cs -- ${relPath}`, {
      cwd: websiteDir,
      stdio: ['ignore', 'pipe', 'ignore'],
    })
      .toString()
      .trim()
    if (/^\d{4}-\d{2}-\d{2}$/.test(out)) return out
  } catch {
    /* not a git checkout, or path untracked — fall through */
  }
  return null
}

/**
 * Blog <lastmod> comes from the post itself, not from git (US-WEB009).
 *
 * Every prerendered blog post has an index.pageContext.json emitted beside it
 * by Vike, carrying the same `blogPost` the page rendered from. Reading it
 * keeps this script's "walk the emitted output" contract — no second Supabase
 * round-trip, and no separate manifest to drift out of sync.
 *
 * Falls back to the git date if the file is missing or unreadable, which is
 * what happens when a build runs without Supabase config.
 */
function blogLastmodFromPageContext(file) {
  const ctxFile = join(dirname(file), 'index.pageContext.json')
  if (!existsSync(ctxFile)) return null
  try {
    const ctx = JSON.parse(readFileSync(ctxFile, 'utf8'))
    const post = ctx?.blogPost ?? ctx?.pageContext?.blogPost
    const stamp = post?.updated_at || post?.published_at
    if (typeof stamp !== 'string') return null
    const day = stamp.slice(0, 10)
    return /^\d{4}-\d{2}-\d{2}$/.test(day) ? day : null
  } catch {
    return null
  }
}

const TODAY = new Date().toISOString().slice(0, 10)
const WEBSITE_FALLBACK_DATE =
  gitDate('src') || gitDate('pages') || TODAY

function lastmodFor(route, slug) {
  // Comparison pages are data-driven by src/data/competitors/<slug>.json.
  if (route.startsWith('/compare/daily-ok-vs-') && slug) {
    return gitDate(`src/data/competitors/${slug}.json`) || WEBSITE_FALLBACK_DATE
  }
  // /what-to-do/* pages are all driven by src/data/whatToDo.ts.
  if (route.startsWith('/what-to-do/')) {
    return gitDate('src/data/whatToDo.ts') || WEBSITE_FALLBACK_DATE
  }
  const src = ROUTE_SOURCE[route]
  if (src) return gitDate(src) || WEBSITE_FALLBACK_DATE
  return WEBSITE_FALLBACK_DATE
}

function metaFor(route) {
  if (route === '/') return { changefreq: 'weekly', priority: '1.0', group: 'core' }
  if (route.startsWith('/compare/daily-ok-vs-'))
    return { changefreq: 'monthly', priority: '0.8', group: 'pseo' }
  if (route.startsWith('/what-to-do/'))
    return { changefreq: 'monthly', priority: '0.8', group: 'pseo' }
  if (route.startsWith('/blog/'))
    return { changefreq: 'weekly', priority: '0.7', group: 'blog' }
  if (route === '/blog')
    return { changefreq: 'daily', priority: '0.7', group: 'core' }
  if (
    route === '/elderly-care' ||
    route === '/child-safety' ||
    route === '/check-in-app-for-elderly' ||
    route === '/daily-check-in-app-for-seniors' ||
    route === '/peace-of-mind-app-for-elderly-parents'
  )
    return { changefreq: 'monthly', priority: '0.9', group: 'core' }
  if (route === '/pricing' || route === '/compare' || route === '/what-to-do')
    return { changefreq: 'monthly', priority: '0.8', group: 'core' }
  if (route === '/support')
    return { changefreq: 'monthly', priority: '0.6', group: 'core' }
  if (route === '/accessibility')
    return { changefreq: 'monthly', priority: '0.5', group: 'core' }
  // Legal / misc.
  return { changefreq: 'yearly', priority: '0.4', group: 'core' }
}

function walkIndexHtml(dir, acc = []) {
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry)
    const st = statSync(full)
    if (st.isDirectory()) walkIndexHtml(full, acc)
    else if (entry === 'index.html') acc.push(full)
  }
  return acc
}

function routeFromFile(file) {
  const rel = relative(distClient, dirname(file)).split(/[\\/]/).join('/')
  return rel === '' ? '/' : `/${rel}`
}

const NOINDEX_RE = /<meta[^>]+name=["']robots["'][^>]*content=["'][^"']*noindex[^"']*["']/i

function isNoindex(route, html) {
  if (NOINDEX_PREFIXES.some((p) => route === p || route.startsWith(p + '/') || route === p + '/login' || route.startsWith(p))) {
    return true
  }
  return NOINDEX_RE.test(html)
}

function urlXml({ loc, lastmod, changefreq, priority }) {
  return [
    '  <url>',
    `    <loc>${loc}</loc>`,
    `    <lastmod>${lastmod}</lastmod>`,
    `    <changefreq>${changefreq}</changefreq>`,
    `    <priority>${priority}</priority>`,
    '  </url>',
  ].join('\n')
}

function urlsetDoc(entries) {
  return (
    '<?xml version="1.0" encoding="UTF-8"?>\n' +
    '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n' +
    entries.map(urlXml).join('\n') +
    '\n</urlset>\n'
  )
}

function sitemapIndexDoc(children) {
  return (
    '<?xml version="1.0" encoding="UTF-8"?>\n' +
    '<sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n' +
    children
      .map(
        (c) =>
          `  <sitemap>\n    <loc>${SITE_ORIGIN}/${c.name}</loc>\n    <lastmod>${c.lastmod}</lastmod>\n  </sitemap>`,
      )
      .join('\n') +
    '\n</sitemapindex>\n'
  )
}

// --- main ------------------------------------------------------------------

const files = walkIndexHtml(distClient)
const entries = []
let skipped = 0

for (const file of files) {
  const route = routeFromFile(file)
  const html = readFileSync(file, 'utf8')
  if (isNoindex(route, html)) {
    skipped++
    continue
  }
  const slug = route.startsWith('/compare/daily-ok-vs-')
    ? route.slice('/compare/daily-ok-vs-'.length)
    : null
  const meta = metaFor(route)
  const lastmod =
    (route.startsWith('/blog/') ? blogLastmodFromPageContext(file) : null) ??
    lastmodFor(route, slug)
  entries.push({
    loc: route === '/' ? `${SITE_ORIGIN}/` : `${SITE_ORIGIN}${route}`,
    lastmod,
    changefreq: meta.changefreq,
    priority: meta.priority,
    group: meta.group,
  })
}

entries.sort((a, b) => a.loc.localeCompare(b.loc))

if (entries.length > SITEMAP_SPLIT_THRESHOLD) {
  const groups = { core: [], pseo: [], blog: [] }
  for (const e of entries) groups[e.group].push(e)
  const children = []
  for (const [name, list] of Object.entries(groups)) {
    if (list.length === 0) continue
    const fileName = `sitemap-${name}.xml`
    writeFileSync(join(distClient, fileName), urlsetDoc(list))
    const newest = list.reduce((m, e) => (e.lastmod > m ? e.lastmod : m), '0000-00-00')
    children.push({ name: fileName, lastmod: newest })
  }
  writeFileSync(join(distClient, 'sitemap.xml'), sitemapIndexDoc(children))
  console.log(
    `[sitemap] ${entries.length} URLs (> ${SITEMAP_SPLIT_THRESHOLD}) → sitemap index: ${children
      .map((c) => c.name)
      .join(', ')}; skipped ${skipped} noindex`,
  )
} else {
  writeFileSync(join(distClient, 'sitemap.xml'), urlsetDoc(entries))
  console.log(
    `[sitemap] wrote dist/client/sitemap.xml with ${entries.length} URLs; skipped ${skipped} noindex`,
  )
}
