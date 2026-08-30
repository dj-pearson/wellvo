import type { Config } from 'vike/types'

export default {
  prerender: { disableAutoRun: true },
  clientRouting: true,
  hydrationCanBeAborted: true,
  // blogIndex / blogPost are seeded by +onBeforePrerenderStart.ts so the
  // client's first render matches the prerendered HTML (US-WEB008).
  passToClient: ['routeParams', 'urlPathname', 'blogIndex', 'blogPost'],
} satisfies Config
