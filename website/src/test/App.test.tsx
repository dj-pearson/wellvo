import { render, screen, waitFor } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { HelmetProvider } from 'react-helmet-async'
import { describe, it, expect, beforeEach } from 'vitest'
import App from '../App'
import { canonicalUrl } from '../lib/canonical'

/**
 * Route integrity (US-WEB021).
 *
 * This suite used to assert on hero prose — `/know your loved ones are OK/i`
 * for the home page, and so on. That copy is the part of the site the SEO work
 * deliberately rewrites: the home H1 became "Know your aging parent is OK",
 * the assertion went stale, and the whole file sat red. A test that breaks
 * every time someone does their job correctly gets ignored, and an ignored
 * test file hides the failures that do matter.
 *
 * So these assertions are about route *identity*, not wording. For every
 * public route they check the three things that are genuinely broken if they
 * are false, and that no copy edit can legitimately change:
 *
 *   1. The route renders without throwing.
 *   2. It did not silently fall through to the 404 page — the single most
 *      likely regression when a path is renamed in one place but not another.
 *   3. It emits exactly one H1, whose canonical link matches the trailing-slash
 *      form from US-WEB010. One H1 is both an accessibility requirement and
 *      the thing search engines read as the page's subject.
 *
 * Copy is asserted in exactly one place — the home page's own reason to exist,
 * below — and even there only as the promise, not the sentence.
 */

/** Every public route, with the params the dynamic ones need. */
const PUBLIC_ROUTES = [
  '/',
  '/pricing',
  '/support',
  '/privacy',
  '/terms',
  '/cookies',
  '/dmca',
  '/accessibility',
  '/elderly-care',
  '/child-safety',
  '/check-in-app-for-elderly',
  '/daily-check-in-app-for-seniors',
  '/peace-of-mind-app-for-elderly-parents',
  '/welfare-check-on-elderly-parent',
  '/what-to-do',
  '/what-to-do/elderly-father-not-answering-phone',
  '/compare',
  '/compare/daily-ok-vs-life-alert',
]

function renderApp(initialRoute: string) {
  return render(
    <HelmetProvider>
      <MemoryRouter initialEntries={[initialRoute]}>
        <App />
      </MemoryRouter>
    </HelmetProvider>,
  )
}

beforeEach(() => {
  document.head.querySelectorAll('link[rel="canonical"]').forEach((el) => el.remove())
})

describe('public routes', () => {
  it.each(PUBLIC_ROUTES)('%s renders a page rather than the 404', async (route) => {
    renderApp(route)

    const heading = await screen.findByRole('heading', { level: 1 })
    expect(heading).toBeInTheDocument()
    expect(heading.textContent?.trim()).not.toBe('')

    // NotFound owns this copy; if it shows up here, the route did not match.
    expect(screen.queryByText(/page not found/i)).not.toBeInTheDocument()

    // Exactly one H1 — more than one and neither search engines nor screen
    // reader users can tell what the page is about.
    expect(screen.getAllByRole('heading', { level: 1 })).toHaveLength(1)
  })

  it.each(PUBLIC_ROUTES)('%s declares its own canonical URL', async (route) => {
    renderApp(route)
    await screen.findByRole('heading', { level: 1 })

    await waitFor(() => {
      const canonical = document.head.querySelector('link[rel="canonical"]')
      expect(canonical?.getAttribute('href')).toBe(canonicalUrl(route))
    })
  })
})

describe('unknown routes', () => {
  it('renders the 404 page', async () => {
    renderApp('/this-route-does-not-exist')
    expect(await screen.findByText(/page not found/i)).toBeInTheDocument()
  })
})

describe('the home page', () => {
  it('leads with the promise the product is sold on', async () => {
    renderApp('/')
    const heading = await screen.findByRole('heading', { level: 1 })

    // Not the sentence — the promise. Rewording is expected; dropping the
    // "someone you worry about is OK" claim from the H1 is a product decision
    // that should have to break a test on the way through.
    expect(heading.textContent).toMatch(/\bOK\b/)
  })
})
