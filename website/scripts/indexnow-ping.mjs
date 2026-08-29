/**
 * IndexNow ping (SEO_STRATEGY.md §5).
 *
 * Runs AFTER generate-sitemap.mjs. Reads the emitted sitemap(s), collects the
 * <loc> URLs, and submits them to IndexNow so Bing + Yandex index new/changed
 * pages within minutes instead of waiting for a crawl. (Google ignores
 * IndexNow; it gets the sitemap + Search Console.)
 *
 * Safe by design:
 *  - No-ops (exit 0) if the key file or sitemap is missing, so local builds and
 *    PR previews never fail. It only actually pings when INDEXNOW_SUBMIT=1
 *    (set this in the production deploy job) — otherwise it just logs intent.
 *  - Network errors are caught and logged, never thrown.
 *
 * Scope (US-WEB009): submits URLs whose <lastmod> falls inside a recency
 * window rather than the entire sitemap on every deploy. Re-submitting a
 * hundred unchanged URLs each build is what burns an IndexNow quota and
 * teaches the endpoint to ignore you. The window is stateless on purpose —
 * CI has no memory of the previous deploy, and <lastmod> already carries the
 * "did this change" signal, which for blog posts is now the post's real
 * updated_at. If nothing falls inside the window (a first deploy, or a
 * long-quiet site) it falls back to submitting everything.
 *
 * Usage:
 *   node scripts/indexnow-ping.mjs            # dry-run: parse + log, no POST
 *   INDEXNOW_SUBMIT=1 node scripts/indexnow-ping.mjs   # real submission
 *   INDEXNOW_WINDOW_DAYS=7 node scripts/...   # narrow the recency window
 */
import { readFileSync, existsSync, readdirSync } from 'fs'
import { join, dirname } from 'path'
import { fileURLToPath } from 'url'

const __dirname = dirname(fileURLToPath(import.meta.url))
const websiteDir = join(__dirname, '..')
const publicDir = join(websiteDir, 'public')
const distClient = join(websiteDir, 'dist', 'client')

const SITE_ORIGIN = 'https://dailyok.net'
const HOST = 'dailyok.net'
const ENDPOINT = 'https://api.indexnow.org/indexnow'

// The IndexNow key is the basename of the *.txt key file committed in public/.
function findKey() {
  if (!existsSync(publicDir)) return null
  const keyFile = readdirSync(publicDir).find(
    (f) => /^[a-f0-9]{8,128}\.txt$/i.test(f),
  )
  if (!keyFile) return null
  const key = keyFile.replace(/\.txt$/i, '')
  const contents = readFileSync(join(publicDir, keyFile), 'utf8').trim()
  // The file must contain exactly the key (IndexNow requirement).
  if (contents !== key) {
    console.warn(`[indexnow] key file ${keyFile} contents != filename; skipping`)
    return null
  }
  return key
}

const WINDOW_DAYS = Number(process.env.INDEXNOW_WINDOW_DAYS ?? 30)

function locsFromXml(xml) {
  return [...xml.matchAll(/<loc>\s*([^<\s]+)\s*<\/loc>/g)].map((m) => m[1])
}

/** [{ loc, lastmod }] from a <urlset>, preserving their pairing. */
function entriesFromXml(xml) {
  return [...xml.matchAll(/<url>([\s\S]*?)<\/url>/g)].map((m) => {
    const block = m[1]
    const loc = block.match(/<loc>\s*([^<\s]+)\s*<\/loc>/)?.[1] ?? null
    const lastmod = block.match(/<lastmod>\s*([^<\s]+)\s*<\/lastmod>/)?.[1] ?? null
    return { loc, lastmod }
  }).filter((e) => e.loc)
}

/** URLs changed within WINDOW_DAYS; all of them if none qualify. */
function selectRecent(entries) {
  if (!Number.isFinite(WINDOW_DAYS) || WINDOW_DAYS <= 0) {
    return entries.map((e) => e.loc)
  }
  const cutoff = Date.now() - WINDOW_DAYS * 86_400_000
  const recent = entries
    .filter((e) => {
      if (!e.lastmod) return true // undated: assume it may have changed
      const t = Date.parse(e.lastmod)
      return Number.isNaN(t) ? true : t >= cutoff
    })
    .map((e) => e.loc)
  if (recent.length === 0) {
    console.log(
      `[indexnow] nothing modified in the last ${WINDOW_DAYS} day(s); submitting all URLs instead.`,
    )
    return entries.map((e) => e.loc)
  }
  return recent
}

// Prefer the prerendered dist sitemap; fall back to the static public one.
function readSitemapEntries() {
  const roots = [distClient, publicDir]
  for (const root of roots) {
    const indexPath = join(root, 'sitemap.xml')
    if (!existsSync(indexPath)) continue
    const xml = readFileSync(indexPath, 'utf8')
    const locs = locsFromXml(xml)
    // If sitemap.xml is a sitemap index, its <loc>s point at child sitemaps.
    const childSitemaps = locs.filter((u) => /sitemap[\w-]*\.xml$/.test(u))
    if (childSitemaps.length && /<sitemapindex/.test(xml)) {
      const byLoc = new Map()
      for (const child of childSitemaps) {
        const childFile = join(root, child.split('/').pop())
        if (existsSync(childFile)) {
          for (const e of entriesFromXml(readFileSync(childFile, 'utf8'))) {
            byLoc.set(e.loc, e)
          }
        }
      }
      if (byLoc.size) return [...byLoc.values()]
    }
    const entries = entriesFromXml(xml)
    if (entries.length) return entries
  }
  return []
}

async function main() {
  const key = findKey()
  if (!key) {
    console.log('[indexnow] no key file in public/; nothing to submit. Skipping.')
    return
  }
  const entries = readSitemapEntries().filter((e) => e.loc.startsWith(SITE_ORIGIN))
  if (!entries.length) {
    console.log('[indexnow] no sitemap URLs found; skipping.')
    return
  }
  const urlList = selectRecent(entries)
  const blogCount = urlList.filter((u) => u.startsWith(`${SITE_ORIGIN}/blog/`)).length
  console.log(
    `[indexnow] ${urlList.length} of ${entries.length} URL(s) selected ` +
      `(window ${WINDOW_DAYS}d, ${blogCount} blog post(s)).`,
  )

  const payload = {
    host: HOST,
    key,
    keyLocation: `${SITE_ORIGIN}/${key}.txt`,
    urlList,
  }

  if (process.env.INDEXNOW_SUBMIT !== '1') {
    console.log(
      `[indexnow] dry-run: would submit ${urlList.length} URL(s) for ${HOST}. ` +
        `Set INDEXNOW_SUBMIT=1 in the production deploy to send.`,
    )
    return
  }

  try {
    const res = await fetch(ENDPOINT, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=utf-8' },
      body: JSON.stringify(payload),
    })
    console.log(`[indexnow] submitted ${urlList.length} URL(s) → ${res.status} ${res.statusText}`)
  } catch (err) {
    console.warn(`[indexnow] submission failed (non-fatal): ${err?.message ?? err}`)
  }
}

main()
