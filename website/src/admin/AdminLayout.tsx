import { NavLink, Navigate, Outlet, useLocation } from 'react-router-dom'
import {
  LayoutDashboard,
  Users,
  FileText,
  Share2,
  BarChart3,
  LogOut,
} from 'lucide-react'
import { useAdminAuth } from './AdminAuthProvider'
import './admin.css'

export default function AdminLayout() {
  const { session, loading, isAdmin, adminCheckDone, signOut } = useAdminAuth()
  const location = useLocation()

  if (loading || (session && !adminCheckDone)) {
    return (
      <div className="admin-login">
        <div className="admin-login-card">Loading…</div>
      </div>
    )
  }

  if (!session) {
    return <Navigate to="/admin/login" replace state={{ from: location.pathname }} />
  }

  if (!isAdmin) {
    return <Navigate to="/admin/login" replace />
  }

  return (
    <div className="admin-app">
      <aside className="admin-sidebar">
        <div className="admin-sidebar-brand">
          <span className="admin-sidebar-brand-dot" />
          Daily OK Admin
        </div>
        <nav className="admin-nav">
          <NavLink to="/admin" end>
            <LayoutDashboard size={16} /> Overview
          </NavLink>
          <NavLink to="/admin/users">
            <Users size={16} /> Users
          </NavLink>
          <NavLink to="/admin/blog">
            <FileText size={16} /> Blog
          </NavLink>
          <NavLink to="/admin/social">
            <Share2 size={16} /> Social
          </NavLink>
          <NavLink to="/admin/analytics">
            <BarChart3 size={16} /> Analytics
          </NavLink>
        </nav>
        <div className="admin-sidebar-footer">
          Signed in as<br />
          <strong style={{ color: 'var(--gray-200)' }}>{session.user.email || session.user.id.slice(0, 8)}</strong>
          <button onClick={() => void signOut()}>
            <LogOut size={12} style={{ marginRight: 6 }} /> Sign out
          </button>
        </div>
      </aside>
      <main className="admin-main">
        <Outlet />
      </main>
    </div>
  )
}
