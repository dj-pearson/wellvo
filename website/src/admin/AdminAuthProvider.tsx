import { createContext, useContext, useEffect, useMemo, useState, type ReactNode } from 'react'
import type { Session } from '@supabase/supabase-js'
import { getSupabase, isSupabaseConfigured } from '../lib/supabase'

interface AdminSessionState {
  loading: boolean
  session: Session | null
  isAdmin: boolean
  adminCheckDone: boolean
  signOut: () => Promise<void>
  refreshAdminStatus: () => Promise<void>
}

const AdminAuthContext = createContext<AdminSessionState | null>(null)

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
      const { data, error } = await supabase
        .from('users')
        .select('is_system_admin')
        .eq('id', session.user.id)
        .maybeSingle()
      if (error) throw error
      setIsAdmin(!!data?.is_system_admin)
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

export function useAdminAuth(): AdminSessionState {
  const ctx = useContext(AdminAuthContext)
  if (!ctx) throw new Error('useAdminAuth must be used inside AdminAuthProvider')
  return ctx
}
