import { escapeInject, dangerouslySkipEscape } from 'vike/server'
import { renderToReadableStream } from 'react-dom/server'
import { StaticRouter } from 'react-router-dom'
import { HelmetProvider, type HelmetServerState } from 'react-helmet-async'
import { AdminAuthProvider } from '../src/admin/AdminAuthProvider'
import ErrorBoundary from '../src/components/ErrorBoundary'
import type { PageContextServer } from 'vike/types'
import Page from './+Page'

import '../src/index.css'
import '../src/App.css'

interface HelmetContext {
  helmet?: HelmetServerState
}

// Static <head> content shared by every prerendered page. Per-page <title>,
// <meta name="description">, canonical links, and JSON-LD are rendered by
// components (via react-helmet-async or plain React 19 tags) and lifted
// from body → head after render by extractHeadTags().
const STATIC_HEAD = `
    <meta charset="UTF-8" />
    <script async src="https://www.googletagmanager.com/gtag/js?id=G-J2H67EW9JY"></script>
    <script>
      window.dataLayer = window.dataLayer || [];
      function gtag(){dataLayer.push(arguments);}
      gtag('js', new Date());
      gtag('config', 'G-J2H67EW9JY');
    </script>
    <link rel="icon" type="image/svg+xml" href="/favicon.svg" />
    <link rel="icon" type="image/png" sizes="32x32" href="/icon-32.png" />
    <link rel="icon" type="image/png" sizes="16x16" href="/icon-16.png" />
    <link rel="manifest" href="/manifest.json" />
    <link rel="apple-touch-icon" href="/apple-touch-icon.png" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <meta name="theme-color" content="#2ECC71" />
    <meta name="apple-itunes-app" content="app-id=6760836697, app-argument=https://dailyok.net" />
    <link rel="preconnect" href="https://fonts.googleapis.com" />
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet" />
    <script type="application/ld+json">
    [
      {
        "@context": "https://schema.org",
        "@type": "SoftwareApplication",
        "name": "Daily OK",
        "applicationCategory": "HealthApplication",
        "applicationSubCategory": "Caregiving",
        "operatingSystem": "iOS, Android",
        "description": "Daily check-in app for families caring for elderly parents with dementia, children, and long-distance loved ones. One tap to confirm safety. Escalating alerts if no response.",
        "url": "https://dailyok.net",
        "downloadUrl": "https://apps.apple.com/us/app/dailyok-daily-check-in/id6760836697",
        "offers": [
          { "@type": "Offer", "price": "3.99", "priceCurrency": "USD", "name": "Caregiver monthly" },
          { "@type": "Offer", "price": "6.99", "priceCurrency": "USD", "name": "Family monthly" },
          { "@type": "Offer", "price": "9.99", "priceCurrency": "USD", "name": "Family+ monthly" }
        ]
      },
      {
        "@context": "https://schema.org",
        "@type": "Organization",
        "name": "Daily OK",
        "url": "https://dailyok.net",
        "logo": "https://dailyok.net/icon-512.png",
        "contactPoint": { "@type": "ContactPoint", "email": "support@dailyok.net", "contactType": "customer support" }
      },
      {
        "@context": "https://schema.org",
        "@type": "WebSite",
        "name": "Daily OK",
        "url": "https://dailyok.net"
      }
    ]
    </script>
    <script defer src="https://static.cloudflareinsights.com/beacon.min.js" data-cf-beacon='{"token": "YOUR_CF_ANALYTICS_TOKEN"}'></script>`

const DEFAULT_TITLE = '<title>Daily OK — Daily Check-In App for Families & Caregivers</title>'
const DEFAULT_DESCRIPTION = '<meta name="description" content="Daily OK is the simplest daily check-in app for families caring for aging parents, children, and long-distance loved ones. One tap. Peace of mind." />'

/**
 * React Helmet Async's server-side capture doesn't reliably fire under
 * React 19's streaming renderer, so it emits <title>, <meta>, <link>, and
 * JSON-LD <script> tags inside the React tree (which ends up in <body>).
 * Browsers and crawlers want those in <head>, so we extract them after
 * render and hoist them into the head template.
 */
function extractHeadTags(html: string): { headHtml: string; bodyHtml: string } {
  const patterns = [
    /<title>[\s\S]*?<\/title>/gi,
    /<meta\s[^>]*\/?>/gi,
    /<link\s[^>]*\/?>/gi,
    /<script\s+type="application\/ld\+json"[^>]*>[\s\S]*?<\/script>/gi,
  ]
  const lifted: string[] = []
  let body = html
  for (const p of patterns) {
    const matches = body.match(p) ?? []
    lifted.push(...matches)
    body = body.replace(p, '')
  }
  const hasTitle = lifted.some((t) => /^<title>/i.test(t))
  const hasDescription = lifted.some((t) => /<meta\s[^>]*name="description"/i.test(t))
  if (!hasTitle) lifted.unshift(DEFAULT_TITLE)
  if (!hasDescription) lifted.push(DEFAULT_DESCRIPTION)
  return { headHtml: lifted.join('\n    '), bodyHtml: body }
}

export default async function onRenderHtml(pageContext: PageContextServer) {
  const helmetContext: HelmetContext = {}

  const tree = (
    <ErrorBoundary>
      <HelmetProvider context={helmetContext}>
        <AdminAuthProvider>
          <StaticRouter location={pageContext.urlOriginal ?? '/'}>
            <Page />
          </StaticRouter>
        </AdminAuthProvider>
      </HelmetProvider>
    </ErrorBoundary>
  )

  // React 19's renderToReadableStream waits for all Suspense boundaries to
  // resolve when we await stream.allReady. This lets us keep the lazy()
  // imports in App.tsx — the server render waits for them all to load
  // before emitting HTML, so the prerendered output contains real page
  // content instead of the Suspense fallback spinner.
  const stream = await renderToReadableStream(tree)
  await stream.allReady
  const rawHtml = await new Response(stream).text()

  // helmetContext.helmet is empty under streaming SSR in react-helmet-async
  // v3 + React 19; we extract head-destined tags from the rendered HTML
  // directly. This is also more robust to future rendering-library changes.
  const { headHtml, bodyHtml } = extractHeadTags(rawHtml)

  // Still read helmet in case a future version supports streaming cleanly —
  // if it ever returns content, prefer it over the lifted tags.
  const helmet = helmetContext.helmet
  const helmetFallback = [
    helmet?.title?.toString() ?? '',
    helmet?.meta?.toString() ?? '',
    helmet?.link?.toString() ?? '',
    helmet?.script?.toString() ?? '',
  ].filter(Boolean).join('\n    ')

  return escapeInject`<!DOCTYPE html>
<html lang="en">
  <head>
    ${dangerouslySkipEscape(STATIC_HEAD)}
    ${dangerouslySkipEscape(helmetFallback)}
    ${dangerouslySkipEscape(headHtml)}
  </head>
  <body>
    <div id="root">${dangerouslySkipEscape(bodyHtml)}</div>
  </body>
</html>`
}
