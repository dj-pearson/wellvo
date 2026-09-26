import { render, screen } from '@testing-library/react'
import { MemoryRouter, Route, Routes } from 'react-router-dom'
import { HelmetProvider } from 'react-helmet-async'
import { describe, it, expect } from 'vitest'
import Invite from '../pages/Invite'
import { APP_STORE_URL, PLAY_STORE_URL, readInvite } from '../lib/invite'
import { readFileSync } from 'fs'
import { join } from 'path'

const TOKEN = 'a'.repeat(64)

function renderAt(url: string) {
  return render(
    <HelmetProvider>
      <MemoryRouter initialEntries={[url]}>
        <Routes>
          <Route path="/invite" element={<Invite />} />
          <Route path="/invite/:token" element={<Invite />} />
        </Routes>
      </MemoryRouter>
    </HelmetProvider>,
  )
}

describe('Invite page', () => {
  it('shows the setup code and hands the token to the app', () => {
    renderAt(`/invite/${TOKEN}?code=123456`)
    expect(screen.getByText('123456')).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Open Daily OK' })).toHaveAttribute(
      'href',
      `dailyok://invite?token=${TOKEN}`,
    )
  })

  it('links both stores to the real apps', () => {
    renderAt(`/invite/${TOKEN}`)
    expect(screen.getByRole('link', { name: /App Store/ })).toHaveAttribute('href', APP_STORE_URL)
    expect(screen.getByRole('link', { name: /Google Play/ })).toHaveAttribute('href', PLAY_STORE_URL)
  })

  it('accepts the older /invite?token= form', () => {
    renderAt(`/invite?token=${TOKEN}`)
    expect(screen.getByRole('link', { name: 'Open Daily OK' })).toHaveAttribute(
      'href',
      `dailyok://invite?token=${TOKEN}`,
    )
  })

  it('never puts a malformed token or code on the page', () => {
    expect(readInvite('not-hex"><script>', '?code=12ab')).toEqual({ token: null, code: null })
    expect(readInvite(undefined, '?token=abc&code=1234567')).toEqual({ token: null, code: null })
  })

  it('is noindex', () => {
    renderAt(`/invite/${TOKEN}`)
    // react-helmet-async moves tags into the head asynchronously; the SEO
    // component renders the robots meta inline in tests.
    const robots = document.querySelector('meta[name="robots"]')
    expect(robots?.getAttribute('content')).toContain('noindex')
  })
})

describe('invite routing files', () => {
  const pub = join(__dirname, '..', '..', 'public')

  it('serves every /invite/<token> the invite page', () => {
    const redirects = readFileSync(join(pub, '_redirects'), 'utf8')
    expect(redirects).toMatch(/^\/invite\/\*\s+\/invite\/index\.html\s+200$/m)
  })

  it('associates invite paths with the iOS app', () => {
    const aasa = JSON.parse(readFileSync(join(pub, '.well-known', 'apple-app-site-association'), 'utf8'))
    const detail = aasa.applinks.details[0]
    expect(detail.appID.endsWith('.com.wellvo.ios')).toBe(true)
    expect(detail.paths).toEqual(expect.arrayContaining(['/invite', '/invite/*']))
  })

  it('associates the Android package for App Links', () => {
    const links = JSON.parse(readFileSync(join(pub, '.well-known', 'assetlinks.json'), 'utf8'))
    expect(links[0].target.package_name).toBe('net.dailyok.android')
  })
})
