import { render, screen } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { HelmetProvider } from 'react-helmet-async'
import { describe, it, expect } from 'vitest'
import { canonicalPath, canonicalUrl } from '../lib/canonical'
import { buildBreadcrumbJsonLd } from '../lib/breadcrumb'
import App from '../App'

/**
 * Guards US-WEB010. Production serves the trailing-slash form
 * (`/pricing` 308s to `/pricing/`), so canonicals, sitemap <loc>s, JSON-LD
 * urls and internal links must all use it — otherwise every one of them
 * points at a URL that redirects, which is what left both forms indexed.
 */

describe('canonicalPath', () => {
  it('adds a trailing slash to app paths', () => {
    expect(canonicalPath('/pricing')).toBe('/pricing/')
    expect(canonicalPath('/what-to-do/mom-not-answering-phone')).toBe(
      '/what-to-do/mom-not-answering-phone/',
    )
  })

  it('leaves the root path alone rather than producing //', () => {
    expect(canonicalPath('/')).toBe('/')
    expect(canonicalUrl('/')).toBe('https://dailyok.net/')
  })

  it('is idempotent', () => {
    expect(canonicalPath('/pricing/')).toBe('/pricing/')
    expect(canonicalPath(canonicalPath('/blog'))).toBe('/blog/')
  })

  it('does not mangle a path carrying a fragment or query', () => {
    expect(canonicalPath('/#how-it-works')).toBe('/#how-it-works')
    expect(canonicalPath('/support?topic=billing')).toBe('/support?topic=billing')
  })

  it('builds absolute URLs on the production origin', () => {
    expect(canonicalUrl('/pricing')).toBe('https://dailyok.net/pricing/')
  })
})

describe('breadcrumb JSON-LD', () => {
  it('emits canonical trailing-slash item URLs', () => {
    const ld = buildBreadcrumbJsonLd([
      { name: 'Home', path: '/' },
      { name: 'Blog', path: '/blog' },
    ]) as { itemListElement: { item: string }[] }
    expect(ld.itemListElement.map((e) => e.item)).toEqual([
      'https://dailyok.net/',
      'https://dailyok.net/blog/',
    ])
  })
})

describe('routing tolerates the canonical trailing-slash form', () => {
  // Internal links now render href="/pricing/". If React Router did not match
  // that against <Route path="/pricing">, every internal link on the site
  // would 404 — so this is the load-bearing assertion of US-WEB010.
  it('renders the pricing page at /pricing/', async () => {
    render(
      <HelmetProvider>
        <MemoryRouter initialEntries={['/pricing/']}>
          <App />
        </MemoryRouter>
      </HelmetProvider>,
    )
    expect(await screen.findByText(/Simple, Transparent Pricing/i)).toBeInTheDocument()
  })

  it('renders a what-to-do page at its trailing-slash path', async () => {
    render(
      <HelmetProvider>
        <MemoryRouter initialEntries={['/what-to-do/mom-not-answering-phone/']}>
          <App />
        </MemoryRouter>
      </HelmetProvider>,
    )
    expect(
      await screen.findByRole('heading', { level: 1, name: /doesn't answer the phone/i }),
    ).toBeInTheDocument()
  })
})
