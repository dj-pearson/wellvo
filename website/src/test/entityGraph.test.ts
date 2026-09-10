import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, it, expect } from 'vitest'
import {
  APPLICATION_ID,
  EDITORIAL_TEAM_ID,
  ORGANIZATION_ID,
  WEBSITE_ID,
} from '../lib/entityIds'
import { buildEditorialArticleJsonLd } from '../lib/articleSchema'

/**
 * Guards US-SEO015.
 *
 * The sitewide JSON-LD lives in a template literal in pages/+onRenderHtml.tsx,
 * which cannot import from src/. So the same three @id strings are written
 * twice, and nothing but this test stops them drifting — at which point every
 * per-page publisher reference silently dangles and the graph quietly stops
 * resolving. Nothing renders differently when that happens.
 */

const head = readFileSync(
  resolve(__dirname, '../../pages/+onRenderHtml.tsx'),
  'utf-8',
)

describe('the sitewide entity ids', () => {
  it.each([
    ['Organization', ORGANIZATION_ID],
    ['WebSite', WEBSITE_ID],
    ['SoftwareApplication', APPLICATION_ID],
  ])('%s declares the id src/lib/entityIds.ts expects', (_type, id) => {
    expect(head).toContain(`"@id": "${id}"`)
  })

  it('points the app and the site at the organization', () => {
    const references = head.match(
      new RegExp(`"publisher": \\{ "@id": "${ORGANIZATION_ID}" \\}`, 'g'),
    )
    expect(references).toHaveLength(2)
  })

  it('keeps the ids distinct', () => {
    const ids = [ORGANIZATION_ID, WEBSITE_ID, APPLICATION_ID, EDITORIAL_TEAM_ID]
    expect(new Set(ids).size).toBe(ids.length)
  })
})

describe('buildEditorialArticleJsonLd', () => {
  const article = buildEditorialArticleJsonLd({
    headline: 'What to do when an elderly parent does not answer the phone',
    description: 'An ordered plan for the first 30 minutes.',
    path: '/what-to-do/elderly-father-not-answering-phone',
    datePublished: '2026-08-29',
    section: "Doesn't answer the phone",
  })

  it('references the sitewide organization rather than redeclaring it', () => {
    expect(article.publisher).toEqual({ '@id': ORGANIZATION_ID })
    expect(article.isPartOf).toEqual({ '@id': WEBSITE_ID })
  })

  it('attributes to the editorial team as its own node, not the company relabelled', () => {
    // Reusing ORGANIZATION_ID with a different name asserts that one @id has
    // two names — a contradiction that only shows up when the graph resolves.
    const author = article.author as Record<string, unknown>
    expect(author['@id']).toBe(EDITORIAL_TEAM_ID)
    expect(author['@id']).not.toBe(ORGANIZATION_ID)
    expect(author.name).toBe('Daily OK Editorial Team')
    expect(author.parentOrganization).toEqual({ '@id': ORGANIZATION_ID })
  })

  it('does not imply medical credentials', () => {
    // Standing YMYL constraint from src/data/whatToDo.ts: until a licensed
    // clinician is contracted, the byline must not read as a practitioner.
    const author = article.author as Record<string, unknown>
    expect(author['@type']).toBe('Organization')
    expect(String(author.name)).not.toMatch(/\b(Dr|MD|RN|LCSW|PhD)\b/)
  })

  it('carries the fields Google needs and truncates an over-long headline', () => {
    expect(article.image).toEqual(['https://dailyok.net/og-image.png'])
    expect(article.dateModified).toBe('2026-08-29')
    expect(article.mainEntityOfPage).toEqual({
      '@type': 'WebPage',
      '@id': 'https://dailyok.net/what-to-do/elderly-father-not-answering-phone/',
    })

    const long = buildEditorialArticleJsonLd({
      headline: 'x'.repeat(300),
      description: 'd',
      path: '/x',
      datePublished: '2026-01-01',
    })
    expect(String(long.headline)).toHaveLength(110)
  })
})
