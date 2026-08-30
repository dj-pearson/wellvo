/**
 * Canonical URL construction (US-WEB010).
 *
 * Cloudflare Pages serves this site in its TRAILING-SLASH form. Vike
 * prerenders each route to `dist/client/<route>/index.html`, and Pages serves
 * that directory-style file at `/pricing/` while issuing a 308 from `/pricing`.
 * Verified against production:
 *
 *     curl -sSI https://dailyok.net/pricing   ->  308, Location: /pricing/
 *     curl -sSI https://dailyok.net/pricing/  ->  200
 *
 * Every canonical tag, sitemap <loc>, JSON-LD url and internal link previously
 * used the NO-slash form, so each one pointed at a URL that immediately
 * redirects. Google was being told "the canonical is /pricing" while /pricing
 * redirected to /pricing/ — a self-contradictory signal, and the reason
 * Search Console indexed both (114 impressions on /pricing/, 14 on /pricing).
 *
 * The fix is to state what the server actually does rather than to change the
 * server: adopt the trailing-slash form everywhere. That also keeps the
 * variant Google already prefers, instead of redirecting the stronger URL to
 * the weaker one.
 *
 * The root path is the one exception — `https://dailyok.net/` is already the
 * slash form and must not become `//`.
 */

export const SITE_ORIGIN = 'https://dailyok.net'

/**
 * Normalize an app path to the canonical trailing-slash form.
 * Leaves query strings and fragments alone — they are not part of a canonical.
 */
export function canonicalPath(path: string): string {
  const withLeadingSlash = path.startsWith('/') ? path : `/${path}`
  if (withLeadingSlash === '/') return '/'
  // Don't mangle a path that carries a fragment or query; canonicals should
  // not have them, but a caller passing one should not get `/foo#bar/`.
  if (/[?#]/.test(withLeadingSlash)) return withLeadingSlash
  return withLeadingSlash.endsWith('/') ? withLeadingSlash : `${withLeadingSlash}/`
}

/** Absolute canonical URL for an app path. */
export function canonicalUrl(path: string): string {
  return `${SITE_ORIGIN}${canonicalPath(path)}`
}
