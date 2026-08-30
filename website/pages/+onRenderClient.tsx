import { hydrateRoot, createRoot } from 'react-dom/client'
import { StrictMode } from 'react'
import { BrowserRouter } from 'react-router-dom'
import { HelmetProvider } from 'react-helmet-async'
import { AdminAuthProvider } from '../src/admin/AdminAuthProvider'
import ErrorBoundary from '../src/components/ErrorBoundary'
import { initSentry } from '../src/lib/sentry'
import { BlogSeedProvider, seedFromPageContext } from '../src/lib/blogSeed'
import type { PageContextClient } from 'vike/types'
import Page from './+Page'

// Route browser errors to the Daily OK Sentry project. Runs once on first
// client render; prerender/SSR (onRenderHtml) never calls this.
initSentry()

let rendered = false

export default async function onRenderClient(pageContext: PageContextClient) {
  const container = document.getElementById('root')
  if (!container) return

  // Must match what +onRenderHtml.tsx rendered, or hydration mismatches
  // on every prerendered blog page (US-WEB008).
  const blogSeed = seedFromPageContext(pageContext)

  const tree = (
    <StrictMode>
      <ErrorBoundary>
        <HelmetProvider>
          <BlogSeedProvider seed={blogSeed}>
            <AdminAuthProvider>
              <BrowserRouter>
                <Page />
              </BrowserRouter>
            </AdminAuthProvider>
          </BlogSeedProvider>
        </HelmetProvider>
      </ErrorBoundary>
    </StrictMode>
  )

  // First render of the session hydrates the prerendered HTML; subsequent
  // navigations are handled by React Router within the already-mounted tree
  // (we don't re-mount on route change).
  if (!rendered) {
    rendered = true
    if (container.innerHTML.trim().length > 0) {
      hydrateRoot(container, tree)
    } else {
      createRoot(container).render(tree)
    }
  }
}
