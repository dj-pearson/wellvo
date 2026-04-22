import type { Config } from 'vike/types'

// Minimal Vike config. We provide our own onRenderHtml / onRenderClient
// so we can keep React Router inside the app instead of adopting Vike's
// file-based router. Vike's job here is purely SSG + hydration.
//
// Prerender is enabled globally via vite.config.ts; the list of URLs to
// generate at build time lives in +onBeforePrerenderStart.ts.

export default {
  clientRouting: true,
  hydrationCanBeAborted: true,
  // Make Supabase client + Vite env vars pass through to the SSR bundle
  // so the build doesn't fail on them even though we never actually fetch
  // during SSR (blog/admin data fetches happen only on the client).
  passToClient: ['routeParams', 'urlPathname'],
} satisfies Config
