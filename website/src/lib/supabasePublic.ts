import { createClient, type SupabaseClient } from '@supabase/supabase-js'

/**
 * Anonymous, read-only client for public blog reads. Public pages load this
 * module with a dynamic import, and only when a post is not already seeded by
 * the prerender, so supabase-js stays out of their first-load JS. It never
 * touches the admin session: nothing is persisted, refreshed or read from the
 * URL.
 */
let cachedClient: SupabaseClient | null = null

export function getPublicSupabase(): SupabaseClient {
  const url = import.meta.env.VITE_SUPABASE_URL
  const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY
  if (!url || !anonKey) {
    throw new Error('Supabase is not configured. Set VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY.')
  }
  if (!cachedClient) {
    cachedClient = createClient(url, anonKey, {
      auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    })
  }
  return cachedClient
}
