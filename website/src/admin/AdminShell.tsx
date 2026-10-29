import { Outlet } from 'react-router-dom'
import { AdminAuthProvider } from './AdminAuthProvider'

/**
 * Root of the /admin route tree. AdminAuthProvider creates the persisted
 * Supabase auth client, reads the session and registers listeners — work only
 * the admin needs. It used to wrap the whole site (twice: the render hook and
 * App), so every public page shipped supabase-js and ran getSession() on load.
 * Mounting it here, behind App's lazy import, keeps all of that off public
 * pages.
 */
export default function AdminShell() {
  return (
    <AdminAuthProvider>
      <Outlet />
    </AdminAuthProvider>
  )
}
