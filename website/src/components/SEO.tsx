import { Helmet } from 'react-helmet-async'
import { canonicalUrl } from '../lib/canonical'

const APP_STORE_URL = 'https://apps.apple.com/us/app/dailyok-daily-check-in/id6760836697'
const SITE_URL = 'https://dailyok.net'
const DEFAULT_IMAGE = `${SITE_URL}/og-image.png`
const DEFAULT_IMAGE_ALT =
  'Daily OK — the senior check-in app: a once-a-day "I\'m OK" from your aging parent, with alerts if they miss it.'

/**
 * Real, measured dimensions of public/og-image.png (US-SEO005).
 *
 * These are not decoration. Facebook, LinkedIn and Slack lay the card out
 * before the image finishes downloading: without width and height they either
 * render a small square thumbnail or reflow once the fetch lands, and on a
 * first-ever share they frequently show no image at all because the scrape and
 * the render race. Declaring the real size lets the large-summary card be laid
 * out immediately.
 *
 * Stated as strings because that is what goes in the attribute, and asserted
 * against the actual file by src/test/seo.test.tsx — a wrong number here is
 * worse than none, since the consumer trusts it for the aspect ratio.
 */
const DEFAULT_IMAGE_WIDTH = '1200'
const DEFAULT_IMAGE_HEIGHT = '630'
const DEFAULT_IMAGE_TYPE = 'image/png'

interface SEOProps {
  title: string
  description: string
  path: string
  keywords?: string
  ogType?: string
  jsonLd?: Record<string, unknown> | Record<string, unknown>[]
  /**
   * Per-page social image, absolute URL. Blog posts carry their own featured
   * image; everything else shares the sitewide card. When this is set the
   * width/height/type hints are omitted, because the dimensions of a remote
   * image uploaded through the admin are not known at render time and a
   * guessed one would be a lie the consumer acts on.
   */
  image?: string
  imageAlt?: string
  /**
   * Overrides the derived canonical. Only for pages that carry an explicit
   * canonical of their own — a blog post may point at an original elsewhere.
   */
  canonical?: string
  /** ISO timestamps, emitted only for ogType="article". */
  publishedTime?: string
  modifiedTime?: string
  /**
   * Emits `robots: noindex, follow`. "follow" rather than "none" on purpose:
   * a page can be unfit to rank while its outbound links are still worth
   * crawling — the 404 page is exactly that case (US-SEO016). The sitemap and
   * llms.txt generators both skip any page carrying this tag, so setting it is
   * the whole opt-out.
   */
  noindex?: boolean
  /**
   * Appends " | Daily OK" to the title. Default true. Set false when the
   * title already names the brand — "Daily OK vs. Life Alert: Honest
   * Comparison (2026) | Daily OK" says it twice and spends 11 of the ~60
   * characters Google renders on the repetition (US-SEO008).
   */
  appendBrand?: boolean
}

/**
 * JSON-LD goes inside a <script>, where the parser is looking for `</script>`
 * rather than for JSON. Any `<` in title, description or post content would
 * otherwise be able to close the tag early; escaping it keeps the payload
 * valid JSON and inert as markup. Blog posts carry operator- and
 * LLM-authored text, so this is a real path, not a theoretical one.
 */
function serializeJsonLd(value: unknown): string {
  return JSON.stringify(value).replace(/</g, '\\u003c')
}

export default function SEO({
  title,
  description,
  path,
  keywords,
  ogType = 'website',
  jsonLd,
  image,
  imageAlt,
  canonical,
  publishedTime,
  modifiedTime,
  appendBrand = true,
  noindex = false,
}: SEOProps) {
  // Trailing-slash form — that is what production serves (US-WEB010).
  const fullUrl = canonical ?? canonicalUrl(path)
  const fullTitle = path === '/' || !appendBrand ? title : `${title} | Daily OK`
  const imageUrl = image ?? DEFAULT_IMAGE
  const imageAltText = imageAlt ?? DEFAULT_IMAGE_ALT
  const isDefaultImage = image === undefined
  const isArticle = ogType === 'article'

  return (
    <Helmet>
      <title>{fullTitle}</title>
      <meta name="description" content={description} />
      {noindex && <meta name="robots" content="noindex, follow" />}
      {keywords && <meta name="keywords" content={keywords} />}
      {/*
        No canonical on a noindex page (US-SEO016). The 404 is served from
        /404.html at whatever URL the visitor actually asked for, so a
        self-canonical would point at a URL that does not exist — and a
        canonical is a request to index THIS one, which contradicts the robots
        tag directly above it.
      */}
      {!noindex && <link rel="canonical" href={fullUrl} />}

      {/* Open Graph */}
      <meta property="og:title" content={fullTitle} />
      <meta property="og:description" content={description} />
      <meta property="og:type" content={ogType} />
      <meta property="og:url" content={fullUrl} />
      <meta property="og:image" content={imageUrl} />
      <meta property="og:image:alt" content={imageAltText} />
      {isDefaultImage && <meta property="og:image:width" content={DEFAULT_IMAGE_WIDTH} />}
      {isDefaultImage && <meta property="og:image:height" content={DEFAULT_IMAGE_HEIGHT} />}
      {isDefaultImage && <meta property="og:image:type" content={DEFAULT_IMAGE_TYPE} />}
      <meta property="og:site_name" content="Daily OK" />
      <meta property="og:locale" content="en_US" />
      {isArticle && publishedTime && (
        <meta property="article:published_time" content={publishedTime} />
      )}
      {isArticle && modifiedTime && (
        <meta property="article:modified_time" content={modifiedTime} />
      )}

      {/* Twitter */}
      <meta name="twitter:card" content="summary_large_image" />
      <meta name="twitter:title" content={fullTitle} />
      <meta name="twitter:description" content={description} />
      <meta name="twitter:image" content={imageUrl} />
      <meta name="twitter:image:alt" content={imageAltText} />

      {/* Structured Data */}
      {jsonLd && (
        <script type="application/ld+json">{serializeJsonLd(jsonLd)}</script>
      )}
    </Helmet>
  )
}

export {
  APP_STORE_URL,
  SITE_URL,
  DEFAULT_IMAGE,
  DEFAULT_IMAGE_WIDTH,
  DEFAULT_IMAGE_HEIGHT,
  DEFAULT_IMAGE_TYPE,
}
