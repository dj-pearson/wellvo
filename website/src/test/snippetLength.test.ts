import { describe, it, expect } from 'vitest'
import { competitors } from '../data/competitors'

/**
 * Guards US-SEO008 — SERP snippet lengths on the comparison pages.
 *
 * Google renders roughly 580px of title and 920px of description before
 * truncating with an ellipsis; ~60 and ~160 characters are the usual
 * character-count proxies. Overshooting is not a soft cost. The description
 * on these pages was derived by taking the first two sentences of
 * `daily_ok_verdict` — page prose with no length ceiling — which produced 225
 * to 407 characters, so every one of the ten highest commercial-intent URLs on
 * the site was cut off mid-sentence in the result Google actually shows.
 *
 * These are the pages people paste into a group chat while deciding what to
 * buy for a parent. The snippet is the ad.
 */

const TITLE_MAX = 60
const DESCRIPTION_MAX = 160

/** Mirrors the title ComparePost.tsx builds. */
function titleFor(c: (typeof competitors)[number]): string {
  return c.meta_title ?? `Daily OK vs. ${c.name}: Honest Comparison (2026)`
}

describe('comparison page snippets', () => {
  it('has data for every competitor', () => {
    expect(competitors.length).toBeGreaterThanOrEqual(10)
  })

  it.each(competitors.map((c) => [c.slug, c] as const))(
    '%s fits the rendered title width',
    (_slug, c) => {
      const title = titleFor(c)
      expect(title.length).toBeLessThanOrEqual(TITLE_MAX)
      // No brand suffix is appended, so the title has to name the brand itself.
      expect(title).toContain('Daily OK')
    },
  )

  it.each(competitors.map((c) => [c.slug, c] as const))(
    '%s fits the rendered description width',
    (_slug, c) => {
      expect(c.meta_description.length).toBeLessThanOrEqual(DESCRIPTION_MAX)
      // Long enough to be worth showing: Google rewrites descriptions it
      // considers too thin to answer the query.
      expect(c.meta_description.length).toBeGreaterThanOrEqual(110)
    },
  )

  it('gives every page a distinct snippet', () => {
    const titles = new Set(competitors.map(titleFor))
    const descriptions = new Set(competitors.map((c) => c.meta_description))
    expect(titles.size).toBe(competitors.length)
    expect(descriptions.size).toBe(competitors.length)
  })

  it('no longer derives the description from the on-page verdict', () => {
    // The old bug in one assertion: a description that is a prefix of the
    // page's own prose is the truncation bug coming back.
    for (const c of competitors) {
      expect(c.daily_ok_verdict.startsWith(c.meta_description.slice(0, 40))).toBe(false)
    }
  })
})
