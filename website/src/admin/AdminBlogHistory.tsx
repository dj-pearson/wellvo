import { useEffect, useMemo, useState, type CSSProperties } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import { ArrowLeft, History, RotateCcw, GitCompare } from 'lucide-react'
import {
  listRevisions, getRevision, restoreRevision,
  type BlogPostRevisionSummary, type BlogPostRevision,
} from '../lib/admin'
import './admin.css'

type Mode = 'list' | 'diff'

const REASON_LABELS: Record<string, string> = {
  initial: 'Initial',
  manual_edit: 'Manual edit',
  ai_regenerate: 'AI regenerate',
  auto_refresh: 'Auto refresh',
  restore: 'Restore',
}

export default function AdminBlogHistory() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()

  const [revisions, setRevisions] = useState<BlogPostRevisionSummary[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [success, setSuccess] = useState<string | null>(null)

  const [selA, setSelA] = useState<string | null>(null)
  const [selB, setSelB] = useState<string | null>(null)
  const [mode, setMode] = useState<Mode>('list')
  const [revA, setRevA] = useState<BlogPostRevision | null>(null)
  const [revB, setRevB] = useState<BlogPostRevision | null>(null)
  const [diffLoading, setDiffLoading] = useState(false)
  const [restoring, setRestoring] = useState<string | null>(null)

  const fetchRevisions = async () => {
    if (!id) return
    setLoading(true)
    setError(null)
    try {
      const res = await listRevisions(id, { limit: 100 })
      setRevisions(res.revisions)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load revisions')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { fetchRevisions(); /* eslint-disable-next-line react-hooks/exhaustive-deps */ }, [id])

  const toggleSelect = (revisionId: string) => {
    if (selA === revisionId) { setSelA(null); return }
    if (selB === revisionId) { setSelB(null); return }
    if (!selA) { setSelA(revisionId); return }
    if (!selB) { setSelB(revisionId); return }
    // Both filled — replace the older selection (B) with the new one
    setSelB(revisionId)
  }

  const compare = async () => {
    if (!selA || !selB) return
    setDiffLoading(true)
    setError(null)
    try {
      const [a, b] = await Promise.all([getRevision(selA), getRevision(selB)])
      // Order: older (A) on the left, newer (B) on the right, by created_at
      const aDate = new Date(a.revision.created_at).getTime()
      const bDate = new Date(b.revision.created_at).getTime()
      if (aDate <= bDate) { setRevA(a.revision); setRevB(b.revision) }
      else { setRevA(b.revision); setRevB(a.revision) }
      setMode('diff')
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load revisions for diff')
    } finally {
      setDiffLoading(false)
    }
  }

  const restore = async (revisionId: string) => {
    if (!confirm('Restore this version? Current content will be saved as a new revision before replacement.')) return
    setRestoring(revisionId)
    setError(null)
    setSuccess(null)
    try {
      await restoreRevision(revisionId)
      setSuccess('Restored. Returning to editor…')
      setTimeout(() => navigate(`/admin/blog/${id}`), 600)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Restore failed')
      setRestoring(null)
    }
  }

  if (!id) return <div className="admin-empty">Missing post id.</div>

  return (
    <>
      <div className="admin-page-header">
        <div>
          <div className="admin-page-title">
            <History size={18} style={{ verticalAlign: 'middle', marginRight: 6 }} />
            Revision history
          </div>
          <div className="admin-page-subtitle">
            {mode === 'list' ? `${revisions.length} revision${revisions.length === 1 ? '' : 's'}` : 'Side-by-side diff'}
          </div>
        </div>
        <div style={{ display: 'flex', gap: 8 }}>
          {mode === 'diff' && (
            <button className="admin-btn admin-btn-secondary" onClick={() => setMode('list')} type="button">
              <ArrowLeft size={14} /> Back to list
            </button>
          )}
          <Link className="admin-btn admin-btn-secondary" to={`/admin/blog/${id}`}>
            <ArrowLeft size={14} /> Back to editor
          </Link>
        </div>
      </div>

      {error && <div className="admin-error">{error}</div>}
      {success && <div className="admin-success">{success}</div>}

      {mode === 'list' ? (
        <RevisionList
          revisions={revisions}
          loading={loading}
          selA={selA}
          selB={selB}
          onToggle={toggleSelect}
          onRestore={restore}
          onCompare={compare}
          diffLoading={diffLoading}
          restoring={restoring}
        />
      ) : (
        revA && revB && (
          <DiffView
            a={revA}
            b={revB}
            onRestore={restore}
            restoring={restoring}
          />
        )
      )}
    </>
  )
}

// =============================================================================
// List view
// =============================================================================

function RevisionList({
  revisions, loading, selA, selB, onToggle, onRestore, onCompare, diffLoading, restoring,
}: {
  revisions: BlogPostRevisionSummary[]
  loading: boolean
  selA: string | null
  selB: string | null
  onToggle: (id: string) => void
  onRestore: (id: string) => void
  onCompare: () => void
  diffLoading: boolean
  restoring: string | null
}) {
  if (loading) return <div className="admin-empty">Loading revisions…</div>
  if (revisions.length === 0) return <div className="admin-empty">No revisions yet.</div>

  const canCompare = !!selA && !!selB

  return (
    <>
      <div style={{
        display: 'flex', alignItems: 'center', gap: 12, marginBottom: 12,
        padding: 10, border: '1px solid var(--gray-200)', borderRadius: 6, background: 'var(--gray-50)',
      }}>
        <span style={{ fontSize: 13, color: 'var(--gray-700)' }}>
          Pick two revisions to compare — selected: {selA ? '1' : '0'} / 2
        </span>
        <div style={{ flex: 1 }} />
        <button
          className="admin-btn admin-btn-primary"
          type="button"
          onClick={onCompare}
          disabled={!canCompare || diffLoading}
        >
          <GitCompare size={14} /> {diffLoading ? 'Loading…' : 'Compare selected'}
        </button>
      </div>

      <div style={{ overflowX: 'auto' }}>
        <table className="admin-table">
          <thead>
            <tr>
              <th style={{ width: 60 }}>Pick</th>
              <th>When</th>
              <th>Reason</th>
              <th>Editor</th>
              <th>Title</th>
              <th>Status</th>
              <th style={{ width: 120 }}></th>
            </tr>
          </thead>
          <tbody>
            {revisions.map((r) => {
              const checked = selA === r.id || selB === r.id
              const slot = selA === r.id ? 'A' : selB === r.id ? 'B' : null
              return (
                <tr key={r.id} style={checked ? { background: 'var(--blue-50, #eff6ff)' } : undefined}>
                  <td>
                    <label style={{ display: 'flex', alignItems: 'center', gap: 6, cursor: 'pointer' }}>
                      <input type="checkbox" checked={checked} onChange={() => onToggle(r.id)} />
                      {slot && <strong style={{ fontSize: 12 }}>{slot}</strong>}
                    </label>
                  </td>
                  <td style={{ whiteSpace: 'nowrap' }}>{formatWhen(r.created_at)}</td>
                  <td>
                    <span className="admin-ai-chip" style={reasonChipStyle(r.reason)}>
                      {REASON_LABELS[r.reason] ?? r.reason}
                    </span>
                  </td>
                  <td>{r.editor?.display_name || r.editor?.email || (r.editor_id ? '—' : 'system')}</td>
                  <td style={{ maxWidth: 360, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                    {r.title}
                  </td>
                  <td>{r.status}</td>
                  <td>
                    <button
                      className="admin-btn admin-btn-secondary"
                      type="button"
                      onClick={() => onRestore(r.id)}
                      disabled={!!restoring}
                    >
                      <RotateCcw size={12} /> {restoring === r.id ? 'Restoring…' : 'Restore'}
                    </button>
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

// =============================================================================
// Diff view
// =============================================================================

function DiffView({
  a, b, onRestore, restoring,
}: {
  a: BlogPostRevision
  b: BlogPostRevision
  onRestore: (id: string) => void
  restoring: string | null
}) {
  const metaRows: Array<{ label: string; aVal: string; bVal: string }> = [
    { label: 'Title', aVal: a.title, bVal: b.title },
    { label: 'Slug', aVal: a.slug, bVal: b.slug },
    { label: 'Status', aVal: a.status, bVal: b.status },
    { label: 'Excerpt', aVal: a.excerpt ?? '', bVal: b.excerpt ?? '' },
    { label: 'SEO title', aVal: a.seo_title ?? '', bVal: b.seo_title ?? '' },
    { label: 'SEO description', aVal: a.seo_description ?? '', bVal: b.seo_description ?? '' },
    { label: 'Category', aVal: a.category ?? '', bVal: b.category ?? '' },
    { label: 'Tags', aVal: (a.tags ?? []).join(', '), bVal: (b.tags ?? []).join(', ') },
  ]

  const aLines = useMemo(() => stripToLines(a.content_html), [a.content_html])
  const bLines = useMemo(() => stripToLines(b.content_html), [b.content_html])
  const diffed = useMemo(() => lineDiff(aLines, bLines), [aLines, bLines])

  return (
    <>
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12, marginBottom: 16 }}>
        <RevisionHeader rev={a} side="A" onRestore={onRestore} restoring={restoring} />
        <RevisionHeader rev={b} side="B" onRestore={onRestore} restoring={restoring} />
      </div>

      <h3 style={{ marginTop: 24, marginBottom: 8 }}>Metadata</h3>
      <div style={{ overflowX: 'auto' }}>
        <table className="admin-table">
          <thead>
            <tr>
              <th style={{ width: 160 }}>Field</th>
              <th>A (older)</th>
              <th>B (newer)</th>
            </tr>
          </thead>
          <tbody>
            {metaRows.map((row) => {
              const changed = row.aVal !== row.bVal
              return (
                <tr key={row.label}>
                  <td><strong>{row.label}</strong></td>
                  <td style={changed ? cellChangedStyle('a') : undefined}>{row.aVal || <em>—</em>}</td>
                  <td style={changed ? cellChangedStyle('b') : undefined}>{row.bVal || <em>—</em>}</td>
                </tr>
              )
            })}
          </tbody>
        </table>
      </div>

      <h3 style={{ marginTop: 24, marginBottom: 8 }}>Content (text diff)</h3>
      <div style={{
        display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 0,
        border: '1px solid var(--gray-200)', borderRadius: 6, overflow: 'hidden',
      }}>
        <div style={{ borderRight: '1px solid var(--gray-200)' }}>
          <DiffColumn ops={diffed} side="a" />
        </div>
        <div>
          <DiffColumn ops={diffed} side="b" />
        </div>
      </div>
    </>
  )
}

function RevisionHeader({
  rev, side, onRestore, restoring,
}: {
  rev: BlogPostRevision
  side: 'A' | 'B'
  onRestore: (id: string) => void
  restoring: string | null
}) {
  return (
    <div style={{ border: '1px solid var(--gray-200)', borderRadius: 6, padding: 12, background: 'var(--gray-50)' }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 12 }}>
        <div>
          <div style={{ fontSize: 12, color: 'var(--gray-600)' }}>Revision {side}</div>
          <div style={{ fontWeight: 600 }}>{formatWhen(rev.created_at)}</div>
          <div style={{ fontSize: 13, color: 'var(--gray-700)' }}>
            <span className="admin-ai-chip" style={reasonChipStyle(rev.reason)}>
              {REASON_LABELS[rev.reason] ?? rev.reason}
            </span>
          </div>
        </div>
        <button
          className="admin-btn admin-btn-secondary"
          type="button"
          onClick={() => onRestore(rev.id)}
          disabled={!!restoring}
        >
          <RotateCcw size={12} /> {restoring === rev.id ? 'Restoring…' : 'Restore'}
        </button>
      </div>
    </div>
  )
}

interface DiffOp { kind: 'eq' | 'del' | 'add'; line: string }

function DiffColumn({ ops, side }: { ops: DiffOp[]; side: 'a' | 'b' }) {
  return (
    <pre style={{
      margin: 0, padding: 12, fontFamily: 'ui-monospace, Menlo, monospace', fontSize: 12,
      whiteSpace: 'pre-wrap', wordBreak: 'break-word', lineHeight: 1.5,
    }}>
      {ops.map((op, i) => {
        if (op.kind === 'eq') return <div key={i}>{op.line || ' '}</div>
        if (op.kind === 'del' && side === 'a') {
          return <div key={i} style={{ background: '#fee2e2' }}>− {op.line}</div>
        }
        if (op.kind === 'add' && side === 'b') {
          return <div key={i} style={{ background: '#dcfce7' }}>+ {op.line}</div>
        }
        return <div key={i} style={{ visibility: 'hidden' }}>&nbsp;</div>
      })}
    </pre>
  )
}

// =============================================================================
// Helpers
// =============================================================================

function formatWhen(iso: string): string {
  const d = new Date(iso)
  return d.toLocaleString(undefined, {
    year: 'numeric', month: 'short', day: 'numeric',
    hour: '2-digit', minute: '2-digit',
  })
}

function reasonChipStyle(reason: string): CSSProperties {
  switch (reason) {
    case 'initial': return { background: '#eff6ff', color: '#1d4ed8' }
    case 'restore': return { background: '#fef3c7', color: '#92400e' }
    case 'auto_refresh': return { background: '#f3e8ff', color: '#6b21a8' }
    case 'ai_regenerate': return { background: '#e0e7ff', color: '#3730a3' }
    default: return {}
  }
}

function cellChangedStyle(side: 'a' | 'b'): CSSProperties {
  return { background: side === 'a' ? '#fee2e2' : '#dcfce7' }
}

/**
 * Strip HTML to a list of lines suitable for line-level diff.
 * Splits on block-level boundaries so each <p>/<li>/<h2> ends up on its own line.
 */
function stripToLines(html: string): string[] {
  const blockified = html
    .replace(/<\/(p|li|h1|h2|h3|h4|h5|h6|blockquote|div|ul|ol|tr)>/gi, '$&\n')
    .replace(/<br\s*\/?>/gi, '\n')
  const text = blockified.replace(/<[^>]+>/g, '').replace(/&nbsp;/g, ' ')
  return text.split(/\n+/).map((s) => s.trim()).filter((s) => s.length > 0)
}

/**
 * LCS-based line diff. Returns an ordered sequence of operations:
 *   eq  — line present in both (same content)
 *   del — line removed (only on side A)
 *   add — line added (only on side B)
 *
 * O(n*m) memory — fine for typical blog post lengths (<200 lines per side).
 */
function lineDiff(a: string[], b: string[]): DiffOp[] {
  const n = a.length, m = b.length
  if (n === 0) return b.map((line) => ({ kind: 'add' as const, line }))
  if (m === 0) return a.map((line) => ({ kind: 'del' as const, line }))

  // dp[i][j] = LCS length of a[i..] and b[j..]
  const dp: number[][] = Array.from({ length: n + 1 }, () => new Array(m + 1).fill(0))
  for (let i = n - 1; i >= 0; i--) {
    for (let j = m - 1; j >= 0; j--) {
      dp[i][j] = a[i] === b[j] ? dp[i + 1][j + 1] + 1 : Math.max(dp[i + 1][j], dp[i][j + 1])
    }
  }

  const ops: DiffOp[] = []
  let i = 0, j = 0
  while (i < n && j < m) {
    if (a[i] === b[j]) {
      ops.push({ kind: 'eq', line: a[i] })
      i++; j++
    } else if (dp[i + 1][j] >= dp[i][j + 1]) {
      ops.push({ kind: 'del', line: a[i] })
      i++
    } else {
      ops.push({ kind: 'add', line: b[j] })
      j++
    }
  }
  while (i < n) { ops.push({ kind: 'del', line: a[i++] }) }
  while (j < m) { ops.push({ kind: 'add', line: b[j++] }) }
  return ops
}
