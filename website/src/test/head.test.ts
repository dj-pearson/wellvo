import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, it, expect } from 'vitest'

/**
 * Guards US-SEO003.
 *
 * pages/+onRenderHtml.tsx builds the shared <head> as a TEMPLATE LITERAL, not
 * as JSX. That distinction is invisible while editing — the file is .tsx and
 * the surrounding code is JSX — so a `{/* … *\/}` comment written by reflex
 * inside the string is not stripped by anything. It shipped as ~1.3 KB of
 * visible source commentary in the head of all 34 prerendered documents.
 *
 * The failure is silent: valid-enough HTML, no console error, nothing broken
 * on screen. Only reading the emitted output shows it. These assertions read
 * it from the source instead, so the loop is closed before a build runs.
 */

const root = resolve(__dirname, '../..')
const source = readFileSync(resolve(root, 'pages/+onRenderHtml.tsx'), 'utf-8')

/** The STATIC_HEAD template literal's contents, verbatim. */
function staticHead(): string {
  const start = source.indexOf('const STATIC_HEAD = `')
  expect(start).toBeGreaterThan(-1)
  const from = start + 'const STATIC_HEAD = `'.length
  const end = source.indexOf('`', from)
  expect(end).toBeGreaterThan(from)
  return source.slice(from, end)
}

/** The HEAD_FIRST template literal's contents, verbatim. */
function headFirst(): string {
  const start = source.indexOf('const HEAD_FIRST = `')
  expect(start).toBeGreaterThan(-1)
  const from = start + 'const HEAD_FIRST = `'.length
  const end = source.indexOf('`', from)
  expect(end).toBeGreaterThan(from)
  return source.slice(from, end)
}

describe('the static <head> template', () => {
  it('contains no JSX comment syntax', () => {
    // `{/*` would be emitted literally; so would a bare `*/}`.
    expect(staticHead()).not.toContain('{/*')
    expect(staticHead()).not.toContain('*/}')
  })

  it('ships no HTML comments', () => {
    // An HTML comment is valid inside the template but is copied into every
    // prerendered document. The commentary lives in TypeScript instead.
    expect(staticHead()).not.toContain('<!--')
    expect(headFirst()).not.toContain('<!--')
  })

  it('still carries the tags it exists to carry', () => {
    const head = staticHead()
    expect(head).toContain('rel="manifest"')
    expect(head).toContain('application/ld+json')
  })

  it('opens <head> with charset and viewport, ahead of the stylesheets', () => {
    const first = headFirst()
    expect(first.indexOf('<meta charset="UTF-8" />')).toBe(0)
    expect(first).toContain('name="viewport"')
    // Vike injects its stylesheet links at this placeholder rather than
    // straight after <head>, so it must come after the two tags above.
    expect(first.trimEnd().endsWith('${VIKE_ASSETS_FIRST}')).toBe(true)
    expect(source).toContain("const VIKE_ASSETS_FIRST = '__VITE_PLUGIN_SSR__ASSETS_FIRST__'")
    expect(source).toMatch(/<head>\s*\$\{dangerouslySkipEscape\(HEAD_FIRST\)\}/)
    // Neither tag is repeated further down.
    expect(staticHead()).not.toContain('charset')
    expect(staticHead()).not.toContain('name="viewport"')
  })

  it('relies on a placeholder the installed Vike still honours', () => {
    // If Vike drops the placeholder, it would ship as literal text and the
    // stylesheets would land back in front of <meta charset>.
    const injector = readFileSync(
      resolve(
        root,
        'node_modules/vike/dist/server/runtime/renderPageServer/html/injectAssets/injectHtmlTags.js',
      ),
      'utf-8',
    )
    expect(injector).toContain("'__VITE_PLUGIN_SSR__ASSETS_FIRST__'")
  })

  it('ships no placeholder analytics token', () => {
    // US-SEO004. The Cloudflare beacon is emitted only when
    // VITE_CF_ANALYTICS_TOKEN holds a real 32-hex token; a hard-coded one in
    // the template means every visitor pays a third-party request for
    // telemetry Cloudflare throws away.
    expect(staticHead()).not.toContain('YOUR_CF_ANALYTICS_TOKEN')
    expect(staticHead()).not.toContain('cloudflareinsights.com')
    expect(source).toContain('VITE_CF_ANALYTICS_TOKEN')
  })

  it('refuses a Cloudflare token that is not 32 hex characters', () => {
    // The token is interpolated straight into a JSON attribute, so the guard
    // that keeps arbitrary text out of the document must actually be there.
    const re = /const CF_TOKEN_RE = (\/.+\/i?)/.exec(source)
    expect(re).not.toBeNull()
    const pattern = new RegExp(re![1].slice(1, re![1].lastIndexOf('/')), 'i')
    expect(pattern.test('0123456789abcdef0123456789abcdef')).toBe(true)
    expect(pattern.test('YOUR_CF_ANALYTICS_TOKEN')).toBe(false)
    expect(pattern.test('"}\'></script><script>alert(1)</script>')).toBe(false)
    expect(pattern.test('')).toBe(false)
  })

  it('leaves per-page tags to the SEO component', () => {
    // title, description and canonical are per-URL and come from SEO.tsx via
    // extractHeadTags(). Hard-coding one here would give all 34 pages the
    // same one.
    const head = staticHead()
    expect(head).not.toContain('rel="canonical"')
    expect(head).not.toContain('<title>')
  })
})
