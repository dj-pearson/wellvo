/**
 * Heading-outline check over the prerendered output (US-SEO014).
 *
 * A document outline is what a screen reader navigates by and what an
 * extractor uses to decide which passage answers a query. Skipping a level
 * breaks both, and it is invisible on screen because the styling comes from
 * the container class, not from the tag.
 *
 * Every page on this site skipped h2 -> h4, because the footer's four column
 * headings were h4. Several landing pages skipped again mid-content, where
 * card headings inside an h2 section were also h4.
 *
 * Asserts three things per indexable page: exactly one h1, that it comes
 * first, and that no level is skipped on the way down.
 */
import { readFileSync, readdirSync, statSync } from 'fs'
import { join, dirname, relative } from 'path'
import { fileURLToPath } from 'url'

const __dirname = dirname(fileURLToPath(import.meta.url))
const distClient = join(__dirname, '..', 'dist', 'client')
const NOINDEX_RE = /<meta[^>]+name=["']robots["'][^>]*content=["'][^"']*noindex[^"']*["']/i

function walk(dir, acc = []) {
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry)
    if (statSync(full).isDirectory()) walk(full, acc)
    else if (entry === 'index.html') acc.push(full)
  }
  return acc
}

let failures = 0
let checked = 0

for (const file of walk(distClient).sort()) {
  const rel = relative(distClient, dirname(file)).split(/[\\/]/).join('/')
  const route = rel === '' ? '/' : `/${rel}/`
  if (route.startsWith('/admin')) continue

  const html = readFileSync(file, 'utf8')
  if (NOINDEX_RE.test(html)) continue

  const levels = [...html.matchAll(/<h([1-6])[^>]*>([\s\S]*?)<\/h\1>/g)].map((m) => ({
    level: Number(m[1]),
    text: m[2].replace(/<[^>]+>/g, '').trim().slice(0, 50),
  }))

  const problems = []
  if (levels.length === 0) {
    problems.push('no headings')
  } else {
    const h1s = levels.filter((h) => h.level === 1)
    if (h1s.length !== 1) problems.push(`${h1s.length} h1 elements`)
    if (levels[0].level !== 1) problems.push(`outline starts at h${levels[0].level}`)
    let prev = levels[0].level
    for (const h of levels.slice(1)) {
      if (h.level > prev + 1) problems.push(`h${prev} -> h${h.level} at "${h.text}"`)
      prev = h.level
    }
  }

  checked++
  if (problems.length) {
    failures++
    console.error(`[headings] FAIL  ${route} — ${problems.join('; ')}`)
  }
}

console.log(`[headings] checked ${checked} indexable route(s): ${failures} failure(s)`)
if (checked === 0) {
  console.error('[headings] no routes checked — did the prerender run?')
  process.exit(1)
}
process.exit(failures > 0 ? 1 : 0)
