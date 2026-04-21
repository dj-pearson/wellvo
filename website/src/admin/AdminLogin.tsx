import { useState, type FormEvent } from 'react'
import { Navigate, useLocation } from 'react-router-dom'
import { getSupabase, isSupabaseConfigured } from '../lib/supabase'
import { useAdminAuth } from './AdminAuthProvider'
import './admin.css'

export default function AdminLogin() {
  const { session, loading, isAdmin, adminCheckDone } = useAdminAuth()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [info, setInfo] = useState<string | null>(null)
  const location = useLocation()

  if (!isSupabaseConfigured()) {
    return (
      <div className="admin-login">
        <div className="admin-login-card">
          <div className="admin-login-title">Admin</div>
          <div className="admin-error">
            Supabase is not configured. Set <code>VITE_SUPABASE_URL</code> and{' '}
            <code>VITE_SUPABASE_ANON_KEY</code> before building the website.
          </div>
        </div>
      </div>
    )
  }

  if (loading) {
    return (
      <div className="admin-login">
        <div className="admin-login-card">Loading…</div>
      </div>
    )
  }

  if (session && adminCheckDone && isAdmin) {
    const from = (location.state as { from?: string } | null)?.from || '/admin'
    return <Navigate to={from} replace />
  }

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault()
    setError(null)
    setInfo(null)
    setSubmitting(true)
    try {
      const supabase = getSupabase()
      const { error: signInErr } = await supabase.auth.signInWithPassword({ email, password })
      if (signInErr) throw signInErr
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Sign-in failed')
    } finally {
      setSubmitting(false)
    }
  }

  const handleMagicLink = async () => {
    if (!email) {
      setError('Enter your email first')
      return
    }
    setError(null)
    setInfo(null)
    setSubmitting(true)
    try {
      const supabase = getSupabase()
      const { error: otpErr } = await supabase.auth.signInWithOtp({
        email,
        options: { emailRedirectTo: `${window.location.origin}/admin` },
      })
      if (otpErr) throw otpErr
      setInfo('Check your email for a sign-in link.')
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not send magic link')
    } finally {
      setSubmitting(false)
    }
  }

  const notAdmin = session && adminCheckDone && !isAdmin

  return (
    <div className="admin-login">
      <div className="admin-login-card">
        <div className="admin-login-title">
          <span className="admin-sidebar-brand-dot" />
          Daily OK Admin
        </div>
        <div className="admin-login-sub">Sign in with an admin account.</div>

        {error && <div className="admin-error">{error}</div>}
        {info && <div className="admin-success">{info}</div>}
        {notAdmin && (
          <div className="admin-error">
            Signed in, but this account does not have admin access.
          </div>
        )}

        <form onSubmit={handleSubmit} className="admin-form">
          <div>
            <label className="admin-label" htmlFor="admin-email">Email</label>
            <input
              id="admin-email"
              type="email"
              className="admin-input"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              autoComplete="email"
              required
            />
          </div>
          <div>
            <label className="admin-label" htmlFor="admin-password">Password</label>
            <input
              id="admin-password"
              type="password"
              className="admin-input"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              autoComplete="current-password"
            />
          </div>
          <button type="submit" className="admin-btn admin-btn-primary" disabled={submitting}>
            {submitting ? 'Signing in…' : 'Sign in'}
          </button>
          <button type="button" className="admin-btn admin-btn-secondary" onClick={handleMagicLink} disabled={submitting}>
            Send magic link instead
          </button>
        </form>
      </div>
    </div>
  )
}
