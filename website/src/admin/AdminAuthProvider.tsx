import { useEffect, useMemo, useState, type ReactNode } from 'react'
import type { Session } from '@supabase/supabase-js'
import { getSupabase, isSupabaseConfigured } from '../lib/supabase'
import { AdminAuthContext, type AdminSessionState } from './adminAuthContext'

export function AdminAuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null)
  const [loading, setLoading] = useState(true)
  const [isAdmin, setIsAdmin] = useState(false)
  const [adminCheckDone, setAdminCheckDone] = useState(false)

  const configured = isSupabaseConfigured()

  useEffect(() => {
    if (!configured) {
      setLoading(false)
      setAdminCheckDone(true)
      return
    }
    const supabase = getSupabase()
    let mounted = true

    supabase.auth.getSession().then(({ data }) => {
      if (!mounted) return
      setSession(data.session)
      setLoading(false)
    })

    const { data: listener } = supabase.auth.onAuthStateChange((_event, newSession) => {
      setSession(newSession)
      setIsAdmin(false)
      setAdminCheckDone(false)
    })

    return () => {
      mounted = false
      listener.subscription.unsubscribe()
    }
  }, [configured])

  const checkAdmin = async () => {
    if (!session) {
      setIsAdmin(false)
      setAdminCheckDone(true)
      return
    }
    try {
      const supabase = getSupabase()
      // is_system_admin() (SECURITY DEFINER) answers for the caller. The
      // column itself is being hidden from clients (staged migration
      // member_column_privileges.sql), which would break a direct select.
      const { data, error } = await supabase.rpc('is_system_admin')
      if (error) throw error
      setIsAdmin(data === true)
    } catch {
      setIsAdmin(false)
    } finally {
      setAdminCheckDone(true)
    }
  }

  useEffect(() => {
    if (session && !adminCheckDone) {
      void checkAdmin()
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [session, adminCheckDone])

  const value = useMemo<AdminSessionState>(
    () => ({
      loading,
      session,
      isAdmin,
      adminCheckDone,
      signOut: async () => {
        if (configured) await getSupabase().auth.signOut()
      },
      refreshAdminStatus: checkAdmin,
    }),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [loading, session, isAdmin, adminCheckDone, configured],
  )

  return <AdminAuthContext.Provider value={value}>{children}</AdminAuthContext.Provider>
}
