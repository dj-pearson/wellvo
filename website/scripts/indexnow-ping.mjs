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
 * Usage:
 *   node scripts/indexnow-ping.mjs            # dry-run: parse + log, no POST
 *   INDEXNOW_SUBMIT=1 node scripts/indexnow-ping.mjs   # real submission
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

function locsFromXml(xml) {
  return [...xml.matchAll(/<loc>\s*([^<\s]+)\s*<\/loc>/g)].map((m) => m[1])
}

// Prefer the prerendered dist sitemap; fall back to the static public one.
function readSitemapUrls() {
  const roots = [distClient, publicDir]
  for (const root of roots) {
    const indexPath = join(root, 'sitemap.xml')
    if (!existsSync(indexPath)) continue
    const xml = readFileSync(indexPath, 'utf8')
    const locs = locsFromXml(xml)
    // If sitemap.xml is a sitemap index, its <loc>s point at child sitemaps.
    const childSitemaps = locs.filter((u) => /sitemap[\w-]*\.xml$/.test(u))
    if (childSitemaps.length && /<sitemapindex/.test(xml)) {
      const urls = new Set()
      for (const child of childSitemaps) {
        const childFile = join(root, child.split('/').pop())
        if (existsSync(childFile)) {
          locsFromXml(readFileSync(childFile, 'utf8')).forEach((u) => urls.add(u))
        }
      }
      if (urls.size) return [...urls]
    }
    if (locs.length) return locs
  }
  return []
}

async function main() {
  const key = findKey()
  if (!key) {
    console.log('[indexnow] no key file in public/; nothing to submit. Skipping.')
    return
  }
  const urlList = readSitemapUrls().filter((u) => u.startsWith(SITE_ORIGIN))
  if (!urlList.length) {
    console.log('[indexnow] no sitemap URLs found; skipping.')
    return
  }

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
