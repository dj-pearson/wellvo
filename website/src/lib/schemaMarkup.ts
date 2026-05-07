/**
 * JSON-LD schema markup builder for blog posts. (US-BLOG-027)
 *
 * Always emits an Article. Conditionally emits FAQPage when the body has ≥2
 * question-style H2/H3 subheads with answers underneath, and HowTo when the
 * title looks like a how-to and the body has an ordered list of ≥3 steps.
 *
 * Designed to fail closed: if detection is uncertain, we skip the optional
 * schemas rather than emit something Google will flag.
 *
 * Used by website/src/pages/BlogPost.tsx — the JSON-LD strings are rendered
 * as <script type="application/ld+json"> tags inside react-helmet-async.
 */

const SITE_ORIGIN = 'https://dailyok.net'
const PUBLISHER_LOGO = `${SITE_ORIGIN}/icon-512.png`
const DEFAULT_AUTHOR = 'Daily OK Editorial'
const DEFAULT_LANGUAGE = 'en-US'

export interface SchemaInputPost {
  slug: string
  title: string
  excerpt: string | null
  content_html: string
  featured_image_url: string | null
  og_image_url: string | null
  category: string | null
  tags: string[]
  seo_title: string | null
  seo_description: string | null
  canonical_url: string | null
  published_at: string
  updated_at?: string | null
  author_name?: string | null
}

export interface SchemaObject {
  '@context': string
  '@type': string
  [key: string]: unknown
}

/**
 * Build every applicable JSON-LD schema for a post.
 * Always returns at least one entry (the Article).
 */
export function buildPostSchemas(post: SchemaInputPost): SchemaObject[] {
  const schemas: SchemaObject[] = [buildArticleSchema(post)]

  const faq = buildFaqSchema(post.content_html)
  if (faq) schemas.push(faq)

  const howto = buildHowToSchema(post.title, post.content_html)
  if (howto) schemas.push(howto)

  return schemas
}

// =============================================================================
// Article
// =============================================================================

export function buildArticleSchema(post: SchemaInputPost): SchemaObject {
  const url = post.canonical_url || `${SITE_ORIGIN}/blog/${post.slug}`
  const image = post.og_image_url || post.featured_image_url || `${SITE_ORIGIN}/og-image.png`
  const description = post.seo_description || post.excerpt || ''

  const schema: SchemaObject = {
    '@context': 'https://schema.org',
    '@type': 'Article',
    headline: (post.seo_title || post.title).slice(0, 110),
    description,
    image: [image],
    datePublished: post.published_at,
    dateModified: post.updated_at || post.published_at,
    author: {
      '@type': 'Person',
      name: post.author_name || DEFAULT_AUTHOR,
    },
    publisher: {
      '@type': 'Organization',
      name: 'Daily OK',
      url: SITE_ORIGIN,
      logo: {
        '@type': 'ImageObject',
        url: PUBLISHER_LOGO,
      },
    },
    mainEntityOfPage: {
      '@type': 'WebPage',
      '@id': url,
    },
    inLanguage: DEFAULT_LANGUAGE,
  }

  if (post.category) schema.articleSection = post.category
  if (post.tags.length > 0) schema.keywords = post.tags.join(', ')

  return schema
}

// =============================================================================
// FAQPage
// =============================================================================

interface FaqPair {
  question: string
  answer: string
}

export function buildFaqSchema(html: string): SchemaObject | null {
  const pairs = extractFaqPairs(html)
  if (pairs.length < 2) return null

  return {
    '@context': 'https://schema.org',
    '@type': 'FAQPage',
    mainEntity: pairs.map((p) => ({
      '@type': 'Question',
      name: p.question,
      acceptedAnswer: {
        '@type': 'Answer',
        text: p.answer,
      },
    })),
  }
}

function extractFaqPairs(html: string): FaqPair[] {
  if (!html) return []
  const doc = parseHtml(html)
  if (!doc) return []

  const pairs: FaqPair[] = []
  // Look at H2 and H3 — most posts use H2 for FAQ headings.
  const headings = Array.from(doc.querySelectorAll('h2, h3')) as HTMLElement[]

  for (const h of headings) {
    const question = textOf(h).trim()
    if (!question) continue
    if (!isQuestion(question)) continue

    // Collect the answer: walk forward through siblings until the next
    // heading. Concatenate paragraph + list text. Skip empties.
    const parts: string[] = []
    let sib = h.nextElementSibling
    while (sib && !/^H[1-6]$/.test(sib.tagName)) {
      if (sib.tagName === 'P' || sib.tagName === 'BLOCKQUOTE') {
        const t = textOf(sib).trim()
        if (t) parts.push(t)
      } else if (sib.tagName === 'UL' || sib.tagName === 'OL') {
        const items = Array.from(sib.querySelectorAll('li')).map((li) => textOf(li).trim()).filter(Boolean)
        if (items.length) parts.push(items.map((t) => `• ${t}`).join(' '))
      }
      sib = sib.nextElementSibling
    }
    const answer = parts.join(' ').trim()
    // Don't emit a Question with a trivially short answer — Google rejects those.
    if (answer.length >= 25) {
      pairs.push({ question, answer })
    }
  }

  return pairs
}

function isQuestion(text: string): boolean {
  if (text.endsWith('?')) return true
  // "How to ..." style headings are typically how-tos, not FAQ entries — skip.
  // But "How do I..." / "What if..." phrased as a Q may not have a question
  // mark. Be conservative: require explicit question mark for FAQPage.
  return false
}

// =============================================================================
// HowTo
// =============================================================================

interface HowToStep {
  name: string
  text: string
}

const HOWTO_TITLE_RE = /^\s*how\s+(to|do|can|should|long|much|often|many|will|did|i)\b/i

export function buildHowToSchema(title: string, html: string): SchemaObject | null {
  if (!HOWTO_TITLE_RE.test(title)) return null

  const steps = extractHowToSteps(html)
  if (steps.length < 3) return null

  return {
    '@context': 'https://schema.org',
    '@type': 'HowTo',
    name: title,
    step: steps.map((s, idx) => ({
      '@type': 'HowToStep',
      position: idx + 1,
      name: s.name,
      text: s.text,
    })),
  }
}

function extractHowToSteps(html: string): HowToStep[] {
  if (!html) return []
  const doc = parseHtml(html)
  if (!doc) return []

  // First OL with ≥3 LIs wins.
  const ols = Array.from(doc.querySelectorAll('ol')) as HTMLElement[]
  for (const ol of ols) {
    const items = Array.from(ol.querySelectorAll(':scope > li')) as HTMLElement[]
    if (items.length < 3) continue
    return items.map((li) => {
      const text = textOf(li).trim()
      // Step name = first sentence (or first 80 chars). Step text = full text.
      const firstSentence = text.split(/(?<=[.!?])\s+/)[0] ?? text
      const name = firstSentence.length > 80 ? `${firstSentence.slice(0, 77)}…` : firstSentence
      return { name: name || 'Step', text }
    })
  }

  return []
}

// =============================================================================
// HTML helpers
// =============================================================================

function parseHtml(html: string): Document | null {
  if (typeof DOMParser === 'undefined') return null
  try {
    return new DOMParser().parseFromString(`<!doctype html><body>${html}</body>`, 'text/html')
  } catch {
    return null
  }
}

function textOf(el: Element): string {
  return (el.textContent || '').replace(/\s+/g, ' ').trim()
}
