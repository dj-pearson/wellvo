import { createClient, type SupabaseClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY

let cachedClient: SupabaseClient | null = null

export function getSupabase(): SupabaseClient {
  if (!url || !anonKey) {
    throw new Error(
      'Supabase is not configured. Set VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY.'
    )
  }
  if (!cachedClient) {
    cachedClient = createClient(url, anonKey, {
      auth: {
        persistSession: true,
        autoRefreshToken: true,
        detectSessionInUrl: true,
        storageKey: 'dailyok-admin-auth',
        // PKCE: the magic link returns a one-time ?code= that only this
        // browser (holding the verifier) can exchange, instead of tokens in
        // the URL fragment.
        flowType: 'pkce',
      },
    })
  }
  return cachedClient
}

export { isSupabaseConfigured } from './supabaseConfig'
