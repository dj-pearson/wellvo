import { Helmet } from 'react-helmet-async'

const APP_STORE_URL = 'https://apps.apple.com/us/app/dailyok-daily-check-in/id6760836697'
const SITE_URL = 'https://dailyok.net'
const DEFAULT_IMAGE = `${SITE_URL}/og-image.png`
const DEFAULT_IMAGE_ALT =
  'Daily OK — the senior check-in app: a once-a-day "I\'m OK" from your aging parent, with alerts if they miss it.'

interface SEOProps {
  title: string
  description: string
  path: string
  keywords?: string
  ogType?: string
  jsonLd?: Record<string, unknown> | Record<string, unknown>[]
}

export default function SEO({
  title,
  description,
  path,
  keywords,
  ogType = 'website',
  jsonLd,
}: SEOProps) {
  const fullUrl = `${SITE_URL}${path}`
  const fullTitle = path === '/' ? title : `${title} | Daily OK`

  return (
    <Helmet>
      <title>{fullTitle}</title>
      <meta name="description" content={description} />
      {keywords && <meta name="keywords" content={keywords} />}
      <link rel="canonical" href={fullUrl} />

      {/* Open Graph */}
      <meta property="og:title" content={fullTitle} />
      <meta property="og:description" content={description} />
      <meta property="og:type" content={ogType} />
      <meta property="og:url" content={fullUrl} />
      <meta property="og:image" content={DEFAULT_IMAGE} />
      <meta property="og:image:alt" content={DEFAULT_IMAGE_ALT} />
      <meta property="og:site_name" content="Daily OK" />

      {/* Twitter */}
      <meta name="twitter:card" content="summary_large_image" />
      <meta name="twitter:title" content={fullTitle} />
      <meta name="twitter:description" content={description} />
      <meta name="twitter:image" content={DEFAULT_IMAGE} />
      <meta name="twitter:image:alt" content={DEFAULT_IMAGE_ALT} />

      {/* Structured Data */}
      {jsonLd && (
        <script type="application/ld+json">
          {JSON.stringify(Array.isArray(jsonLd) ? jsonLd : jsonLd)}
        </script>
      )}
    </Helmet>
  )
}

export { APP_STORE_URL, SITE_URL }
