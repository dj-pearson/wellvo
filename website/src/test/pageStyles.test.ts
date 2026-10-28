import { readFileSync, readdirSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, it, expect } from 'vitest'

/**
 * Page CSS ships in the prerendered <head> via src/pageStyles.css, which
 * pages/+onRenderHtml.tsx imports. Every route is a lazy() chunk, so a page
 * stylesheet imported from its component instead would only arrive after the
 * JS chunk loads — the unstyled-flash + layout-shift this file exists to stop.
 * These checks keep a new page from quietly reintroducing it.
 */

const src = resolve(__dirname, '..')
const read = (p: string) => readFileSync(resolve(src, p), 'utf-8')

const pageCss = readdirSync(resolve(src, 'pages')).filter((f) => f.endsWith('.css'))
const pageTsx = readdirSync(resolve(src, 'pages')).filter((f) => f.endsWith('.tsx'))
const bundle = read('pageStyles.css')

describe('page stylesheets', () => {
  it('bundles every src/pages stylesheet, after shared.css', () => {
    expect(bundle).toMatch(/@import '\.\/shared\.css';[\s\S]*@import '\.\/pages\//)
    for (const file of pageCss) {
      expect(bundle, `${file} missing from pageStyles.css`).toContain(`@import './pages/${file}';`)
    }
  })

  it('keeps Accessibility.css after Legal.css so its overrides win', () => {
    expect(bundle.indexOf("@import './pages/Accessibility.css'")).toBeGreaterThan(
      bundle.indexOf("@import './pages/Legal.css'"),
    )
  })

  it('is linked from the static render graph, not from lazy page components', () => {
    expect(readFileSync(resolve(src, '../pages/+onRenderHtml.tsx'), 'utf-8')).toContain(
      "import '../src/pageStyles.css'",
    )
    for (const file of pageTsx) {
      expect(read(`pages/${file}`), `${file} imports CSS directly`).not.toMatch(/^import '[^']+\.css'/m)
    }
  })
})
