import type { Config } from 'vike/types'

export default {
  prerender: true,
  clientRouting: true,
  hydrationCanBeAborted: true,
  passToClient: ['routeParams', 'urlPathname'],
} satisfies Config
