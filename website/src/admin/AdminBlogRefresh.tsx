import { useEffect, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { ArrowLeft, RefreshCw, Sparkles, X, Check, History } from 'lucide-react'
import {
  listRefreshQueue, actionRefreshQueue, triggerRefreshProposal,
  type RefreshQueueItem, type RefreshStatus,
} from '../lib/admin'
import './admin.css'

type Filter = 'open' | RefreshStatus | 'all'

const REASON_LABELS: Record<string, string> = {
  decay: 'Traffic decay',
  serp_change: 'SERP shift',
  stale_facts: 'Stale facts',
  manual: 'Manual flag',
  periodic: 'Periodic refresh',
}

const STATUS_STYLES: Record<RefreshStatus, { bg: string; fg: string; label: string }> = {
  queued:      { bg: '#fef3c7', fg: '#92400e', label: 'Queued' },
  in_progress: { bg: '#e0e7ff', fg: '#3730a3', label: 'In progress' },
  proposed:    { bg: '#f3e8ff', fg: '#6b21a8', label: 'Proposal ready' },
  done:        { bg: '#dcfce7', fg: '#166534', label: 'Done' },
  dismissed:   { bg: '#f3f4f6', fg: '#4b5563', label: 'Dismissed' },
}

export default function AdminBlogRefresh() {
  const navigate = useNavigate()
  const [items, setItems] = useState<RefreshQueueItem[]>([])
  const [total, setTotal] = useState(0)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [filter, setFilter] = useState<Filter>('open')
  const [busyId, setBusyId] = useState<string | null>(null)
  const [busyKind, setBusyKind] = useState<'propose' | 'action' | null>(null)

  const fetchItems = async () => {
    setLoading(true)
    setError(null)
    try {
      const res = await listRefreshQueue({ filter, limit: 100 })
      setItems(res.items)
      setTotal(res.total)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load refresh queue')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { void fetchItems() /* eslint-disable-next-line react-hooks/exhaustive-deps */ }, [filter])

  const propose = async (item: RefreshQueueItem) => {
    setBusyId(item.id)
    setBusyKind('propose')
    setError(null)
    try {
      const res = await triggerRefreshProposal(item.id)
      // Refresh the list to pull in the new status + summary, then deep-link to history
      await fetchItems()
      navigate(`/admin/blog/${item.post_id}/history`)
      // History page will show the new revision tagged 'auto_refresh_proposal'.
      void res
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to generate proposal')
    } finally {
      setBusyId(null)
      setBusyKind(null)
    }
  }

  const action = async (item: RefreshQueueItem, next: 'dismissed' | 'done' | 'queued') => {
    setBusyId(item.id)
    setBusyKind('action')
    setError(null)
    try {
      await actionRefreshQueue(item.id, next)
      await fetchItems()
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to update queue')
    } finally {
      setBusyId(null)
      setBusyKind(null)
    }
  }

  return (
    <>
      <div className="admin-page-header">
        <div>
          <div className="admin-page-title">
            <RefreshCw size={18} style={{ verticalAlign: 'middle', marginRight: 6 }} />
            Refresh queue
          </div>
          <div className="admin-page-subtitle">
            {total} item{total === 1 ? '' : 's'} ({filter}). Posts flagged by the decay detector or by editors.
          </div>
        </div>
        <Link to="/admin/blog" className="admin-btn admin-btn-secondary">
          <ArrowLeft size={14} /> Back to blog
        </Link>
      </div>

      <div className="admin-toolbar">
        {(['open', 'queued', 'in_progress', 'proposed', 'done', 'dismissed', 'all'] as Filter[]).map((f) => (
          <button
            key={f}
            className={`admin-btn admin-btn-sm ${filter === f ? 'admin-btn-primary' : 'admin-btn-secondary'}`}
            onClick={() => setFilter(f)}
          >
            {f.replace('_', ' ')}
          </button>
        ))}
      </div>

      {error && <div className="admin-error">{error}</div>}

      <div className="admin-table-wrap">
        <table className="admin-table">
          <thead>
            <tr>
              <th>Post</th>
              <th style={{ width: 130 }}>Reason</th>
              <th style={{ width: 130 }}>Status</th>
              <th>Signal / proposal</th>
              <th style={{ width: 110 }}>Created</th>
              <th style={{ width: 280 }}></th>
            </tr>
          </thead>
          <tbody>
            {loading && <tr><td colSpan={6} className="admin-empty">Loading…</td></tr>}
            {!loading && items.length === 0 && (
              <tr><td colSpan={6} className="admin-empty">
                No items in this view. The decay detector runs nightly at 04:30 UTC.
              </td></tr>
            )}
            {items.map((item) => {
              const reasonLabel = REASON_LABELS[item.reason] ?? item.reason
              const statusStyle = STATUS_STYLES[item.status]
              const isBusy = busyId === item.id
              return (
                <tr key={item.id}>
                  <td>
                    <div style={{ fontWeight: 600 }}>{item.post?.title ?? '(post deleted)'}</div>
                    <div style={{ fontSize: 12, color: 'var(--gray-500)', marginTop: 2 }}>
                      /{item.post?.slug ?? item.post_id}
                      {item.post?.seo_score !== null && item.post?.seo_score !== undefined && (
                        <span style={{ marginLeft: 8 }}>
                          SEO {item.post.seo_score}
                        </span>
                      )}
                    </div>
                  </td>
                  <td>
                    <span className="admin-badge admin-badge-gray">{reasonLabel}</span>
                  </td>
                  <td>
                    <span style={{
                      display: 'inline-block', padding: '2px 8px', borderRadius: 10,
                      background: statusStyle.bg, color: statusStyle.fg,
                      fontSize: 12, fontWeight: 600,
                    }}>{statusStyle.label}</span>
                  </td>
                  <td style={{ fontSize: 12, color: 'var(--gray-700)' }}>
                    {item.proposal_summary ? (
                      <em style={{ color: 'var(--gray-800)' }}>{item.proposal_summary}</em>
                    ) : (
                      <DetectionSignal meta={item.detection_meta} />
                    )}
                  </td>
                  <td style={{ fontSize: 12, color: 'var(--gray-600)' }}>
                    {new Date(item.created_at).toLocaleDateString()}
                  </td>
                  <td>
                    <div style={{ display: 'flex', gap: 6, justifyContent: 'flex-end', flexWrap: 'wrap' }}>
                      {item.status === 'proposed' && item.proposal_revision_id && (
                        <button
                          className="admin-btn admin-btn-sm admin-btn-primary"
                          onClick={() => navigate(`/admin/blog/${item.post_id}/history`)}
                          disabled={isBusy}
                        >
                          <History size={12} /> Review
                        </button>
                      )}
                      {(item.status === 'queued' || item.status === 'in_progress') && (
                        <button
                          className="admin-btn admin-btn-sm admin-btn-primary"
                          onClick={() => void propose(item)}
                          disabled={isBusy}
                        >
                          <Sparkles size={12} />
                          {isBusy && busyKind === 'propose' ? 'Generating…' : 'Generate proposal'}
                        </button>
                      )}
                      {item.status !== 'done' && item.status !== 'dismissed' && (
                        <button
                          className="admin-btn admin-btn-sm admin-btn-secondary"
                          onClick={() => void action(item, 'done')}
                          disabled={isBusy}
                          title="Mark as resolved"
                        >
                          <Check size={12} /> Done
                        </button>
                      )}
                      {item.status !== 'dismissed' && item.status !== 'done' && (
                        <button
                          className="admin-btn admin-btn-sm admin-btn-secondary"
                          onClick={() => void action(item, 'dismissed')}
                          disabled={isBusy}
                          title="Dismiss without action"
                        >
                          <X size={12} /> Dismiss
                        </button>
                      )}
                    </div>
                  </td>
                </tr>
              )
            })}
          </tbody>
        </table>
      </div>
    </>
  )
}

function DetectionSignal({ meta }: { meta: Record<string, unknown> | null }) {
  if (!meta) return <span style={{ color: 'var(--gray-400)' }}>—</span>
  const drop = meta.drop_pct
  const cur = meta.current_28d_clicks
  const prior = meta.prior_28d_clicks
  if (typeof drop === 'number' && typeof cur === 'number' && typeof prior === 'number') {
    return (
      <span>
        Clicks down <strong>{drop.toFixed(1)}%</strong> ({prior} → {cur})
      </span>
    )
  }
  return <code style={{ fontSize: 11 }}>{JSON.stringify(meta).slice(0, 100)}</code>
}
