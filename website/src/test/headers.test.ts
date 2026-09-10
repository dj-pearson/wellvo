import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { readdirSync, statSync } from 'node:fs'
import { describe, it, expect } from 'vitest'

/**
 * Guards US-SEO012 — the caching contract in public/_headers.
 *
 * Cloudflare Pages sends `public, max-age=0, must-revalidate` for every path it
 * is not told about, so the absence of a rule is not a neutral default: it is
 * a revalidation round-trip on every navigation. That was the state for all
 * 1.4 MB of content-hashed JS and CSS under /assets.
 *
 * The mirror-image mistake is worse and silent: an immutable year on a path
 * whose filename does NOT change between deploys pins visitors to a stale
 * build with no way to recover. These assertions pin both directions.
 */

const root = resolve(__dirname, '../..')
const headers = readFileSync(resolve(root, 'public/_headers'), 'utf-8')

/** All directives declared for a path, as written. */
function rulesFor(path: string): string[] {
  const lines = headers.split('\n')
  const start = lines.findIndex((l) => l.trim() === path)
  if (start === -1) return []
  const out: string[] = []
  for (let i = start + 1; i < lines.length; i++) {
    const line = lines[i]
    if (!/^\s+\S/.test(line)) break
    out.push(line.trim())
  }
  return out
}

function cacheControlFor(path: string): string | undefined {
  return rulesFor(path)
    .find((r) => r.toLowerCase().startsWith('cache-control:'))
    ?.slice('cache-control:'.length)
    .trim()
}

const IMMUTABLE = 'public, max-age=31536000, immutable'

describe('cache headers', () => {
  it('caches the content-hashed build output for a year', () => {
    expect(cacheControlFor('/assets/*')).toBe(IMMUTABLE)
    expect(cacheControlFor('/fonts/*')).toBe(IMMUTABLE)
  })

  it('never caches a stable-named path immutably', () => {
    // Each of these keeps the same URL across deploys. An immutable year on
    // any of them strands visitors and crawlers on an old build.
    for (const path of ['/*', '/', '/index.html', '/sitemap.xml', '/robots.txt', '/llms.txt']) {
      const cc = cacheControlFor(path)
      if (cc) expect(cc).not.toContain('immutable')
    }
    expect(headers).not.toMatch(/^\/\*\s*$[\s\S]{0,400}?immutable/m)
  })

  it('gives unhashed brand assets a bounded lifetime, not a year', () => {
    const cc = cacheControlFor('/og-image.png')
    expect(cc).toBeDefined()
    expect(cc).not.toContain('immutable')
    expect(cc).toContain('stale-while-revalidate')
  })

  it('covers every unhashed asset the pages actually reference', () => {
    // The rules are written out one path at a time on purpose, which only
    // stays correct if the list matches what public/ contains.
    const publicDir = resolve(root, 'public')
    const topLevelAssets = readdirSync(publicDir)
      .filter((f) => statSync(resolve(publicDir, f)).isFile())
      .filter((f) => /\.(png|svg)$/.test(f))
    for (const file of topLevelAssets) {
      expect(cacheControlFor(`/${file}`), `${file} has no cache rule`).toBeDefined()
    }
  })
})

describe('robots headers', () => {
  it('marks the admin surface noindex at the HTTP layer too', () => {
    // _redirects rewrites /admin/* to the homepage shell, so without this a
    // crawler reaching it is served the homepage's HTML under an /admin URL.
    for (const path of ['/admin', '/admin/*']) {
      expect(rulesFor(path).join(' ')).toMatch(/X-Robots-Tag:\s*noindex/i)
    }
  })
})
