import { useEffect, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { Plus, Trash2, Edit3, Sparkles } from 'lucide-react'
import { listPosts, deletePost, type BlogPostListItem } from '../lib/admin'
import './admin.css'

type StatusFilter = 'all' | 'draft' | 'published' | 'archived'

export default function AdminBlog() {
  const [posts, setPosts] = useState<BlogPostListItem[]>([])
  const [total, setTotal] = useState(0)
  const [status, setStatus] = useState<StatusFilter>('all')
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const navigate = useNavigate()

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

  useEffect(() => {
    void fetchPosts()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [status])

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
