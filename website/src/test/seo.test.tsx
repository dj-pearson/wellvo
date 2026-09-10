import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { render, waitFor } from '@testing-library/react'
import { HelmetProvider } from 'react-helmet-async'
import { describe, it, expect, beforeEach } from 'vitest'
import SEO, {
  DEFAULT_IMAGE,
  DEFAULT_IMAGE_WIDTH,
  DEFAULT_IMAGE_HEIGHT,
  DEFAULT_IMAGE_TYPE,
} from '../components/SEO'

/**
 * Guards US-SEO005 — the social card contract.
 *
 * Two failures this closes, both invisible from inside the app: og:image had
 * no declared size, so consumers that lay the card out before the image lands
 * fell back to a small thumbnail; and the two page families that hand-rolled
 * their own <Helmet> (comparison pages, blog posts) emitted no og:image and
 * no twitter:card at all, so they shared as bare links.
 */

function head() {
  return document.head.innerHTML
}

function meta(selector: string): string | null {
  return document.head.querySelector(selector)?.getAttribute('content') ?? null
}

beforeEach(() => {
  document.head.innerHTML = ''
})

async function renderSEO(props: Parameters<typeof SEO>[0]) {
  render(
    <HelmetProvider>
      <SEO {...props} />
    </HelmetProvider>,
  )
  await waitFor(() => expect(head()).toContain('og:image'))
}

const BASE = {
  title: 'Check-In App for Elderly Parents',
  description: 'One tap a day, automatic alerts if it is missed.',
  path: '/check-in-app-for-elderly',
}

describe('the declared default card image', () => {
  it('states the real dimensions of public/og-image.png', () => {
    // A wrong number here is worse than none: the consumer trusts it for the
    // aspect ratio and crops to it. Read the PNG's IHDR rather than the
    // filename or a memory of what it used to be.
    const png = readFileSync(resolve(__dirname, '../../public/og-image.png'))
    expect(png.subarray(1, 4).toString('ascii')).toBe('PNG')
    expect(png.subarray(12, 16).toString('ascii')).toBe('IHDR')
    const width = png.readUInt32BE(16)
    const height = png.readUInt32BE(20)

    expect(String(width)).toBe(DEFAULT_IMAGE_WIDTH)
    expect(String(height)).toBe(DEFAULT_IMAGE_HEIGHT)
    expect(DEFAULT_IMAGE_TYPE).toBe('image/png')
    // 1.91:1 is what the large-summary card is laid out for.
    expect(width / height).toBeCloseTo(1.91, 1)
  })
})

describe('<SEO> on a normal page', () => {
  it('declares the image with its size and type', async () => {
    await renderSEO(BASE)
    expect(meta('meta[property="og:image"]')).toBe(DEFAULT_IMAGE)
    expect(meta('meta[property="og:image:width"]')).toBe(DEFAULT_IMAGE_WIDTH)
    expect(meta('meta[property="og:image:height"]')).toBe(DEFAULT_IMAGE_HEIGHT)
    expect(meta('meta[property="og:image:type"]')).toBe(DEFAULT_IMAGE_TYPE)
    expect(meta('meta[property="og:locale"]')).toBe('en_US')
    expect(meta('meta[name="twitter:card"]')).toBe('summary_large_image')
    expect(meta('meta[property="og:image:alt"]')).toContain('Daily OK')
  })

  it('emits exactly one og:image and one twitter:image', async () => {
    await renderSEO(BASE)
    expect(document.head.querySelectorAll('meta[property="og:image"]')).toHaveLength(1)
    expect(document.head.querySelectorAll('meta[name="twitter:image"]')).toHaveLength(1)
  })

  it('omits article timestamps when the page is not an article', async () => {
    await renderSEO({ ...BASE, publishedTime: '2026-01-01T00:00:00Z' })
    expect(meta('meta[property="article:published_time"]')).toBeNull()
  })
})

describe('<SEO> with a per-page image', () => {
  const withImage = {
    ...BASE,
    path: '/blog/a-post',
    ogType: 'article',
    image: 'https://cdn.example.com/featured.jpg',
    imageAlt: 'A post',
    publishedTime: '2026-01-01T00:00:00Z',
    modifiedTime: '2026-02-01T00:00:00Z',
  }

  it('uses it for both og and twitter', async () => {
    await renderSEO(withImage)
    expect(meta('meta[property="og:image"]')).toBe(withImage.image)
    expect(meta('meta[name="twitter:image"]')).toBe(withImage.image)
    expect(meta('meta[property="og:image:alt"]')).toBe('A post')
  })

  it('omits width/height/type, whose values it cannot know', async () => {
    await renderSEO(withImage)
    expect(meta('meta[property="og:image:width"]')).toBeNull()
    expect(meta('meta[property="og:image:height"]')).toBeNull()
    expect(meta('meta[property="og:image:type"]')).toBeNull()
  })

  it('emits article timestamps for an article', async () => {
    await renderSEO(withImage)
    expect(meta('meta[property="article:published_time"]')).toBe(withImage.publishedTime)
    expect(meta('meta[property="article:modified_time"]')).toBe(withImage.modifiedTime)
  })

  it('honours an explicit canonical over the derived one', async () => {
    await renderSEO({ ...withImage, canonical: 'https://elsewhere.example/original/' })
    expect(document.head.querySelector('link[rel="canonical"]')?.getAttribute('href')).toBe(
      'https://elsewhere.example/original/',
    )
  })
})

describe('<SEO noindex>', () => {
  it('emits noindex, follow — not none', async () => {
    // A 404's links are still worth crawling even though the page must never
    // rank. "none" would throw that away with nothing gained.
    await renderSEO({ ...BASE, path: '/404', noindex: true })
    expect(meta('meta[name="robots"]')).toBe('noindex, follow')
  })

  it('omits the canonical, which would contradict the robots tag', async () => {
    await renderSEO({ ...BASE, path: '/404', noindex: true })
    expect(document.head.querySelector('link[rel="canonical"]')).toBeNull()
  })

  it('still emits a canonical on a normal page', async () => {
    await renderSEO(BASE)
    expect(document.head.querySelector('link[rel="canonical"]')).not.toBeNull()
    expect(meta('meta[name="robots"]')).toBeNull()
  })
})

describe('JSON-LD serialization', () => {
  it('escapes < so operator-authored text cannot close the script tag', async () => {
    await renderSEO({
      ...BASE,
      jsonLd: { '@type': 'Article', headline: 'Mom </script><script>alert(1)</script>' },
    })
    // react-helmet-async v3 does not move a <script> child into <head> on the
    // client — pages/+onRenderHtml.tsx's extractHeadTags() is what hoists it
    // during prerender. So query the whole document, which is where it is
    // here, and assert the payload rather than its position.
    const script = document.querySelector('script[type="application/ld+json"]')
    expect(script).not.toBeNull()
    const payload = script!.textContent ?? ''
    expect(payload).not.toContain('</script>')
    expect(payload).toContain('\\u003c')
    // Still valid JSON, and the text survives intact once parsed.
    expect(JSON.parse(payload).headline).toBe('Mom </script><script>alert(1)</script>')
  })
})
