import DOMPurify from 'dompurify'
import { JSDOM } from 'jsdom'
import { describe, it, expect } from 'vitest'
import { BLOG_BLANK_TARGET_REL, BLOG_HTML_ALLOWLIST, hardenBlogLinks } from '../lib/blogTypes'

/**
 * Post bodies are author- and LLM-written and the allowlist keeps `target`
 * and `rel`, so a new-tab link must leave the sanitizer with a rel we chose,
 * in both the browser instance and the jsdom-backed prerender instance.
 */

const CONFIG = {
  ALLOWED_TAGS: [...BLOG_HTML_ALLOWLIST.ALLOWED_TAGS],
  ALLOWED_ATTR: [...BLOG_HTML_ALLOWLIST.ALLOWED_ATTR],
}

function links(html: string): HTMLAnchorElement[] {
  const doc = new DOMParser().parseFromString(html, 'text/html')
  return [...doc.querySelectorAll('a')]
}

describe('hardenBlogLinks', () => {
  it('forces rel on target=_blank links and replaces an author rel', () => {
    const out = hardenBlogLinks(DOMPurify).sanitize(
      '<p><a href="https://a.example" target="_blank">a</a>' +
        '<a href="https://b.example" target="_BLANK" rel="opener">b</a>' +
        '<a href="/pricing">c</a></p>',
      CONFIG,
    )
    const [a, b, c] = links(out)
    expect(a.getAttribute('rel')).toBe(BLOG_BLANK_TARGET_REL)
    expect(b.getAttribute('rel')).toBe(BLOG_BLANK_TARGET_REL)
    expect(c.hasAttribute('rel')).toBe(false)
  })

  it('registers the hook once per instance', () => {
    const purify = DOMPurify(new JSDOM('').window as unknown as Window & typeof globalThis)
    let calls = 0
    const addHook = purify.addHook.bind(purify)
    purify.addHook = ((...args: Parameters<typeof addHook>) => {
      calls++
      return addHook(...args)
    }) as typeof purify.addHook
    expect(hardenBlogLinks(purify)).toBe(purify)
    hardenBlogLinks(purify)
    expect(calls).toBe(1)
  })

  it('applies to a jsdom-backed instance like the prerenderer uses', () => {
    const purify = hardenBlogLinks(
      DOMPurify(new JSDOM('').window as unknown as Window & typeof globalThis),
    )
    const out = purify.sanitize('<a href="https://x.example" target="_blank">x</a>', CONFIG)
    expect(links(out)[0].getAttribute('rel')).toBe(BLOG_BLANK_TARGET_REL)
  })
})
