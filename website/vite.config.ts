import { defineConfig, loadEnv } from 'vite'
import react from '@vitejs/plugin-react'
import vike from 'vike/plugin'

// https://vite.dev/config/
export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '')
  const viteKeys = Object.keys(env).filter((k) => k.startsWith('VITE_'))
  // Deliberately logs to the build output — helpful for diagnosing
  // Cloudflare Pages env var injection. Values are not logged, only keys.
  console.log(`[vite] VITE_* env keys visible to build (${viteKeys.length}):`, viteKeys.length ? viteKeys : '(none)')
  if (!env.VITE_SUPABASE_URL) console.log('[vite] WARNING: VITE_SUPABASE_URL is missing — admin login will fail at runtime')
  if (!env.VITE_SUPABASE_ANON_KEY) console.log('[vite] WARNING: VITE_SUPABASE_ANON_KEY is missing — admin login will fail at runtime')
  if (!env.VITE_EDGE_FUNCTIONS_URL) console.log('[vite] WARNING: VITE_EDGE_FUNCTIONS_URL is missing — admin API calls will fail at runtime')

  return {
  plugins: [react(), vike()],
  build: {
    rollupOptions: {
      output: {
        manualChunks(id: string) {
          if (id.includes('node_modules/react-dom') || id.includes('node_modules/react/') || id.includes('node_modules/react-router-dom')) {
            return 'vendor';
          }
          if (id.includes('node_modules/lucide-react')) {
            return 'icons';
          }
          if (id.includes('node_modules/@supabase')) {
            return 'supabase';
          }
          if (id.includes('node_modules/@tiptap') || id.includes('node_modules/prosemirror')) {
            return 'editor';
          }
        },
      },
    },
  },
  }
})
