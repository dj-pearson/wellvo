import { useEffect, useMemo, useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { Helmet } from 'react-helmet-async'
import DOMPurify from 'dompurify'
import { getSupabase, isSupabaseConfigured } from '../lib/supabase'
import './Blog.css'

interface PublicPost {
  id: string
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
}

export default function BlogPost() {
  const { slug } = useParams<{ slug: string }>()
  const [post, setPost] = useState<PublicPost | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (!slug) return
    if (!isSupabaseConfigured()) {
      setError('Blog is not configured yet.')
      setLoading(false)
      return
    }
    const supabase = getSupabase()
    supabase
      .from('blog_posts')
      .select('id, slug, title, excerpt, content_html, featured_image_url, og_image_url, category, tags, seo_title, seo_description, canonical_url, published_at')
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
  }, [slug])

  const safeHtml = useMemo(() => {
    if (!post?.content_html) return ''
    return DOMPurify.sanitize(post.content_html, {
      ALLOWED_TAGS: ['h1','h2','h3','h4','p','ul','ol','li','strong','em','b','i','a','blockquote','br','hr','img','code','pre','figure','figcaption'],
      ALLOWED_ATTR: ['href','src','alt','title','rel','target'],
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
        {post.canonical_url && <link rel="canonical" href={post.canonical_url} />}
        <meta property="og:title" content={seoTitle} />
        {seoDescription && <meta property="og:description" content={seoDescription} />}
        {ogImage && <meta property="og:image" content={ogImage} />}
        <meta property="og:type" content="article" />
        <meta property="article:published_time" content={post.published_at} />
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
            <img src={post.featured_image_url} alt="" className="blog-article-hero" />
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
