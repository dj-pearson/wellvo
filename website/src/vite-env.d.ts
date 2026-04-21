/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_SUPABASE_URL?: string
  readonly VITE_SUPABASE_ANON_KEY?: string
  readonly VITE_EDGE_FUNCTIONS_URL?: string
  readonly VITE_CLOUDFLARE_ANALYTICS_URL?: string
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}
