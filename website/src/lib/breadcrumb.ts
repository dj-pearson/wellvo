/** BreadcrumbList JSON-LD builder. Shared by the cornerstone landing pages
 *  (US-WEB003) and reusable by other nested pages. */

const SITE_ORIGIN = 'https://dailyok.net'

export interface Crumb {
  name: string
  /** Path beginning with "/" (e.g. "/pricing"). Use "/" for Home. */
  path: string
}

export function buildBreadcrumbJsonLd(crumbs: Crumb[]): Record<string, unknown> {
  return {
    '@context': 'https://schema.org',
    '@type': 'BreadcrumbList',
    itemListElement: crumbs.map((c, i) => ({
      '@type': 'ListItem',
      position: i + 1,
      name: c.name,
      item: `${SITE_ORIGIN}${c.path === '/' ? '' : c.path}` || SITE_ORIGIN,
    })),
  }
}
