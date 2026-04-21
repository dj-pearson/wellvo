import { useEffect, useState } from 'react'
import { ChevronRight, ChevronDown, Users as UsersIcon, Crown, UserCheck, Eye } from 'lucide-react'
import {
  listUsers, listFamilyTree, getUser, setUserAdmin,
  type AdminUser, type FamilyTreeNode, type FamilyTreeMember,
} from '../lib/admin'
import './admin.css'

type View = 'tree' | 'flat'

export default function AdminUsers() {
  const [view, setView] = useState<View>('tree')
  const [search, setSearch] = useState('')
  const [selectedId, setSelectedId] = useState<string | null>(null)

  return (
    <>
      <div className="admin-page-header">
        <div>
          <div className="admin-page-title">Users</div>
          <div className="admin-page-subtitle">Families grouped by owner, with receivers as children</div>
        </div>
        <div style={{ display: 'flex', gap: 8 }}>
          <button
            className={`admin-btn admin-btn-sm ${view === 'tree' ? 'admin-btn-primary' : 'admin-btn-secondary'}`}
            onClick={() => setView('tree')}
          >
            By family
          </button>
          <button
            className={`admin-btn admin-btn-sm ${view === 'flat' ? 'admin-btn-primary' : 'admin-btn-secondary'}`}
            onClick={() => setView('flat')}
          >
            Flat list
          </button>
        </div>
      </div>

      <div className="admin-toolbar">
        <input
          type="text"
          className="admin-input"
          placeholder="Search email, phone, name, or family name"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
        {search && (
          <button className="admin-btn admin-btn-secondary admin-btn-sm" onClick={() => setSearch('')}>
            Clear
          </button>
        )}
      </div>

      {view === 'tree'
        ? <FamilyTreeView search={search} onSelect={setSelectedId} />
        : <FlatList search={search} onSelect={setSelectedId} />}

      {selectedId && (
        <UserDetailDrawer
          userId={selectedId}
          onClose={() => setSelectedId(null)}
          onChanged={() => { /* parent views refetch on their own */ }}
        />
      )}
    </>
  )
}

// =============================================================================
// Family tree view — Owner row with receivers/viewers indented beneath
// =============================================================================

function FamilyTreeView({ search, onSelect }: { search: string; onSelect: (id: string) => void }) {
  const [data, setData] = useState<Awaited<ReturnType<typeof listFamilyTree>> | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    let cancelled = false
    setLoading(true)
    setError(null)
    const timer = setTimeout(() => {
      listFamilyTree({ search })
        .then((res) => { if (!cancelled) setData(res) })
        .catch((err) => { if (!cancelled) setError(err instanceof Error ? err.message : 'Failed to load') })
        .finally(() => { if (!cancelled) setLoading(false) })
    }, search ? 250 : 0)
    return () => { cancelled = true; clearTimeout(timer) }
  }, [search])

  if (loading) return <div className="admin-empty">Loading families…</div>
  if (error) return <div className="admin-error">{error}</div>
  if (!data) return null

  return (
    <>
      <div style={{ display: 'grid', gap: 10 }}>
        {data.families.length === 0 && (
          <div className="admin-empty">No families {search && 'match your search'}</div>
        )}
        {data.families.map((f) => (
          <FamilyCard key={f.id} family={f} onSelect={onSelect} />
        ))}
      </div>

      {data.orphans.length > 0 && (
        <div style={{ marginTop: 24 }}>
          <div className="admin-card-title" style={{ marginBottom: 8 }}>
            Unattached users ({data.orphans.length})
          </div>
          <div className="admin-card" style={{ padding: 0 }}>
            {data.orphans.map((u, i) => (
              <UserRow
                key={u.id}
                user={u}
                onSelect={onSelect}
                depth={0}
                borderTop={i > 0}
              />
            ))}
          </div>
        </div>
      )}

      <div style={{ marginTop: 12, fontSize: 12, color: 'var(--gray-500)' }}>
        Showing {data.families.length} of {data.total_families} families
        {data.orphans.length > 0 && ` • ${data.orphans.length} unattached`}
      </div>
    </>
  )
}

