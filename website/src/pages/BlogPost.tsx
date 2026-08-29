import { useEffect, useMemo, useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { Helmet } from 'react-helmet-async'
import DOMPurify from 'dompurify'
import { getSupabase, isSupabaseConfigured } from '../lib/supabase'
import { buildPostSchemas } from '../lib/schemaMarkup'
import { buildBreadcrumbJsonLd } from '../lib/breadcrumb'
import { useBlogSeed } from '../lib/blogSeed'
import { BLOG_HTML_ALLOWLIST, POST_COLUMNS, type PublicPost } from '../lib/blogTypes'
import { SITE_URL } from '../components/SEO'
import './Blog.css'


export default function BlogPost() {
  const { slug } = useParams<{ slug: string }>()

  // Seeded at build time by +onBeforePrerenderStart.ts. Before US-WEB008 the
  // post was only ever fetched in the effect below, which does not run during
  // prerender — so every post URL was served the homepage's HTML and the whole
  // blog was invisible to search engines.
  const { blogPost } = useBlogSeed()
  const seeded = blogPost && blogPost.slug === slug ? blogPost : null

  const [post, setPost] = useState<PublicPost | null>(seeded)
  const [loading, setLoading] = useState(seeded === null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (!slug) return
    if (seeded) return
    if (!isSupabaseConfigured()) {
      setError('Blog is not configured yet.')
      setLoading(false)
      return
    }
    const supabase = getSupabase()
    supabase
      .from('blog_posts')
      .select(POST_COLUMNS)
      .eq('slug', slug)
      .eq('status', 'published')
      .lte('published_at', new Date().toISOString())
      .maybeSingle()
      .then(({ data, error: err }) => {
        if (err) {
          setError(err.message)
          setLoading(false)
          return
        }
        if (!data) {
          setError('not found')
          setLoading(false)
          return
        }
        setPost(data as PublicPost)
        setLoading(false)
      })
  }, [slug, seeded])

  const safeHtml = useMemo(() => {
    if (!post?.content_html) return ''
    // A seeded post was already sanitized in Node with the same allowlist
    // (pages/fetchBlogForPrerender.ts). Sanitizing again here would produce a
    // second pass over identical markup and risk a hydration mismatch, so the
    // browser only sanitizes what it fetched itself.
    if (seeded && post === seeded) return post.content_html
    return DOMPurify.sanitize(post.content_html, {
      ALLOWED_TAGS: [...BLOG_HTML_ALLOWLIST.ALLOWED_TAGS],
      ALLOWED_ATTR: [...BLOG_HTML_ALLOWLIST.ALLOWED_ATTR],
    })
  }, [post, seeded])

  // Article + (conditionally) FAQPage / HowTo JSON-LD. Computed against the
  // unsanitized content_html so structural detection sees the same DOM the
  // server originally rendered. Sanitizer runs separately on the visible body.
  const schemas = useMemo(() => {
    if (!post) return []
    return buildPostSchemas({
      slug: post.slug,
      title: post.title,
      excerpt: post.excerpt,
      content_html: post.content_html,
      featured_image_url: post.featured_image_url,
      og_image_url: post.og_image_url,
      category: post.category,
      tags: post.tags,
      seo_title: post.seo_title,
      seo_description: post.seo_description,
      canonical_url: post.canonical_url,
      published_at: post.published_at,
      updated_at: post.updated_at,
    })
  }, [post])

  if (loading) {
    return (
      <section className="section">
        <div className="container"><div className="blog-empty">Loading…</div></div>
      </section>
    )
  }

  if (error || !post) {
    return (
      <section className="section">
        <div className="container">
          <div className="blog-empty">
            <h2>Post not found</h2>
            <p><Link to="/blog">Back to blog</Link></p>
          </div>
        </div>
      </section>
    )
  }

  const seoTitle = post.seo_title || post.title
  const seoDescription = post.seo_description || post.excerpt || undefined
  const ogImage = post.og_image_url || post.featured_image_url || undefined

  return (
    <>
      <Helmet>
        <title>{`${seoTitle} — Daily OK`}</title>
        {seoDescription && <meta name="description" content={seoDescription} />}
        <link rel="canonical" href={post.canonical_url || `${SITE_URL}/blog/${post.slug}`} />
        <meta property="og:url" content={post.canonical_url || `${SITE_URL}/blog/${post.slug}`} />
        <meta property="og:title" content={seoTitle} />
        {seoDescription && <meta property="og:description" content={seoDescription} />}
        {ogImage && <meta property="og:image" content={ogImage} />}
        <meta property="og:type" content="article" />
        <meta property="article:published_time" content={post.published_at} />
        {post.updated_at && (
          <meta property="article:modified_time" content={post.updated_at} />
        )}
        {schemas.map((schema, i) => (
          <script key={i} type="application/ld+json">
            {JSON.stringify(schema).replace(/</g, '\\u003c')}
          </script>
        ))}
        <script type="application/ld+json">
          {JSON.stringify(
            buildBreadcrumbJsonLd([
              { name: 'Home', path: '/' },
              { name: 'Blog', path: '/blog' },
              { name: post.title, path: `/blog/${post.slug}` },
            ]),
          ).replace(/</g, '\\u003c')}
        </script>
      </Helmet>

      <article className="blog-article">
        <div className="container" style={{ maxWidth: 760 }}>
          <div className="blog-article-meta">
            <Link to="/blog">← All posts</Link>
            <span>{new Date(post.published_at).toLocaleDateString(undefined, { year: 'numeric', month: 'long', day: 'numeric' })}</span>
          </div>
          {post.category && <span className="blog-card-cat" style={{ marginBottom: 10 }}>{post.category}</span>}
          <h1>{post.title}</h1>
          {post.excerpt && <p className="blog-article-lede">{post.excerpt}</p>}
          {post.featured_image_url && (
            <img src={post.featured_image_url} alt={post.title} className="blog-article-hero" />
          )}

          <div className="blog-article-body" dangerouslySetInnerHTML={{ __html: safeHtml }} />

          {post.tags.length > 0 && (
            <div className="blog-article-tags">
              {post.tags.map((t) => <span key={t} className="blog-tag">{t}</span>)}
            </div>
          )}
        </div>
      </article>
    </>
  )
}
