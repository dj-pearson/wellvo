import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { Helmet } from 'react-helmet-async'
import { getSupabase, isSupabaseConfigured } from '../lib/supabase'
import './Blog.css'

interface PublicPost {
  id: string
  slug: string
  title: string
  excerpt: string | null
  featured_image_url: string | null
  category: string | null
  tags: string[]
  published_at: string
}

export default function Blog() {
  const [posts, setPosts] = useState<PublicPost[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (!isSupabaseConfigured()) {
      setError('Blog is not configured yet.')
      setLoading(false)
      return
    }
    const supabase = getSupabase()
    supabase
      .from('blog_posts')
      .select('id, slug, title, excerpt, featured_image_url, category, tags, published_at')
      .eq('status', 'published')
      .lte('published_at', new Date().toISOString())
      .order('published_at', { ascending: false })
      .limit(100)
      .then(({ data, error: err }) => {
        if (err) {
          setError(err.message)
          setLoading(false)
          return
        }
        setPosts((data as PublicPost[]) ?? [])
        setLoading(false)
      })
  }, [])

  return (
    <>
      <Helmet>
        <title>Blog — Daily OK</title>
        <meta name="description" content="Guides, tips, and stories about daily check-ins, caregiving, and family safety." />
      </Helmet>

      <section className="blog-hero">
        <div className="container">
          <h1>Daily OK Blog</h1>
          <p>Practical guides for caregivers, families, and anyone looking out for someone.</p>
        </div>
      </section>

      <section className="section">
        <div className="container">
          {loading && <div className="blog-empty">Loading…</div>}
          {error && <div className="blog-empty">{error}</div>}
          {!loading && !error && posts.length === 0 && (
            <div className="blog-empty">No posts yet. Check back soon.</div>
          )}

          <div className="blog-grid">
            {posts.map((p) => (
              <Link to={`/blog/${p.slug}`} key={p.id} className="blog-card">
                {p.featured_image_url && (
                  <div className="blog-card-image" style={{ backgroundImage: `url(${p.featured_image_url})` }} />
                )}
                <div className="blog-card-body">
                  {p.category && <span className="blog-card-cat">{p.category}</span>}
                  <h2>{p.title}</h2>
                  {p.excerpt && <p>{p.excerpt}</p>}
                  <div className="blog-card-meta">
                    {new Date(p.published_at).toLocaleDateString(undefined, {
                      year: 'numeric', month: 'short', day: 'numeric',
                    })}
                  </div>
                </div>
              </Link>
            ))}
          </div>
        </div>
      </section>
    </>
  )
}
