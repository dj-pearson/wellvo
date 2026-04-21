import { useEffect, useState } from 'react'
import { Plus, Trash2, Send, Edit3 } from 'lucide-react'
import {
  listSocial, createSocial, updateSocial, deleteSocial, publishSocial,
  type SocialPost,
} from '../lib/admin'
import './admin.css'

const PLATFORMS = [
  { key: 'twitter', label: 'X / Twitter' },
  { key: 'linkedin', label: 'LinkedIn' },
  { key: 'facebook', label: 'Facebook' },
  { key: 'instagram', label: 'Instagram' },
  { key: 'threads', label: 'Threads' },
  { key: 'tiktok', label: 'TikTok' },
  { key: 'bluesky', label: 'Bluesky' },
  { key: 'youtube', label: 'YouTube' },
]

type Filter = 'all' | 'draft' | 'scheduled' | 'posted' | 'failed'

export default function AdminSocial() {
  const [posts, setPosts] = useState<SocialPost[]>([])
  const [status, setStatus] = useState<Filter>('all')
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [editing, setEditing] = useState<Partial<SocialPost> | null>(null)
  const [publishing, setPublishing] = useState<string | null>(null)

  const refresh = async () => {
    setLoading(true)
    setError(null)
    try {
      const res = await listSocial({ status, limit: 100 })
      setPosts(res.posts)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { void refresh() }, [status]) // eslint-disable-line react-hooks/exhaustive-deps

  const handlePublish = async (id: string) => {
    if (!confirm('Publish this post via the Make.com webhook? This will fire the scenario immediately.')) return
    setPublishing(id)
    try {
      await publishSocial(id)
      void refresh()
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to publish')
    } finally {
      setPublishing(null)
    }
  }

  const handleDelete = async (id: string) => {
    if (!confirm('Delete this social post?')) return
    await deleteSocial(id)
    void refresh()
  }

  return (
    <>
      <div className="admin-page-header">
        <div>
          <div className="admin-page-title">Social</div>
          <div className="admin-page-subtitle">
            Compose, schedule, and publish social posts via your Make.com webhook
          </div>
        </div>
        <button
          className="admin-btn admin-btn-primary"
          onClick={() =>
            setEditing({
              content: '',
              platforms: [],
              status: 'draft',
              scheduled_at: null,
              media_urls: [],
              link_url: null,
            })
          }
        >
          <Plus size={14} /> New post
        </button>
      </div>

      {error && <div className="admin-error">{error}</div>}

      <div className="admin-toolbar">
        {(['all', 'draft', 'scheduled', 'posted', 'failed'] as Filter[]).map((s) => (
          <button
            key={s}
            className={`admin-btn admin-btn-sm ${status === s ? 'admin-btn-primary' : 'admin-btn-secondary'}`}
            onClick={() => setStatus(s)}
          >
            {s[0].toUpperCase() + s.slice(1)}
          </button>
        ))}
      </div>

      {editing && (
        <SocialEditor
          post={editing}
          onClose={() => setEditing(null)}
          onSaved={() => { setEditing(null); void refresh() }}
        />
      )}

      <div style={{ display: 'grid', gap: 12 }}>
        {loading && <div className="admin-empty">Loading…</div>}
        {!loading && posts.length === 0 && <div className="admin-empty">No posts yet.</div>}
        {posts.map((p) => (
          <div key={p.id} className="admin-card">
            <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12, alignItems: 'start' }}>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap', marginBottom: 8 }}>
                  <StatusBadge status={p.status} />
                  {p.platforms.map((pl) => (
                    <span key={pl} className="admin-badge admin-badge-blue">{pl}</span>
                  ))}
                  {p.scheduled_at && (
                    <span className="admin-badge admin-badge-gray">
                      Scheduled: {new Date(p.scheduled_at).toLocaleString()}
                    </span>
                  )}
                  {p.posted_at && (
                    <span className="admin-badge admin-badge-green">
                      Posted: {new Date(p.posted_at).toLocaleString()}
                    </span>
                  )}
                </div>
                <div style={{ whiteSpace: 'pre-wrap', fontSize: 14, color: 'var(--gray-800)' }}>{p.content}</div>
                {p.link_url && (
                  <div style={{ fontSize: 13, marginTop: 6 }}>
                    <a href={p.link_url} target="_blank" rel="noopener noreferrer">{p.link_url}</a>
                  </div>
                )}
                {p.media_urls.length > 0 && (
                  <div style={{ display: 'flex', gap: 8, marginTop: 8, flexWrap: 'wrap' }}>
                    {p.media_urls.map((u) => (
                      <a key={u} href={u} target="_blank" rel="noopener noreferrer">
                        <img src={u} alt="" style={{ height: 60, borderRadius: 6, border: '1px solid var(--gray-200)' }} />
                      </a>
                    ))}
                  </div>
                )}
                {p.post_urls && Object.keys(p.post_urls).length > 0 && (
                  <div style={{ marginTop: 10, fontSize: 13 }}>
                    <strong>Posted URLs: </strong>
                    {Object.entries(p.post_urls).map(([k, v]) => (
                      <a key={k} href={v} target="_blank" rel="noopener noreferrer" style={{ marginRight: 10 }}>{k} ↗</a>
                    ))}
                  </div>
                )}
                {p.webhook_error && (
                  <div className="admin-error" style={{ marginTop: 8 }}>
                    <strong>Webhook error:</strong> {p.webhook_error}
                  </div>
                )}
              </div>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
                {(p.status === 'draft' || p.status === 'scheduled' || p.status === 'failed') && (
                  <button
                    className="admin-btn admin-btn-sm admin-btn-primary"
                    onClick={() => void handlePublish(p.id)}
                    disabled={publishing === p.id}
                  >
                    <Send size={12} /> {publishing === p.id ? 'Publishing…' : 'Publish now'}
                  </button>
                )}
                <button className="admin-btn admin-btn-sm admin-btn-secondary" onClick={() => setEditing(p)}>
                  <Edit3 size={12} /> Edit
                </button>
                <button className="admin-btn admin-btn-sm admin-btn-danger" onClick={() => void handleDelete(p.id)}>
                  <Trash2 size={12} />
                </button>
              </div>
            </div>
          </div>
        ))}
      </div>
    </>
  )
}

