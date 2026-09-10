/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_SUPABASE_URL?: string
  readonly VITE_SUPABASE_ANON_KEY?: string
  readonly VITE_EDGE_FUNCTIONS_URL?: string
  readonly VITE_CLOUDFLARE_ANALYTICS_URL?: string
  /** Cloudflare Web Analytics site token, 32 hex chars. See US-SEO004. */
  readonly VITE_CF_ANALYTICS_TOKEN?: string
  readonly VITE_SENTRY_DSN?: string
  readonly VITE_SENTRY_ENABLED?: string
  readonly VITE_SENTRY_ENVIRONMENT?: string
  readonly VITE_SENTRY_RELEASE?: string
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}
