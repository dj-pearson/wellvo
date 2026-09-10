/**
 * Admin auth context and hook (US-SEO002).
 *
 * Split out of AdminAuthProvider.tsx because a module that exports both a
 * component and plain functions defeats React Fast Refresh, which can only
 * hot-swap a file whose every export is a component. The provider stays in the
 * .tsx; the shape, the context object and the hook live here.
 */
import { createContext, useContext } from 'react'
import type { Session } from '@supabase/supabase-js'

export interface AdminSessionState {
  loading: boolean
  session: Session | null
  isAdmin: boolean
  adminCheckDone: boolean
  signOut: () => Promise<void>
  refreshAdminStatus: () => Promise<void>
}

export const AdminAuthContext = createContext<AdminSessionState | null>(null)

export function useAdminAuth(): AdminSessionState {
  const ctx = useContext(AdminAuthContext)
  if (!ctx) throw new Error('useAdminAuth must be used inside AdminAuthProvider')
  return ctx
}
