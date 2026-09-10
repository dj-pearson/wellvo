import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import SEO from '../components/SEO'
import { buildBreadcrumbJsonLd } from '../lib/breadcrumb'
import { getSupabase, isSupabaseConfigured } from '../lib/supabase'
import { useBlogSeed } from '../lib/blogSeedContext'
import { POST_SUMMARY_COLUMNS, type PublicPostSummary } from '../lib/blogTypes'
import './Blog.css'

export default function Blog() {
  // Seeded at build time by +onBeforePrerenderStart.ts so the prerendered
  // HTML carries real <a href="/blog/..."> links. Without them Googlebot had
  // no path into the blog at all (US-WEB008). Absent on client-side
  // navigation and for a build with no Supabase config — then we fetch.
  const { blogIndex } = useBlogSeed()

  // Whether Supabase is configured is a synchronous fact about the build, not
  // something to discover in an effect. Deriving it during render — rather
  // than setting error state from inside useEffect — is what
  // react-hooks/set-state-in-effect is asking for, and it removes a render
  // pass on every unconfigured build (US-SEO002).
  const needsFetch = blogIndex === null && isSupabaseConfigured()
  const unconfigured = blogIndex === null && !isSupabaseConfigured()

  const [posts, setPosts] = useState<PublicPostSummary[]>(blogIndex ?? [])
  const [loading, setLoading] = useState(needsFetch)
  const [fetchError, setFetchError] = useState<string | null>(null)
  const error = unconfigured ? 'Blog is not configured yet.' : fetchError

  useEffect(() => {
    if (!needsFetch) return
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
          setFetchError(err.message)
          setLoading(false)
          return
        }
        setPosts((data as PublicPostSummary[]) ?? [])
        setLoading(false)
      })
  }, [needsFetch])

  return (
    <>
      {/*
        Was a hand-rolled <Helmet> with a title, a description and a canonical
        and nothing else — no og:image, no og:type, no twitter:card at all
        (US-SEO017). Every share of the blog index rendered as a bare link.
      */}
      <SEO
        title="Blog"
        description="Guides, tips and stories about daily check-ins, caregiving, and keeping an eye on someone without hovering."
        path="/blog"
        jsonLd={buildBreadcrumbJsonLd([
          { name: 'Home', path: '/' },
          { name: 'Blog', path: '/blog' },
        ])}
      />

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
              <Link to={`/blog/${p.slug}/`} key={p.id} className="blog-card">
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
