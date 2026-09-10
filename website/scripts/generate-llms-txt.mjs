/**
 * Build-time llms.txt generator (US-SEO011).
 *
 * llms.txt is the manifest handed to AI crawlers, and it was hand-maintained.
 * It had drifted badly: 18 of 33 indexable routes listed, and the 15 missing
 * ones were the whole point of the pSEO plan — seven of the ten comparison
 * pages, plus the entire "doesn't answer the phone" cluster and
 * /welfare-check-on-elderly-parent. The file even carried a comment saying
 * those guides were "not yet built" long after US-WEB005 built them. Every URL
 * in it was also written in the no-slash form, which production 308s
 * (US-WEB010) — so an agent that does not follow redirects got nothing.
 *
 * The fix is to stop hand-maintaining it. This walks the same prerendered
 * output the sitemap generator walks, so a page cannot be published without
 * appearing here, and reads each page's own <title> and meta description, so
 * the blurbs cannot drift from what the page actually says.
 *
 * Runs after `vike prerender`, writing over the copy Vite already staged from
 * public/. Blog posts are deliberately excluded: they change between builds
 * without a redeploy (docs/BLOG_GENERATION_WEBHOOK.md), so a build-time list of
 * them would be wrong the moment it shipped — /blog is listed instead.
 */
import { readFileSync, writeFileSync, readdirSync, statSync } from 'fs'
import { join, dirname, relative } from 'path'
import { fileURLToPath } from 'url'

const __dirname = dirname(fileURLToPath(import.meta.url))
const distClient = join(__dirname, '..', 'dist', 'client')
const SITE_ORIGIN = 'https://dailyok.net'

/**
 * The canonical entity description. Hand-written, and deliberately identical
 * to the block at the top of public/llms-full.txt — until the Wikidata /
 * Crunchbase / G2 / Capterra profiles exist (pSEO.md §7), this is the source of
 * truth for how Daily OK describes itself, so the two must not drift.
 */
const PREAMBLE = `# Daily OK — Senior Check-In App

> Daily OK is a senior check-in app. An adult child sets up a once-a-day "I'm OK"
> for an aging parent, who taps one large button (or replies straight from the
> notification). If the parent misses the check-in, Daily OK fires escalating alerts
> to a chosen circle of family members. No pendant, no GPS tracking, no cameras, no
> wearables — presence without surveillance. The same gentle daily check-in also
> works for teens and any loved one you worry about. Plans run $3.99–$9.99 per month
> with a free trial. Available on iOS and Android.

This file is generated from the site's prerendered pages at build time, so it
cannot list a page that does not exist or omit one that does. Full long-form
content: ${SITE_ORIGIN}/llms-full.txt
`

/** Section order and membership. First matching rule wins. */
const SECTIONS = [
  { name: 'Core pages (senior check-in)', match: (r) => ['/', '/check-in-app-for-elderly/', '/daily-check-in-app-for-seniors/', '/peace-of-mind-app-for-elderly-parents/', '/elderly-care/', '/pricing/', '/support/'].includes(r) },
  { name: 'Secondary use cases', match: (r) => r === '/child-safety/' },
  { name: 'Comparisons', match: (r) => r.startsWith('/compare') },
  { name: 'What to do when someone does not answer the phone', match: (r) => r.startsWith('/what-to-do') || r === '/welfare-check-on-elderly-parent/' },
  { name: 'More', match: () => true },
]

const NOINDEX_RE = /<meta[^>]+name=["']robots["'][^>]*content=["'][^"']*noindex[^"']*["']/i

function walk(dir, acc = []) {
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry)
    if (statSync(full).isDirectory()) walk(full, acc)
    else if (entry === 'index.html') acc.push(full)
  }
  return acc
}

function unescapeHtml(s) {
  return s
    .replace(/&#x27;|&#39;/g, "'")
    .replace(/&quot;|&#34;/g, '"')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&#x2F;/g, '/')
    .replace(/&amp;|&#38;/g, '&')
}

const entries = []
for (const file of walk(distClient)) {
  const rel = relative(distClient, dirname(file)).split(/[\\/]/).join('/')
  const route = rel === '' ? '/' : `/${rel}/`
  if (route.startsWith('/admin')) continue
  // Individual posts are omitted on purpose — see the header comment.
  if (route.startsWith('/blog/') && route !== '/blog/') continue

  const html = readFileSync(file, 'utf8')
  if (NOINDEX_RE.test(html)) continue

  const titleMatch = /<title>([\s\S]*?)<\/title>/i.exec(html)
  const descMatch = /<meta\s+name="description"\s+content="([\s\S]*?)"\s*\/?>/i.exec(html)
  if (!titleMatch) continue

  // Strip the brand suffix; the file already says whose site this is.
  const title = unescapeHtml(titleMatch[1]).replace(/\s*\|\s*Daily OK\s*$/, '')
  const description = descMatch ? unescapeHtml(descMatch[1]) : ''
  entries.push({ route, title, description })
}

entries.sort((a, b) => a.route.localeCompare(b.route))

const grouped = new Map(SECTIONS.map((s) => [s.name, []]))
for (const e of entries) {
  const section = SECTIONS.find((s) => s.match(e.route))
  grouped.get(section.name).push(e)
}

let out = PREAMBLE
for (const { name } of SECTIONS) {
  const list = grouped.get(name)
  if (list.length === 0) continue
  out += `\n## ${name}\n`
  for (const e of list) {
    const suffix = e.description ? `: ${e.description}` : ''
    out += `- [${e.title}](${SITE_ORIGIN}${e.route})${suffix}\n`
  }
}

writeFileSync(join(distClient, 'llms.txt'), out)
console.log(`[llms] wrote dist/client/llms.txt with ${entries.length} pages across ${[...grouped.values()].filter((l) => l.length).length} sections`)
