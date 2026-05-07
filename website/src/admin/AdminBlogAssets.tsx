import { useEffect, useState, type FormEvent } from 'react'
import { Link } from 'react-router-dom'
import { ArrowLeft, Image as ImageIcon, Quote, LinkIcon, FileIcon, Database, Users, Plus, Trash2 } from 'lucide-react'
import {
  listAssets, createAsset, deleteAsset,
  type BlogAsset, type BlogAssetType,
} from '../lib/admin'
import './admin.css'

type Filter = BlogAssetType | 'all'

const TYPE_META: Record<BlogAssetType, { label: string; Icon: typeof ImageIcon }> = {
  image:          { label: 'Image',     Icon: ImageIcon },
  quote:          { label: 'Quote',     Icon: Quote },
  link:           { label: 'Link',      Icon: LinkIcon },
  file:           { label: 'File',      Icon: FileIcon },
  data_table:     { label: 'Data',      Icon: Database },
  expert_contact: { label: 'Expert',    Icon: Users },
}

export default function AdminBlogAssets() {
  const [assets, setAssets] = useState<BlogAsset[]>([])
  const [total, setTotal] = useState(0)
  const [filter, setFilter] = useState<Filter>('all')
  const [search, setSearch] = useState('')
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [showAdd, setShowAdd] = useState(false)

  const fetchAssets = async () => {
    setLoading(true)
    setError(null)
    try {
      const res = await listAssets({ type: filter, search: search.trim() || undefined, limit: 200 })
      setAssets(res.assets)
      setTotal(res.total)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load assets')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { void fetchAssets() /* eslint-disable-next-line react-hooks/exhaustive-deps */ }, [filter])

  const remove = async (a: BlogAsset) => {
    if (!confirm(`Delete asset "${a.title}"? This cannot be undone.`)) return
    try {
      await deleteAsset(a.id)
      setAssets((s) => s.filter((x) => x.id !== a.id))
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Delete failed')
    }
  }

  return (
    <>
      <div className="admin-page-header">
        <div>
          <div className="admin-page-title">Asset library</div>
          <div className="admin-page-subtitle">{total} asset{total === 1 ? '' : 's'}. License + source mandatory on every row.</div>
        </div>
        <div style={{ display: 'flex', gap: 8 }}>
          <Link to="/admin/blog" className="admin-btn admin-btn-secondary">
            <ArrowLeft size={14} /> Back
          </Link>
          <button className="admin-btn admin-btn-primary" onClick={() => setShowAdd(true)}>
            <Plus size={14} /> Add asset
          </button>
        </div>
      </div>

      <div className="admin-toolbar" style={{ alignItems: 'center', gap: 8 }}>
        {(['all', 'image', 'quote', 'link', 'file', 'data_table', 'expert_contact'] as Filter[]).map((f) => (
          <button
            key={f}
            className={`admin-btn admin-btn-sm ${filter === f ? 'admin-btn-primary' : 'admin-btn-secondary'}`}
            onClick={() => setFilter(f)}
          >
            {f === 'all' ? 'All' : TYPE_META[f].label}
          </button>
        ))}
        <div style={{ flex: 1 }} />
        <form onSubmit={(e) => { e.preventDefault(); void fetchAssets() }} style={{ display: 'flex', gap: 6 }}>
          <input
            className="admin-input"
            placeholder="Search title, description, quote…"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            style={{ width: 280 }}
          />
          <button type="submit" className="admin-btn admin-btn-secondary admin-btn-sm">Search</button>
        </form>
      </div>

      {error && <div className="admin-error">{error}</div>}

      <div className="admin-table-wrap">
        <table className="admin-table">
          <thead>
            <tr>
              <th>Type</th>
              <th>Title</th>
              <th>Source</th>
              <th>License</th>
              <th>Tags</th>
              <th style={{ width: 90 }}></th>
            </tr>
          </thead>
          <tbody>
            {loading && <tr><td colSpan={6} className="admin-empty">Loading…</td></tr>}
            {!loading && assets.length === 0 && (
              <tr><td colSpan={6} className="admin-empty">No assets yet. Click "Add asset" to create one.</td></tr>
            )}
            {assets.map((a) => {
              const meta = TYPE_META[a.type]
              return (
                <tr key={a.id}>
                  <td>
                    <span className="admin-badge admin-badge-gray">
                      <meta.Icon size={11} style={{ verticalAlign: 'middle', marginRight: 3 }} />
                      {meta.label}
                    </span>
                  </td>
                  <td>
                    <div style={{ fontWeight: 600 }}>{a.title}</div>
                    {a.url && (
                      <div style={{ fontSize: 12, color: 'var(--gray-500)', marginTop: 2 }}>
                        <a href={a.url} target="_blank" rel="noopener noreferrer">{a.url}</a>
                      </div>
                    )}
                    {a.quote_text && (
                      <div style={{ fontSize: 12, color: 'var(--gray-700)', marginTop: 4, fontStyle: 'italic' }}>
                        "{a.quote_text.slice(0, 200)}"{a.quote_text.length > 200 ? '…' : ''}
                        {a.attributed_to && <> — {a.attributed_to}</>}
                      </div>
                    )}
                  </td>
                  <td style={{ fontSize: 12 }}>{a.source || <em style={{ color: 'var(--gray-400)' }}>—</em>}</td>
                  <td style={{ fontSize: 12 }}>{a.license || <em style={{ color: 'var(--gray-400)' }}>—</em>}</td>
                  <td>
                    {a.tags.slice(0, 4).map((t) => (
                      <span key={t} className="admin-badge admin-badge-gray" style={{ marginRight: 4 }}>{t}</span>
                    ))}
                  </td>
                  <td>
                    <button
                      className="admin-btn admin-btn-sm admin-btn-danger"
                      onClick={() => void remove(a)}
                      title="Delete"
                    >
                      <Trash2 size={12} />
                    </button>
                  </td>
                </tr>
              )
            })}
          </tbody>
        </table>
      </div>

      {showAdd && (
        <AddAssetDialog
          onClose={() => setShowAdd(false)}
          onAdded={(a) => { setAssets((s) => [a, ...s]); setTotal((t) => t + 1); setShowAdd(false) }}
        />
      )}
    </>
  )
}

// =============================================================================
// Add asset dialog
// =============================================================================

function AddAssetDialog({ onClose, onAdded }: { onClose: () => void; onAdded: (a: BlogAsset) => void }) {
  const [type, setType] = useState<BlogAssetType>('image')
  const [title, setTitle] = useState('')
  const [description, setDescription] = useState('')
  const [tagsRaw, setTagsRaw] = useState('')
  const [source, setSource] = useState('')
  const [license, setLicense] = useState('')
  const [url, setUrl] = useState('')
  const [altText, setAltText] = useState('')
  const [quoteText, setQuoteText] = useState('')
  const [attributedTo, setAttributedTo] = useState('')
  const [contactName, setContactName] = useState('')
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState<string | null>(null)

  const submit = async (e: FormEvent) => {
    e.preventDefault()
    setSaving(true)
    setErr(null)
    try {
      const payload: Partial<BlogAsset> = {
        type, title, description: description || null,
        tags: tagsRaw.split(',').map((s) => s.trim()).filter(Boolean),
        source, license,
        url: url || null, alt_text: altText || null,
        quote_text: quoteText || null, attributed_to: attributedTo || null,
        contact_name: contactName || null,
      }
      const res = await createAsset(payload)
      onAdded(res.asset)
    } catch (e2) {
      setErr(e2 instanceof Error ? e2.message : 'Failed to create asset')
    } finally {
      setSaving(false)
    }
  }

  return (
    <div
      role="dialog" aria-modal="true"
      style={{
        position: 'fixed', inset: 0, background: 'rgba(15,23,42,0.55)',
        display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 50,
      }}
      onClick={onClose}
    >
      <div
        onClick={(e) => e.stopPropagation()}
        style={{
          background: 'white', borderRadius: 8, padding: 20, width: 'min(620px, 92vw)',
          maxHeight: '88vh', overflowY: 'auto', boxShadow: '0 20px 50px rgba(0,0,0,0.25)',
        }}
      >
        <h3 style={{ marginTop: 0 }}>Add asset</h3>
        <form onSubmit={submit} className="admin-form">
          <div className="admin-form-row">
            <div>
              <label className="admin-label">Type</label>
              <select className="admin-input" value={type} onChange={(e) => setType(e.target.value as BlogAssetType)}>
                <option value="image">Image</option>
                <option value="quote">Quote</option>
                <option value="link">Link</option>
                <option value="file">File</option>
                <option value="data_table">Data table</option>
                <option value="expert_contact">Expert contact</option>
              </select>
            </div>
            <div>
              <label className="admin-label">Tags (comma-separated)</label>
              <input className="admin-input" value={tagsRaw} onChange={(e) => setTagsRaw(e.target.value)} placeholder="caregiving, dementia" />
            </div>
          </div>

          <div>
            <label className="admin-label">Title <span style={{ color: 'var(--red-600)' }}>*</span></label>
            <input className="admin-input" value={title} onChange={(e) => setTitle(e.target.value)} required />
          </div>

          <div>
            <label className="admin-label">Description</label>
            <textarea className="admin-textarea" value={description} onChange={(e) => setDescription(e.target.value)} />
          </div>

          {(type === 'image' || type === 'link' || type === 'file' || type === 'data_table') && (
            <div>
              <label className="admin-label">URL {type === 'image' || type === 'link' ? <span style={{ color: 'var(--red-600)' }}>*</span> : null}</label>
              <input className="admin-input" type="url" value={url} onChange={(e) => setUrl(e.target.value)} />
            </div>
          )}

          {type === 'image' && (
            <div>
              <label className="admin-label">Alt text <span style={{ color: 'var(--red-600)' }}>*</span></label>
              <input className="admin-input" value={altText} onChange={(e) => setAltText(e.target.value)} required />
            </div>
          )}

          {type === 'quote' && (
            <>
              <div>
                <label className="admin-label">Quote text <span style={{ color: 'var(--red-600)' }}>*</span></label>
                <textarea className="admin-textarea" value={quoteText} onChange={(e) => setQuoteText(e.target.value)} required />
              </div>
              <div>
                <label className="admin-label">Attributed to</label>
                <input className="admin-input" value={attributedTo} onChange={(e) => setAttributedTo(e.target.value)} />
              </div>
            </>
          )}

          {type === 'expert_contact' && (
            <div>
              <label className="admin-label">Contact name <span style={{ color: 'var(--red-600)' }}>*</span></label>
              <input className="admin-input" value={contactName} onChange={(e) => setContactName(e.target.value)} required />
            </div>
          )}

          <div className="admin-form-row">
            <div>
              <label className="admin-label">Source</label>
              <input className="admin-input" value={source} onChange={(e) => setSource(e.target.value)} placeholder="e.g. AARP, Unsplash, internal-survey-2026" />
            </div>
            <div>
              <label className="admin-label">License</label>
              <input className="admin-input" value={license} onChange={(e) => setLicense(e.target.value)} placeholder="e.g. CC0, CC-BY-4.0, editorial-use-only" />
            </div>
          </div>

          {err && <div className="admin-error">{err}</div>}

          <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 8, marginTop: 12 }}>
            <button type="button" className="admin-btn admin-btn-secondary" onClick={onClose} disabled={saving}>Cancel</button>
            <button type="submit" className="admin-btn admin-btn-primary" disabled={saving || !title}>
              {saving ? 'Saving…' : 'Save asset'}
            </button>
          </div>
        </form>
      </div>
    </div>
  )
}