function StatusBadge({ status }: { status: SocialPost['status'] }) {
  const cls =
    status === 'posted' ? 'admin-badge-green'
    : status === 'scheduled' ? 'admin-badge-blue'
    : status === 'failed' ? 'admin-badge-red'
    : status === 'publishing' ? 'admin-badge-yellow'
    : 'admin-badge-gray'
  return <span className={`admin-badge ${cls}`}>{status}</span>
}

function SocialEditor({
  post,
  onClose,
  onSaved,
}: {
  post: Partial<SocialPost>
  onClose: () => void
  onSaved: () => void
}) {
  const [form, setForm] = useState<Partial<SocialPost>>(post)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [mediaInput, setMediaInput] = useState('')

  const togglePlatform = (key: string) => {
    const current = form.platforms ?? []
    setForm({
      ...form,
      platforms: current.includes(key) ? current.filter((p) => p !== key) : [...current, key],
    })
  }

  const submit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!form.content || !form.content.trim()) {
      setError('Content is required')
      return
    }
    setSaving(true)
    setError(null)
    try {
      const payload = {
        content: form.content,
        platforms: form.platforms ?? [],
        status: form.status ?? 'draft',
        scheduled_at: form.scheduled_at ?? null,
        media_urls: form.media_urls ?? [],
        link_url: form.link_url ?? null,
      }
      if (form.id) {
        await updateSocial(form.id, payload)
      } else {
        await createSocial(payload)
      }
      onSaved()
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to save')
    } finally {
      setSaving(false)
    }
  }

  return (
    <div
      style={{
        position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.35)', zIndex: 1000,
        display: 'flex', justifyContent: 'flex-end',
      }}
      onClick={onClose}
    >
      <div
        style={{
          width: 'min(640px, 100%)', background: 'var(--white)', height: '100vh',
          overflow: 'auto', padding: 24, boxShadow: '-8px 0 30px rgba(0,0,0,0.1)',
        }}
        onClick={(e) => e.stopPropagation()}
      >
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 16 }}>
          <div className="admin-page-title" style={{ fontSize: 20 }}>
            {form.id ? 'Edit social post' : 'New social post'}
          </div>
          <button className="admin-btn admin-btn-secondary admin-btn-sm" onClick={onClose}>Close</button>
        </div>

        {error && <div className="admin-error">{error}</div>}

        <form className="admin-form" onSubmit={submit}>
          <div>
            <label className="admin-label">Content</label>
            <textarea
              className="admin-textarea"
              rows={5}
              value={form.content ?? ''}
              onChange={(e) => setForm({ ...form, content: e.target.value })}
              placeholder="What do you want to say?"
              required
            />
            <div className="admin-help">
              {(form.content?.length ?? 0)} chars — Twitter/X limit is 280 for free, LinkedIn 3000.
            </div>
          </div>

          <div>
            <label className="admin-label">Platforms</label>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6 }}>
              {PLATFORMS.map((p) => {
                const active = form.platforms?.includes(p.key) ?? false
                return (
                  <button
                    key={p.key}
                    type="button"
                    className={`admin-btn admin-btn-sm ${active ? 'admin-btn-primary' : 'admin-btn-secondary'}`}
                    onClick={() => togglePlatform(p.key)}
                  >
                    {p.label}
                  </button>
                )
              })}
            </div>
          </div>

          <div>
            <label className="admin-label">Link URL (optional)</label>
            <input
              type="url"
              className="admin-input"
              value={form.link_url ?? ''}
              onChange={(e) => setForm({ ...form, link_url: e.target.value })}
              placeholder="https://dailyok.net/blog/…"
            />
          </div>

          <div>
            <label className="admin-label">Media URLs</label>
            <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap', marginBottom: 8 }}>
              {(form.media_urls ?? []).map((u) => (
                <span key={u} className="admin-tag">
                  <span style={{ maxWidth: 260, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{u}</span>
                  <button
                    type="button"
                    onClick={() => setForm({ ...form, media_urls: (form.media_urls ?? []).filter((x) => x !== u) })}
                  >×</button>
                </span>
              ))}
            </div>
            <div style={{ display: 'flex', gap: 6 }}>
              <input
                type="url"
                className="admin-input"
                value={mediaInput}
                onChange={(e) => setMediaInput(e.target.value)}
                placeholder="https://…"
              />
              <button
                type="button"
                className="admin-btn admin-btn-secondary"
                onClick={() => {
                  const url = mediaInput.trim()
                  if (!url) return
                  setForm({ ...form, media_urls: [...(form.media_urls ?? []), url] })
                  setMediaInput('')
                }}
              >
                Add
              </button>
            </div>
          </div>

          <div className="admin-form-row">
            <div>
              <label className="admin-label">Status</label>
              <select
                className="admin-select"
                value={form.status ?? 'draft'}
                onChange={(e) => setForm({ ...form, status: e.target.value as SocialPost['status'] })}
              >
                <option value="draft">Draft</option>
                <option value="scheduled">Scheduled</option>
                <option value="posted">Posted (manual)</option>
              </select>
            </div>
            <div>
              <label className="admin-label">Scheduled at</label>
              <input
                type="datetime-local"
                className="admin-input"
                value={form.scheduled_at ? toLocalInput(form.scheduled_at) : ''}
                onChange={(e) => setForm({ ...form, scheduled_at: e.target.value ? new Date(e.target.value).toISOString() : null })}
              />
            </div>
          </div>

          <div style={{ display: 'flex', gap: 8 }}>
            <button className="admin-btn admin-btn-primary" type="submit" disabled={saving}>
              {saving ? 'Saving…' : form.id ? 'Save changes' : 'Create'}
            </button>
            <button className="admin-btn admin-btn-secondary" type="button" onClick={onClose}>Cancel</button>
          </div>
        </form>
      </div>
    </div>
  )
}

function toLocalInput(iso: string): string {
  const d = new Date(iso)
  const pad = (n: number) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`
}
