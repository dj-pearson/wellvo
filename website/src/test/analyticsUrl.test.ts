import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, it, expect } from 'vitest'
import { scrubAnalyticsUrl } from '../lib/consent'

/**
 * Invite links (/invite/<token>?code=…) join a family. GA4 must never see the
 * token or code, and the Cloudflare beacon must not run on the invite shell.
 */
describe('scrubAnalyticsUrl', () => {
  it('collapses invite tokens and drops the code', () => {
    expect(scrubAnalyticsUrl('https://dailyok.net/invite/abc123TOKEN?code=123456#x')).toEqual({
      page_location: 'https://dailyok.net/invite/',
      page_path: '/invite/',
    })
    expect(scrubAnalyticsUrl('https://dailyok.net/invite?code=123456').page_path).toBe('/invite/')
    expect(scrubAnalyticsUrl('https://dailyok.net/invite/a/b/').page_location).toBe(
      'https://dailyok.net/invite/',
    )
  })

  it('strips query strings and fragments from every page', () => {
    expect(scrubAnalyticsUrl('https://dailyok.net/pricing/?utm_source=x&email=a@b.c#faq')).toEqual({
      page_location: 'https://dailyok.net/pricing/',
      page_path: '/pricing/',
    })
  })

  it('leaves look-alike paths alone', () => {
    expect(scrubAnalyticsUrl('https://dailyok.net/invitations/').page_path).toBe('/invitations/')
  })

  it('fails closed on an unparseable URL', () => {
    expect(scrubAnalyticsUrl('not a url')).toEqual({ page_location: '', page_path: '/' })
  })
})

describe('Cloudflare beacon on invite pages', () => {
  it('is gated on the invite path in onRenderHtml', () => {
    const source = readFileSync(resolve(__dirname, '../../pages/+onRenderHtml.tsx'), 'utf-8')
    expect(source).toMatch(/isInvitePath\(pageContext\.urlPathname[^)]*\) \? '' : CF_BEACON/)
  })
})
