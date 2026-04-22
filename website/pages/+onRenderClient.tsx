import { hydrateRoot, createRoot } from 'react-dom/client'
import { StrictMode } from 'react'
import { BrowserRouter } from 'react-router-dom'
import { HelmetProvider } from 'react-helmet-async'
import { AdminAuthProvider } from '../src/admin/AdminAuthProvider'
import ErrorBoundary from '../src/components/ErrorBoundary'
import type { PageContextClient } from 'vike/types'
import Page from './+Page'

let rendered = false

export default async function onRenderClient(_pageContext: PageContextClient) {
  const container = document.getElementById('root')
  if (!container) return

  const tree = (
    <StrictMode>
      <ErrorBoundary>
        <HelmetProvider>
          <AdminAuthProvider>
            <BrowserRouter>
              <Page />
            </BrowserRouter>
          </AdminAuthProvider>
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
