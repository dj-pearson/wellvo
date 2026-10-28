import { describe, it, expect } from 'vitest'
import type { ErrorEvent } from '@sentry/react'
import { scrubUrl, scrubEvent, scrubBreadcrumb } from '../lib/sentry'

describe('sentry URL scrubbing', () => {
  it('drops query strings and fragments', () => {
    expect(scrubUrl('https://dailyok.net/pricing?utm_source=x#plans')).toBe(
      'https://dailyok.net/pricing',
    )
    expect(scrubUrl('https://dailyok.net/admin#access_token=abc&type=recovery')).toBe(
      'https://dailyok.net/admin',
    )
  })

  it('redacts invite tokens and codes', () => {
    expect(scrubUrl('https://dailyok.net/invite/AbC123xyz?code=987654')).toBe(
      'https://dailyok.net/invite/:token',
    )
    expect(scrubUrl('/invite/AbC123xyz')).toBe('/invite/:token')
    expect(scrubUrl('/invite')).toBe('/invite')
  })

  it('scrubs the event request and its breadcrumbs', () => {
    const event = {
      request: {
        url: 'https://dailyok.net/invite/tok?code=1',
        query_string: 'code=1',
        headers: { Referer: 'https://dailyok.net/invite/tok#x' },
      },
      breadcrumbs: [{ category: 'navigation', data: { from: '/invite/tok?code=1', to: '/' } }],
    } as unknown as ErrorEvent
    const out = scrubEvent(event)
    expect(out.request?.url).toBe('https://dailyok.net/invite/:token')
    expect(out.request?.query_string).toBeUndefined()
    expect(out.request?.headers?.Referer).toBe('https://dailyok.net/invite/:token')
    expect(out.breadcrumbs?.[0].data?.from).toBe('/invite/:token')
  })

  it('scrubs fetch breadcrumb URLs', () => {
    const crumb = scrubBreadcrumb({
      category: 'fetch',
      data: { url: 'https://functions.dailyok.net/invite/tok?code=1', method: 'GET' },
    })
    expect(crumb.data?.url).toBe('https://functions.dailyok.net/invite/:token')
    expect(crumb.data?.method).toBe('GET')
  })
})
