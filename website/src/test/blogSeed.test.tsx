import { render, screen } from '@testing-library/react'
import { MemoryRouter, Route, Routes } from 'react-router-dom'
import { HelmetProvider } from 'react-helmet-async'
import { describe, it, expect } from 'vitest'
import { BlogSeedProvider, seedFromPageContext, type BlogSeed } from '../lib/blogSeed'
import type { PublicPost, PublicPostSummary } from '../lib/blogTypes'
import Blog from '../pages/Blog'
import BlogPost from '../pages/BlogPost'

/**
 * Guards US-WEB008. The failure this protects against is silent: if the
 * prerender seed stops reaching these components, the blog still works in a
 * browser (the client-side fetch takes over) while every prerendered page
 * goes back to being empty HTML — which is precisely the state that left the
 * blog with zero indexed URLs for four months.
 */

const SUMMARY: PublicPostSummary = {
  id: 'post-1',
  slug: 'a-seeded-post',
  title: 'A seeded post',
  excerpt: 'Seeded excerpt.',
  featured_image_url: null,
  category: 'Guides',
  tags: ['seeded'],
  published_at: '2026-07-01T12:00:00.000Z',
}

const POST: PublicPost = {
  ...SUMMARY,
  content_html: '<p>Seeded body copy.</p>',
  og_image_url: null,
  seo_title: null,
  seo_description: null,
  canonical_url: null,
  updated_at: null,
}

function renderSeeded(route: string, seed: BlogSeed) {
  return render(
    <HelmetProvider>
      <BlogSeedProvider seed={seed}>
        <MemoryRouter initialEntries={[route]}>
          <Routes>
            <Route path="/blog" element={<Blog />} />
            <Route path="/blog/:slug" element={<BlogPost />} />
          </Routes>
        </MemoryRouter>
      </BlogSeedProvider>
    </HelmetProvider>,
  )
}

describe('blog prerender seed', () => {
  it('renders the index from the seed synchronously, with links to each post', () => {
    renderSeeded('/blog', { blogIndex: [SUMMARY], blogPost: null })

    // Synchronous: no findBy, no loading state. This is what makes the
    // prerendered HTML contain real links instead of a spinner.
    expect(screen.queryByText('Loading…')).not.toBeInTheDocument()
    const link = screen.getByRole('link', { name: /A seeded post/i })
    // Canonical trailing-slash form since US-WEB010 — production 308s the
    // no-slash variant, so internal links must not point through a redirect.
    expect(link).toHaveAttribute('href', '/blog/a-seeded-post/')
  })

  it('renders a post body from the seed without fetching', () => {
    renderSeeded('/blog/a-seeded-post', { blogIndex: null, blogPost: POST })

    expect(screen.queryByText('Loading…')).not.toBeInTheDocument()
    expect(screen.getByRole('heading', { level: 1, name: 'A seeded post' })).toBeInTheDocument()
    expect(screen.getByText('Seeded body copy.')).toBeInTheDocument()
  })

  it('ignores a seed whose slug does not match the route', () => {
    // Guards against a stale seed leaking one post onto another post's URL.
    renderSeeded('/blog/a-different-post', { blogIndex: null, blogPost: POST })

    expect(screen.queryByText('Seeded body copy.')).not.toBeInTheDocument()
  })

  describe('seedFromPageContext', () => {
    it('reads blogIndex and blogPost off pageContext', () => {
      const seed = seedFromPageContext({ blogIndex: [SUMMARY], blogPost: POST })
      expect(seed.blogIndex).toHaveLength(1)
      expect(seed.blogPost?.slug).toBe('a-seeded-post')
    })

    it('degrades to null rather than throwing on absent or malformed context', () => {
      // Vike round-trips pageContext through JSON; anything unexpected must
      // fall back to the client-side fetch, never render a broken page.
      for (const ctx of [undefined, null, {}, { blogPost: 'nope' }, { blogIndex: 42 }]) {
        const seed = seedFromPageContext(ctx)
        expect(seed.blogIndex).toBeNull()
        expect(seed.blogPost).toBeNull()
      }
    })
  })
})
