import { readFileSync, statSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, it, expect } from 'vitest'

/**
 * Guards US-WEB020. Inter is self-hosted. Two things regress easily and both
 * are silent — nothing breaks visually, the site just gets slower and starts
 * leaking visitor IPs to Google again:
 *
 *   1. Someone pastes the Google Fonts <link> back into the head "to fix the
 *      font", and the render-blocking third-party request returns.
 *   2. The woff2 files get moved or renamed without updating @font-face, so
 *      every visitor silently falls back to system-ui.
 *
 * The CSP in public/_headers no longer allows fonts.googleapis.com or
 * fonts.gstatic.com, so a reintroduced <link> would be blocked in production
 * and the font would vanish. These assertions catch it in CI instead.
 */

const root = resolve(__dirname, '../..')
const read = (p: string) => readFileSync(resolve(root, p), 'utf-8')

const FONT_FILES = [
  'public/fonts/inter-v20-latin.woff2',
  'public/fonts/inter-v20-latin-ext.woff2',
]

describe('self-hosted Inter', () => {
  it('ships the woff2 files the stylesheet points at', () => {
    for (const file of FONT_FILES) {
      expect(statSync(resolve(root, file)).size).toBeGreaterThan(1024)
    }
  })

  it('declares every font file in @font-face', () => {
    const css = read('src/index.css')
    for (const file of FONT_FILES) {
      expect(css).toContain(file.replace('public', ''))
    }
    // swap, not block: text must paint in the fallback stack immediately.
    expect(css).toContain('font-display: swap')
  })

  it('preloads the latin subset from the document head', () => {
    const head = read('pages/+onRenderHtml.tsx')
    expect(head).toMatch(/rel="preload"[\s\S]*inter-v20-latin\.woff2/)
    expect(head).toContain('crossOrigin="anonymous"')
  })

  it('does not fetch fonts from Google anywhere in the shipped head or CSS', () => {
    // Comments explaining *why* we left are fine; a real URL is not.
    const strip = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\{\/\*[\s\S]*?\*\/\}/g, '')
    for (const file of ['src/index.css', 'pages/+onRenderHtml.tsx']) {
      const source = strip(read(file))
      expect(source).not.toContain('fonts.googleapis.com')
      expect(source).not.toContain('fonts.gstatic.com')
    }
  })

  it('keeps Google font origins out of the Content-Security-Policy', () => {
    const csp = read('public/_headers')
      .split('\n')
      .find((line) => line.includes('Content-Security-Policy'))
    expect(csp).toBeDefined()
    expect(csp).not.toContain('fonts.googleapis.com')
    expect(csp).not.toContain('fonts.gstatic.com')
  })
})
