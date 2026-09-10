/**
 * Structured-data validation over the prerendered output (US-SEO015).
 *
 * "It parses" is not validation. These checks are the ones that caught real
 * defects on this site: Article nodes with no image, pages carrying two
 * Organization nodes describing the same company, and — introduced and then
 * caught during US-SEO015 itself — one @id asserting two different names,
 * which reads fine in a diff and only surfaces when the graph is resolved.
 */
import { readFileSync, readdirSync, statSync } from 'fs'
import { join, dirname, relative } from 'path'
import { fileURLToPath } from 'url'

const __dirname = dirname(fileURLToPath(import.meta.url))
const distClient = join(__dirname, '..', 'dist', 'client')
const NOINDEX_RE = /<meta[^>]+name=["']robots["'][^>]*content=["'][^"']*noindex[^"']*["']/i
const HEADLINE_MAX = 110
const ARTICLE_REQUIRED = ['headline', 'description', 'image', 'datePublished', 'dateModified', 'author', 'publisher']

function walk(dir, acc = []) {
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry)
    if (statSync(full).isDirectory()) walk(full, acc)
    else if (entry === 'index.html') acc.push(full)
  }
  return acc
}

/** Every object anywhere in the graph, depth-first. */
function allNodes(value, acc = []) {
  if (Array.isArray(value)) value.forEach((v) => allNodes(v, acc))
  else if (value && typeof value === 'object') {
    acc.push(value)
    Object.values(value).forEach((v) => allNodes(v, acc))
  }
  return acc
}

let failures = 0
let checked = 0
let articles = 0

for (const file of walk(distClient).sort()) {
  const rel = relative(distClient, dirname(file)).split(/[\\/]/).join('/')
  const route = rel === '' ? '/' : `/${rel}/`
  if (route.startsWith('/admin')) continue

  const html = readFileSync(file, 'utf8')
  if (NOINDEX_RE.test(html)) continue
  checked++

  const problems = []
  const top = []
  for (const m of html.matchAll(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/g)) {
    try {
      const parsed = JSON.parse(m[1])
      top.push(...(Array.isArray(parsed) ? parsed : [parsed]))
    } catch (err) {
      problems.push(`unparseable JSON-LD block: ${err.message}`)
    }
  }

  const nodes = allNodes(top)
  const defined = new Set(nodes.filter((n) => n['@id'] && n['@type']).map((n) => n['@id']))

  // One @id must not claim two names.
  const namesById = new Map()
  for (const n of nodes) {
    if (!n['@id'] || typeof n.name !== 'string') continue
    if (!namesById.has(n['@id'])) namesById.set(n['@id'], new Set())
    namesById.get(n['@id']).add(n.name)
  }
  for (const [id, names] of namesById) {
    if (names.size > 1) problems.push(`@id ${id} claims ${names.size} names: ${[...names].join(' / ')}`)
  }

  // A bare {"@id": …} reference must resolve to a node on the same page.
  for (const n of nodes) {
    const keys = Object.keys(n)
    if (keys.length === 1 && keys[0] === '@id' && !defined.has(n['@id'])) {
      problems.push(`dangling reference to ${n['@id']}`)
    }
  }

  for (const n of top) {
    if (n['@type'] !== 'Article') continue
    articles++
    for (const key of ARTICLE_REQUIRED) {
      if (!(key in n)) problems.push(`Article missing ${key}`)
    }
    if (typeof n.headline === 'string' && n.headline.length > HEADLINE_MAX) {
      problems.push(`Article headline ${n.headline.length} > ${HEADLINE_MAX}`)
    }
  }

  const fullOrgs = nodes.filter((n) => n['@type'] === 'Organization' && n.name && n.url)
  if (fullOrgs.length > 1) {
    problems.push(`${fullOrgs.length} full Organization nodes — reference the sitewide one by @id instead`)
  }

  if (problems.length) {
    failures++
    for (const p of problems) console.error(`[schema] FAIL  ${route} — ${p}`)
  }
}

console.log(`[schema] checked ${checked} route(s), ${articles} Article node(s): ${failures} route(s) with problems`)
if (checked === 0) {
  console.error('[schema] no routes checked — did the prerender run?')
  process.exit(1)
}
process.exit(failures > 0 ? 1 : 0)
