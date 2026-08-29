import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { Helmet } from 'react-helmet-async'
import { getSupabase, isSupabaseConfigured } from '../lib/supabase'
import { useBlogSeed } from '../lib/blogSeed'
import { POST_SUMMARY_COLUMNS, type PublicPostSummary } from '../lib/blogTypes'
import { SITE_URL } from '../components/SEO'
import './Blog.css'

export default function Blog() {
  // Seeded at build time by +onBeforePrerenderStart.ts so the prerendered
  // HTML carries real <a href="/blog/..."> links. Without them Googlebot had
  // no path into the blog at all (US-WEB008). Absent on client-side
  // navigation and for a build with no Supabase config — then we fetch.
  const { blogIndex } = useBlogSeed()
  const [posts, setPosts] = useState<PublicPostSummary[]>(blogIndex ?? [])
  const [loading, setLoading] = useState(blogIndex === null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (blogIndex !== null) return
    if (!isSupabaseConfigured()) {
      setError('Blog is not configured yet.')
      setLoading(false)
      return
    }
    const supabase = getSupabase()
    supabase
      .from('blog_posts')
      .select(POST_SUMMARY_COLUMNS)
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
        setPosts((data as PublicPostSummary[]) ?? [])
        setLoading(false)
      })
  }, [blogIndex])

  return (
    <>
      <Helmet>
        <title>Blog — Daily OK</title>
        <meta name="description" content="Guides, tips, and stories about daily check-ins, caregiving, and family safety." />
        <link rel="canonical" href={`${SITE_URL}/blog`} />
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
