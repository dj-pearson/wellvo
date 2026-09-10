/**
 * SERP snippet length check over the prerendered output (US-SEO009).
 *
 * Google renders roughly 580px of title and 920px of description before
 * truncating; ~60 and ~160 characters are the usual character-count proxies.
 * Overshoot is invisible everywhere except the search result itself — the page
 * looks fine, the tag is valid, and the sentence people actually read is cut
 * off mid-clause. Descriptions on this site ran to 407 characters before
 * US-SEO008/009.
 *
 * Reads the emitted HTML rather than the source, for two reasons: it is what
 * crawlers read, and the length has to be measured on the UNESCAPED text —
 * `&#x27;` is six characters in the file and one on screen, so measuring the
 * raw attribute overstates every apostrophe by five.
 *
 * Blog posts are reported but never fail the check: their metadata comes from
 * post rows written through the admin UI, so a long excerpt is a content
 * decision to fix in the CMS, not a reason to block a deploy. (In CI there is
 * no Supabase config, so no blog posts are prerendered at all.)
 */
import { readFileSync, readdirSync, statSync } from 'fs'
import { join, dirname, relative } from 'path'
import { fileURLToPath } from 'url'

const __dirname = dirname(fileURLToPath(import.meta.url))
const distClient = join(__dirname, '..', 'dist', 'client')

const TITLE_MAX = 60
const DESCRIPTION_MAX = 160
const NOINDEX_PREFIXES = ['/admin']

function walk(dir, acc = []) {
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry)
    if (statSync(full).isDirectory()) walk(full, acc)
    else if (entry === 'index.html') acc.push(full)
  }
  return acc
}

/** Decode the handful of entities React's renderer emits into attributes. */
function unescapeHtml(s) {
  return s
    .replace(/&#x27;|&#39;/g, "'")
    .replace(/&quot;|&#34;/g, '"')
    .replace(/&amp;|&#38;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&#x2F;/g, '/')
}

const NOINDEX_RE = /<meta[^>]+name=["']robots["'][^>]*content=["'][^"']*noindex[^"']*["']/i

let failures = 0
let warnings = 0
let checked = 0

for (const file of walk(distClient).sort()) {
  const rel = relative(distClient, dirname(file)).split(/[\\/]/).join('/')
  const route = rel === '' ? '/' : `/${rel}/`
  const html = readFileSync(file, 'utf8')

  if (NOINDEX_PREFIXES.some((p) => route.startsWith(p)) || NOINDEX_RE.test(html)) continue

  const titleMatch = /<title>([\s\S]*?)<\/title>/i.exec(html)
  const descMatch = /<meta\s+name="description"\s+content="([\s\S]*?)"\s*\/?>/i.exec(html)

  const problems = []
  if (!titleMatch) problems.push('no <title>')
  if (!descMatch) problems.push('no meta description')

  const title = titleMatch ? unescapeHtml(titleMatch[1]) : ''
  const description = descMatch ? unescapeHtml(descMatch[1]) : ''
  if (title.length > TITLE_MAX) problems.push(`title ${title.length} > ${TITLE_MAX}`)
  if (description.length > DESCRIPTION_MAX)
    problems.push(`description ${description.length} > ${DESCRIPTION_MAX}`)

  checked++
  if (problems.length === 0) continue

  // Blog metadata is authored in the CMS; report it, do not block the deploy.
  const isBlogPost = route.startsWith('/blog/')
  if (isBlogPost) {
    warnings++
    console.warn(`[snippets] warn  ${route} — ${problems.join('; ')}`)
  } else {
    failures++
    console.error(`[snippets] FAIL  ${route} — ${problems.join('; ')}`)
  }
}

console.log(
  `[snippets] checked ${checked} indexable route(s): ${failures} failure(s), ${warnings} warning(s)`,
)

if (checked === 0) {
  console.error('[snippets] no routes checked — did the prerender run?')
  process.exit(1)
}
process.exit(failures > 0 ? 1 : 0)
