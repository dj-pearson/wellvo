/**
 * Whether the build has Supabase credentials. Kept apart from supabase.ts so
 * public pages can ask without statically importing supabase-js.
 */
export function isSupabaseConfigured(): boolean {
  return !!(import.meta.env.VITE_SUPABASE_URL && import.meta.env.VITE_SUPABASE_ANON_KEY)
}
