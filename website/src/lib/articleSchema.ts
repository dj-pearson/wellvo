import { canonicalUrl } from './canonical'
import { EDITORIAL_TEAM_ID, ORGANIZATION_ID, SITE_ORIGIN, WEBSITE_ID } from './entityIds'
import type { SchemaObject } from './schemaMarkup'

/**
 * Article JSON-LD for the hand-written editorial pages (US-SEO015).
 *
 * The comparison pages, the /what-to-do guides and /welfare-check-on-elderly-
 * parent all declare og:type="article", and the guides carry a visible "Last
 * updated" byline — but only the comparison pages emitted an Article node, and
 * that one had no image and re-declared its own Organization. The guides and
 * the welfare-check page emitted no Article at all, so their publication date,
 * modification date and authorship existed only as rendered text.
 *
 * That matters most exactly where it was missing. These are YMYL,
 * health-adjacent pages about what to do when someone might be in trouble;
 * dating and attribution are the E-E-A-T signals for that class of content.
 *
 * Two deliberate choices:
 *
 *  - The author is an ORGANIZATION, "Daily OK Editorial Team", not a Person.
 *    src/data/whatToDo.ts carries a standing YMYL note: until a licensed
 *    clinician is contracted, the byline must not imply medical credentials. A
 *    Person node invites exactly that inference; an editorial team does not.
 *  - The publisher is a REFERENCE to the sitewide Organization node rather
 *    than a second copy of it. See src/lib/entityIds.ts.
 */
export interface EditorialArticleInput {
  headline: string
  description: string
  /** App path, used for the canonical unless `canonical` overrides it. */
  path: string
  canonical?: string
  /** YYYY-MM-DD or full ISO 8601. */
  datePublished: string
  dateModified?: string
  /** Absolute URL. Defaults to the sitewide card image. */
  image?: string
  /** schema.org articleSection, e.g. "Comparisons". */
  section?: string
}

/** Google truncates a headline past ~110 characters rather than using it. */
const HEADLINE_MAX = 110

export function buildEditorialArticleJsonLd(input: EditorialArticleInput): SchemaObject {
  const url = input.canonical ?? canonicalUrl(input.path)

  const schema: SchemaObject = {
    '@context': 'https://schema.org',
    '@type': 'Article',
    headline: input.headline.slice(0, HEADLINE_MAX),
    description: input.description,
    image: [input.image ?? `${SITE_ORIGIN}/og-image.png`],
    datePublished: input.datePublished,
    dateModified: input.dateModified ?? input.datePublished,
    author: {
      '@type': 'Organization',
      '@id': EDITORIAL_TEAM_ID,
      name: 'Daily OK Editorial Team',
      parentOrganization: { '@id': ORGANIZATION_ID },
    },
    publisher: { '@id': ORGANIZATION_ID },
    isPartOf: { '@id': WEBSITE_ID },
    mainEntityOfPage: { '@type': 'WebPage', '@id': url },
    inLanguage: 'en-US',
  }

  if (input.section) schema.articleSection = input.section

  return schema
}
