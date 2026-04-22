import { useEffect, useRef, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { Plus, Trash2, Edit3, Sparkles, Wand2, Loader2, CheckCircle2, AlertCircle } from 'lucide-react'
import {
  listPosts,
  deletePost,
  getBlogBankStatus,
  generateNextFromBank,
  type BlogPostListItem,
  type BlogBankStatus,
} from '../lib/admin'
import './admin.css'

interface GenerationOutcome {
  title: string
  slug: string
  post_id: string
  source: 'blog_title_bank' | 'fallback'
  url: string
}

type StatusFilter = 'all' | 'draft' | 'published' | 'archived'

export default function AdminBlog() {
  const [posts, setPosts] = useState<BlogPostListItem[]>([])
  const [total, setTotal] = useState(0)
  const [status, setStatus] = useState<StatusFilter>('all')
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [bank, setBank] = useState<BlogBankStatus | null>(null)
  const [bankLoading, setBankLoading] = useState(false)
  const [generating, setGenerating] = useState(false)
  const [generatingTitle, setGeneratingTitle] = useState<string | null>(null)
  const [generatingSource, setGeneratingSource] = useState<'blog_title_bank' | 'fallback' | null>(null)
  const [genError, setGenError] = useState<string | null>(null)
  const [lastGenerated, setLastGenerated] = useState<GenerationOutcome | null>(null)
  const [topicHint, setTopicHint] = useState('')
  const [showTopicHint, setShowTopicHint] = useState(false)
  const navigate = useNavigate()
  // Snapshots taken at generation start, used to detect success vs failure on poll
  const startSnapshotRef = useRef<{ published: number; failed: number } | null>(null)

  const fetchPosts = async () => {
    setLoading(true)
    setError(null)
    try {
      const res = await listPosts({ status, limit: 100 })
      setPosts(res.posts)
      setTotal(res.total)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load posts')
    } finally {
      setLoading(false)
    }
  }

  const fetchBank = async () => {
    setBankLoading(true)
    try {
      setBank(await getBlogBankStatus())
    } catch {
      // non-fatal — banner just won't show counts
    } finally {
      setBankLoading(false)
    }
  }

  const handleGenerate = async () => {
    setGenerating(true)
    setGenError(null)
    setLastGenerated(null)
    setGeneratingTitle(null)
    setGeneratingSource(null)
    try {
      // Snapshot counts so the poll loop can detect whether a row was
      // published vs marked failed during this run.
      const snapshot = await getBlogBankStatus()
      startSnapshotRef.current = { published: snapshot.published, failed: snapshot.failed }
      setBank(snapshot)

      const params: { topic?: string } = {}
      const topic = topicHint.trim()
      if (topic) params.topic = topic
      const started = await generateNextFromBank(params)
      setGeneratingTitle(started.title)
      setGeneratingSource(started.source)
      setTopicHint('')
      setShowTopicHint(false)
      // Polling kicks in via the useEffect watching `generating`.
    } catch (err) {
      setGenError(err instanceof Error ? err.message : 'Generation failed')
      setGenerating(false)
      setGeneratingTitle(null)
      setGeneratingSource(null)
    }
  }

  useEffect(() => {
    void fetchPosts()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [status])

  useEffect(() => {
    void fetchBank()
  }, [])

  // Poll bank status while a generation is in flight. Background work on the
  // edge function updates the claimed row to 'published' or 'failed' — when
  // no rows are in progress, we compare count snapshots to decide success.
  useEffect(() => {
    if (!generating) return
    let cancelled = false
    const SITE_ORIGIN = 'https://dailyok.net'

    const tick = async () => {
      if (cancelled) return
      try {
        const latest = await getBlogBankStatus()
        if (cancelled) return
        setBank(latest)

        if (latest.generating > 0) return  // still working

        const snap = startSnapshotRef.current
        const publishedDelta = snap ? latest.published - snap.published : 0
        const failedDelta = snap ? latest.failed - snap.failed : 0

        if (publishedDelta > 0) {
          const postsRes = await listPosts({ status: 'all', limit: 50 })
          if (cancelled) return
          setPosts(postsRes.posts)
          setTotal(postsRes.total)
          const newest = postsRes.posts.find((p) => p.ai_generated)
          if (newest) {
            setLastGenerated({
              post_id: newest.id,
              slug: newest.slug,
              title: newest.title,
              source: generatingSource ?? 'blog_title_bank',
              url: `${SITE_ORIGIN}/blog/${newest.slug}`,
            })
          }
        } else if (failedDelta > 0) {
          setGenError(
            'Generation failed server-side. The bank row is now marked `failed` — check the edge-function logs for the AiError, then flip the row back to `pending` in the SQL editor to retry.',
          )
        } else {
          setGenError('Generation finished without producing a post. Check the edge-function logs.')
        }

        setGenerating(false)
        setGeneratingTitle(null)
        setGeneratingSource(null)
        startSnapshotRef.current = null
      } catch {
        // transient poll error — keep trying
      }
    }

    // First tick after 5s (generations almost never finish faster), then every 5s.
    const firstTick = window.setTimeout(() => { void tick() }, 5000)
    const interval = window.setInterval(() => { void tick() }, 5000)

    return () => {
      cancelled = true
      clearTimeout(firstTick)
      clearInterval(interval)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [generating])

  const handleDelete = async (id: string, title: string) => {
    if (!confirm(`Delete "${title}"? This cannot be undone.`)) return
    try {
      await deletePost(id)
      setPosts((p) => p.filter((x) => x.id !== id))
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to delete')
    }
  }

  return (
    <>
      <div className="admin-page-header">
        <div>
          <div className="admin-page-title">Blog</div>
          <div className="admin-page-subtitle">{total.toLocaleString()} posts</div>
        </div>
        <div style={{ display: 'flex', gap: 8 }}>
          <Link to="/admin/blog/templates" className="admin-btn admin-btn-secondary">
            <Sparkles size={14} /> Templates
          </Link>
          <button className="admin-btn admin-btn-primary" onClick={() => navigate('/admin/blog/new')}>
            <Plus size={14} /> New post
          </button>
        </div>
      </div>

      <div className="admin-card" style={{ borderColor: bank?.pending === 0 ? 'var(--gray-300)' : 'var(--green-200)' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: 16, flexWrap: 'wrap' }}>
          <div style={{ flex: 1, minWidth: 260 }}>
            <div style={{ fontSize: 15, fontWeight: 600, color: 'var(--gray-900)', marginBottom: 4 }}>
              AI blog generator
            </div>
            <div style={{ fontSize: 13, color: 'var(--gray-600)' }}>
              {bankLoading && !bank && 'Loading bank status…'}
              {bank && bank.pending > 0 && (
                <>
                  <strong>{bank.pending}</strong> title{bank.pending === 1 ? '' : 's'} pending in the bank
                  {bank.failed > 0 && <> · <span style={{ color: 'var(--red-600)' }}>{bank.failed} failed</span></>}
                  {bank.published > 0 && <> · {bank.published} already published</>}
                  . Each click pops the next one and publishes a full article.
                </>
              )}
              {bank && bank.pending === 0 && (
                <>
                  Bank is empty — the generator will pick a fresh, non-competing topic from the cluster bank.
                  {bank.failed > 0 && <> <span style={{ color: 'var(--red-600)' }}>{bank.failed} previous row{bank.failed === 1 ? '' : 's'} failed.</span></>}
                </>
              )}
            </div>
            {showTopicHint && (
              <div style={{ marginTop: 10 }}>
                <input
                  type="text"
                  value={topicHint}
                  onChange={(e) => setTopicHint(e.target.value)}
                  placeholder="Optional topic hint for fallback (e.g. 'widowed parent check-in')"
                  disabled={generating}
                  className="admin-input"
                  style={{ width: '100%', maxWidth: 520 }}
                />
                <div style={{ fontSize: 12, color: 'var(--gray-500)', marginTop: 4 }}>
                  Only used when the bank is empty. AI will swap it if it overlaps an existing post.
                </div>
              </div>
            )}
          </div>
          <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
            <button
              type="button"
              className="admin-btn admin-btn-sm admin-btn-secondary"
              onClick={() => setShowTopicHint((v) => !v)}
              disabled={generating}
            >
              {showTopicHint ? 'Hide topic hint' : 'Topic hint'}
            </button>
            <button
              type="button"
              className="admin-btn admin-btn-primary"
              onClick={() => void handleGenerate()}
              disabled={generating}
            >
              {generating
                ? <><Loader2 size={14} className="admin-spin" /> Writing…</>
                : <><Wand2 size={14} /> Generate next post</>}
            </button>
          </div>
        </div>

        {generating && (
          <div style={{ marginTop: 12, padding: '10px 12px', background: 'var(--gray-50)', border: '1px solid var(--gray-200)', borderRadius: 8, color: 'var(--gray-700)', fontSize: 13, display: 'flex', gap: 8, alignItems: 'flex-start' }}>
            <Loader2 size={16} className="admin-spin" style={{ flexShrink: 0, marginTop: 1, color: 'var(--green-600)' }} />
            <div>
              <div style={{ fontWeight: 600, color: 'var(--gray-900)' }}>
                {generatingTitle ? `Generating: ${generatingTitle}` : 'Generating a fresh topic from the cluster bank…'}
              </div>
              <div style={{ marginTop: 2, fontSize: 12 }}>
                This usually takes 30–90 seconds. You can leave this page open — the post will appear in the list automatically.
              </div>
            </div>
          </div>
        )}

        {genError && (
          <div style={{ marginTop: 12, padding: '10px 12px', background: 'var(--red-50)', border: '1px solid var(--red-200)', borderRadius: 8, color: 'var(--red-700)', fontSize: 13, display: 'flex', gap: 8, alignItems: 'flex-start' }}>
            <AlertCircle size={16} style={{ flexShrink: 0, marginTop: 1 }} />
            <div>{genError}</div>
          </div>
        )}

        {lastGenerated && !generating && (
          <div style={{ marginTop: 12, padding: '10px 12px', background: 'var(--green-50)', border: '1px solid var(--green-200)', borderRadius: 8, color: 'var(--gray-800)', fontSize: 13 }}>
            <div style={{ display: 'flex', gap: 8, alignItems: 'flex-start' }}>
              <CheckCircle2 size={16} style={{ flexShrink: 0, marginTop: 1, color: 'var(--green-600)' }} />
              <div style={{ flex: 1 }}>
                <div style={{ fontWeight: 600 }}>Published: {lastGenerated.title}</div>
                <div style={{ fontSize: 12, color: 'var(--gray-600)', marginTop: 2 }}>
                  Source: {lastGenerated.source === 'blog_title_bank' ? 'curated bank' : 'fallback cluster'}
                </div>
                <div style={{ marginTop: 6, display: 'flex', gap: 12 }}>
                  <a href={lastGenerated.url} target="_blank" rel="noopener noreferrer" style={{ color: 'var(--green-700)', fontWeight: 500 }}>
                    View on site ↗
                  </a>
                  <button
                    type="button"
                    className="admin-link-button"
                    onClick={() => navigate(`/admin/blog/${lastGenerated.post_id}`)}
                  >
                    Edit in admin
                  </button>
                </div>
              </div>
            </div>
          </div>
        )}
      </div>

      <div className="admin-toolbar">
        {(['all', 'draft', 'published', 'archived'] as StatusFilter[]).map((s) => (
          <button
            key={s}
            className={`admin-btn admin-btn-sm ${status === s ? 'admin-btn-primary' : 'admin-btn-secondary'}`}
            onClick={() => setStatus(s)}
          >
            {s[0].toUpperCase() + s.slice(1)}
          </button>
        ))}
      </div>

      {error && <div className="admin-error">{error}</div>}

      <div className="admin-table-wrap">
        <table className="admin-table">
          <thead>
            <tr>
              <th>Title</th>
              <th>Status</th>
              <th>Tags</th>
              <th>Updated</th>
              <th style={{ width: 160 }}></th>
            </tr>
          </thead>
          <tbody>
            {loading && <tr><td colSpan={5} className="admin-empty">Loading…</td></tr>}
            {!loading && posts.length === 0 && <tr><td colSpan={5} className="admin-empty">No posts yet. Click "New post" to create one.</td></tr>}
            {posts.map((p) => (
              <tr key={p.id}>
                <td>
                  <div style={{ fontWeight: 600 }}>{p.title}</div>
                  <div style={{ fontSize: 12, color: 'var(--gray-500)', marginTop: 2 }}>
                    /{p.slug}
                    {p.ai_generated && <span className="admin-ai-chip" style={{ marginLeft: 8 }}>AI</span>}
                  </div>
                </td>
                <td>
                  <StatusBadge status={p.status} />
                </td>
                <td>
                  {p.tags.slice(0, 3).map((t) => (
                    <span key={t} className="admin-badge admin-badge-gray" style={{ marginRight: 4 }}>{t}</span>
                  ))}
                </td>
                <td style={{ fontSize: 13, color: 'var(--gray-600)' }}>
                  {new Date(p.updated_at).toLocaleDateString()}
                </td>
                <td>
                  <div style={{ display: 'flex', gap: 6 }}>
                    <button
                      className="admin-btn admin-btn-sm admin-btn-secondary"
                      onClick={() => navigate(`/admin/blog/${p.id}`)}
                    >
                      <Edit3 size={12} /> Edit
                    </button>
                    <button
                      className="admin-btn admin-btn-sm admin-btn-danger"
                      onClick={() => void handleDelete(p.id, p.title)}
                    >
                      <Trash2 size={12} />
                    </button>
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </>
  )
}

function StatusBadge({ status }: { status: BlogPostListItem['status'] }) {
  const cls =
    status === 'published' ? 'admin-badge-green'
    : status === 'draft' ? 'admin-badge-yellow'
    : 'admin-badge-gray'
  return <span className={`admin-badge ${cls}`}>{status}</span>
}