function FamilyCard({ family, onSelect }: { family: FamilyTreeNode; onSelect: (id: string) => void }) {
  const [open, setOpen] = useState(true)
  const memberCount = family.members.length

  return (
    <div className="admin-card" style={{ padding: 0, overflow: 'hidden' }}>
      {/* Family header */}
      <div
        style={{
          display: 'flex', alignItems: 'center', gap: 12,
          padding: '12px 16px',
          background: 'linear-gradient(180deg, var(--green-50) 0%, var(--white) 100%)',
          borderBottom: open ? '1px solid var(--gray-200)' : 'none',
          cursor: 'pointer',
        }}
        onClick={() => setOpen(!open)}
      >
        {open ? <ChevronDown size={16} /> : <ChevronRight size={16} />}
        <UsersIcon size={16} color="var(--green-700)" />
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontWeight: 700, fontSize: 15 }}>{family.name}</div>
          <div style={{ fontSize: 12, color: 'var(--gray-500)', marginTop: 2 }}>
            {memberCount === 0 ? 'No members yet' : `${memberCount} member${memberCount === 1 ? '' : 's'}`}
            {' • '}
            Created {new Date(family.created_at).toLocaleDateString()}
          </div>
        </div>
        <SubTierBadge tier={family.subscription_tier} status={family.subscription_status} />
      </div>

      {open && (
        <div>
          {/* Owner row */}
          {family.owner ? (
            <UserRow
              user={family.owner}
              onSelect={onSelect}
              depth={0}
              roleOverride="owner"
              icon={<Crown size={14} color="var(--green-700)" />}
            />
          ) : (
            <div style={{ padding: '10px 16px 10px 48px', fontSize: 13, color: 'var(--gray-500)' }}>
              Owner record missing
            </div>
          )}

          {/* Members indented */}
          {family.members.map((m) => (
            <MemberRow key={m.member_id} member={m} onSelect={onSelect} />
          ))}

          {family.members.length === 0 && (
            <div style={{ padding: '10px 16px 10px 48px', fontSize: 13, color: 'var(--gray-500)', borderTop: '1px solid var(--gray-100)' }}>
              No receivers yet
            </div>
          )}
        </div>
      )}
    </div>
  )
}

function MemberRow({ member, onSelect }: { member: FamilyTreeMember; onSelect: (id: string) => void }) {
  const icon = member.role === 'viewer' ? <Eye size={14} color="var(--gray-500)" /> : <UserCheck size={14} color="var(--green-600)" />
  return (
    <UserRow
      user={member.user}
      onSelect={onSelect}
      depth={1}
      roleOverride={member.role}
      statusOverride={member.status}
      icon={icon}
    />
  )
}

function UserRow({
  user,
  onSelect,
  depth,
  roleOverride,
  statusOverride,
  icon,
  borderTop = true,
}: {
  user: AdminUser
  onSelect: (id: string) => void
  depth: number
  roleOverride?: string
  statusOverride?: string
  icon?: React.ReactNode
  borderTop?: boolean
}) {
  return (
    <div
      onClick={() => onSelect(user.id)}
      style={{
        display: 'grid',
        gridTemplateColumns: '20px 20px 1fr auto',
        gap: 10,
        alignItems: 'center',
        padding: '10px 16px',
        paddingLeft: 16 + depth * 28,
        borderTop: borderTop ? '1px solid var(--gray-100)' : 'none',
        cursor: 'pointer',
        transition: 'background 0.1s',
      }}
      onMouseEnter={(e) => { e.currentTarget.style.background = 'var(--gray-50)' }}
      onMouseLeave={(e) => { e.currentTarget.style.background = 'transparent' }}
    >
      <span />
      {icon ?? <span style={{ width: 14, height: 14, display: 'inline-block' }} />}
      <div style={{ minWidth: 0 }}>
        <div style={{ fontWeight: 600, fontSize: 14 }}>
          {user.display_name}
          {user.is_system_admin && <span className="admin-badge admin-badge-green" style={{ marginLeft: 8 }}>admin</span>}
        </div>
        <div style={{ fontSize: 12, color: 'var(--gray-500)', marginTop: 2, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
          {user.email || user.phone || user.id.slice(0, 8)}
        </div>
      </div>
      <div style={{ display: 'flex', gap: 6 }}>
        {roleOverride && <span className="admin-badge admin-badge-gray">{roleOverride}</span>}
        {statusOverride && statusOverride !== 'active' && (
          <span className={`admin-badge ${statusOverride === 'invited' ? 'admin-badge-yellow' : 'admin-badge-red'}`}>
            {statusOverride}
          </span>
        )}
      </div>
    </div>
  )
}

function SubTierBadge({ tier, status }: { tier: string; status: string }) {
  const cls =
    tier === 'free' ? 'admin-badge-gray'
    : status === 'active' ? 'admin-badge-green'
    : 'admin-badge-yellow'
  return <span className={`admin-badge ${cls}`}>{tier}{status !== 'active' && ` · ${status}`}</span>
}

// =============================================================================
// Flat list (original view)
// =============================================================================

function FlatList({ search, onSelect }: { search: string; onSelect: (id: string) => void }) {
  const PAGE_SIZE = 50
  const [users, setUsers] = useState<AdminUser[]>([])
  const [total, setTotal] = useState(0)
  const [offset, setOffset] = useState(0)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    let cancelled = false
    setLoading(true)
    setError(null)
    const timer = setTimeout(() => {
      listUsers({ search, limit: PAGE_SIZE, offset })
        .then((res) => {
          if (cancelled) return
          setUsers(res.users)
          setTotal(res.total)
        })
        .catch((err) => { if (!cancelled) setError(err instanceof Error ? err.message : 'Failed to load users') })
        .finally(() => { if (!cancelled) setLoading(false) })
    }, search ? 250 : 0)
    return () => { cancelled = true; clearTimeout(timer) }
  }, [search, offset])

  return (
    <>
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
                  <button className="admin-btn admin-btn-sm admin-btn-secondary" onClick={() => onSelect(u.id)}>
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
    </>
  )
}

// =============================================================================
// User detail drawer (unchanged)
// =============================================================================

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
