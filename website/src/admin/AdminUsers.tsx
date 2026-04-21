import { useEffect, useState } from 'react'
import { listUsers, getUser, setUserAdmin, type AdminUser } from '../lib/admin'
import './admin.css'

const PAGE_SIZE = 50

export default function AdminUsers() {
  const [users, setUsers] = useState<AdminUser[]>([])
  const [total, setTotal] = useState(0)
  const [offset, setOffset] = useState(0)
  const [search, setSearch] = useState('')
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [selectedId, setSelectedId] = useState<string | null>(null)

  const fetchUsers = async (query: string, off: number) => {
    setLoading(true)
    setError(null)
    try {
      const res = await listUsers({ search: query, limit: PAGE_SIZE, offset: off })
      setUsers(res.users)
      setTotal(res.total)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load users')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    void fetchUsers(search, offset)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [offset])

  const onSearch = (e: React.FormEvent) => {
    e.preventDefault()
    setOffset(0)
    void fetchUsers(search, 0)
  }

  return (
    <>
      <div className="admin-page-header">
        <div>
          <div className="admin-page-title">Users</div>
          <div className="admin-page-subtitle">{total.toLocaleString()} total</div>
        </div>
      </div>

      <form onSubmit={onSearch} className="admin-toolbar">
        <input
          type="text"
          className="admin-input"
          placeholder="Search email, phone, or name"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
        <button className="admin-btn admin-btn-primary" type="submit">Search</button>
        {search && (
          <button
            type="button"
            className="admin-btn admin-btn-secondary"
            onClick={() => { setSearch(''); setOffset(0); void fetchUsers('', 0) }}
          >
            Clear
          </button>
        )}
      </form>

      {error && <div className="admin-error">{error}</div>}

      <div className="admin-table-wrap">
        <table className="admin-table">
          <thead>
            <tr>
              <th>Name</th>
              <th>Email</th>
              <th>Phone</th>
              <th>Role</th>
              <th>Admin</th>
              <th>Created</th>
              <th style={{ width: 90 }}></th>
            </tr>
          </thead>
          <tbody>
            {loading && <tr><td colSpan={7} className="admin-empty">Loading…</td></tr>}
            {!loading && users.length === 0 && <tr><td colSpan={7} className="admin-empty">No users found</td></tr>}
            {users.map((u) => (
              <tr key={u.id}>
                <td>{u.display_name}</td>
                <td>{u.email || <span style={{ color: 'var(--gray-400)' }}>—</span>}</td>
                <td>{u.phone || <span style={{ color: 'var(--gray-400)' }}>—</span>}</td>
                <td><span className="admin-badge admin-badge-gray">{u.role}</span></td>
                <td>{u.is_system_admin ? <span className="admin-badge admin-badge-green">admin</span> : <span className="admin-badge admin-badge-gray">—</span>}</td>
                <td>{new Date(u.created_at).toLocaleDateString()}</td>
                <td>
                  <button className="admin-btn admin-btn-sm admin-btn-secondary" onClick={() => setSelectedId(u.id)}>
                    View
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <div className="admin-toolbar" style={{ marginTop: 12, justifyContent: 'space-between' }}>
        <span style={{ fontSize: 13, color: 'var(--gray-500)' }}>
          Showing {users.length === 0 ? 0 : offset + 1}–{offset + users.length} of {total}
        </span>
        <div style={{ display: 'flex', gap: 8 }}>
          <button
            className="admin-btn admin-btn-secondary admin-btn-sm"
            disabled={offset === 0}
            onClick={() => setOffset(Math.max(0, offset - PAGE_SIZE))}
          >
            Previous
          </button>
          <button
            className="admin-btn admin-btn-secondary admin-btn-sm"
            disabled={offset + PAGE_SIZE >= total}
            onClick={() => setOffset(offset + PAGE_SIZE)}
          >
            Next
          </button>
        </div>
      </div>

      {selectedId && (
        <UserDetailDrawer
          userId={selectedId}
          onClose={() => setSelectedId(null)}
          onChanged={() => fetchUsers(search, offset)}
        />
      )}
    </>
  )
}

function UserDetailDrawer({
  userId,
  onClose,
  onChanged,
}: {
  userId: string
  onClose: () => void
  onChanged: () => void
}) {
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [detail, setDetail] = useState<Awaited<ReturnType<typeof getUser>> | null>(null)
  const [working, setWorking] = useState(false)

  useEffect(() => {
    let cancelled = false
    setLoading(true)
    getUser(userId)
      .then((d) => { if (!cancelled) setDetail(d) })
      .catch((err) => { if (!cancelled) setError(err instanceof Error ? err.message : 'Failed to load user') })
      .finally(() => { if (!cancelled) setLoading(false) })
    return () => { cancelled = true }
  }, [userId])

  const toggleAdmin = async () => {
    if (!detail) return
    setWorking(true)
    try {
      await setUserAdmin(userId, !detail.user.is_system_admin)
      const refreshed = await getUser(userId)
      setDetail(refreshed)
      onChanged()
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to update admin status')
    } finally {
      setWorking(false)
    }
  }

  return (
    <div
      style={{
        position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.35)',
        display: 'flex', justifyContent: 'flex-end', zIndex: 1000,
      }}
      onClick={onClose}
    >
      <div
        style={{
          width: 'min(600px, 100%)', background: 'var(--white)', height: '100vh',
          overflow: 'auto', padding: 24, boxShadow: '-8px 0 30px rgba(0,0,0,0.1)',
        }}
        onClick={(e) => e.stopPropagation()}
      >
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 16 }}>
          <div className="admin-page-title" style={{ fontSize: 20 }}>User details</div>
          <button className="admin-btn admin-btn-secondary admin-btn-sm" onClick={onClose}>Close</button>
        </div>
        {error && <div className="admin-error">{error}</div>}
        {loading && <div className="admin-empty">Loading…</div>}
        {detail && (
          <>
            <div className="admin-card">
              <div className="admin-card-title">{detail.user.display_name}</div>
              <div style={{ fontSize: 13, color: 'var(--gray-600)', display: 'grid', gap: 4 }}>
                <div><strong>ID:</strong> <code style={{ fontSize: 12 }}>{detail.user.id}</code></div>
                <div><strong>Email:</strong> {detail.user.email || '—'}</div>
                <div><strong>Phone:</strong> {detail.user.phone || '—'}</div>
                <div><strong>Role:</strong> {detail.user.role}</div>
                <div><strong>Timezone:</strong> {detail.user.timezone}</div>
                <div><strong>Created:</strong> {new Date(detail.user.created_at).toLocaleString()}</div>
              </div>
              <div style={{ marginTop: 12 }}>
                <button
                  className={`admin-btn ${detail.user.is_system_admin ? 'admin-btn-danger' : 'admin-btn-primary'}`}
                  onClick={toggleAdmin}
                  disabled={working}
                >
                  {working ? 'Working…' : detail.user.is_system_admin ? 'Revoke admin' : 'Promote to admin'}
                </button>
              </div>
            </div>

            <Section title={`Families owned (${detail.families_owned.length})`}>
              {detail.families_owned.length === 0
                ? <div style={{ color: 'var(--gray-500)', fontSize: 13 }}>None</div>
                : detail.families_owned.map((f) => (
                    <div key={String(f.id)} style={{ fontSize: 13, padding: '6px 0', borderBottom: '1px solid var(--gray-100)' }}>
                      <strong>{String(f.name)}</strong>{' '}
                      <span className="admin-badge admin-badge-gray">{String(f.subscription_tier)}</span>
                    </div>
                  ))}
            </Section>

            <Section title={`Memberships (${detail.memberships.length})`}>
              {detail.memberships.length === 0
                ? <div style={{ color: 'var(--gray-500)', fontSize: 13 }}>None</div>
                : detail.memberships.map((m, i) => (
                    <div key={i} style={{ fontSize: 13, padding: '6px 0', borderBottom: '1px solid var(--gray-100)' }}>
                      {/* families is a join; stringify a summary */}
                      <strong>{(m.families as { name?: string })?.name ?? 'Unknown family'}</strong>{' '}
                      <span className="admin-badge admin-badge-gray">{String(m.role)}</span>{' '}
                      <span className="admin-badge admin-badge-gray">{String(m.status)}</span>
                    </div>
                  ))}
            </Section>

            <Section title={`Recent check-ins (${detail.recent_checkins.length})`}>
              {detail.recent_checkins.length === 0
                ? <div style={{ color: 'var(--gray-500)', fontSize: 13 }}>None</div>
                : detail.recent_checkins.slice(0, 10).map((c) => (
                    <div key={String(c.id)} style={{ fontSize: 13, padding: '6px 0', borderBottom: '1px solid var(--gray-100)' }}>
                      {new Date(String(c.checked_in_at)).toLocaleString()}{' '}
                      {c.mood ? <span className="admin-badge admin-badge-gray">{String(c.mood)}</span> : null}
                    </div>
                  ))}
            </Section>

            <Section title={`Recent requests (${detail.recent_requests.length})`}>
              {detail.recent_requests.length === 0
                ? <div style={{ color: 'var(--gray-500)', fontSize: 13 }}>None</div>
                : detail.recent_requests.slice(0, 10).map((r) => (
                    <div key={String(r.id)} style={{ fontSize: 13, padding: '6px 0', borderBottom: '1px solid var(--gray-100)' }}>
                      {new Date(String(r.created_at)).toLocaleString()}{' '}
                      <span className={`admin-badge ${r.status === 'missed' ? 'admin-badge-red' : 'admin-badge-gray'}`}>
                        {String(r.status)}
                      </span>
                    </div>
                  ))}
            </Section>
          </>
        )}
      </div>
    </div>
  )
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="admin-card">
      <div className="admin-card-title">{title}</div>
      {children}
    </div>
  )
}
