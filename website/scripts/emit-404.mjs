/**
 * Lift the prerendered /404 page to dist/client/404.html (US-SEO016).
 *
 * Cloudflare Pages serves /404.html for any path it cannot match, with a real
 * 404 status. Without that file it answers with its own generic page, so
 * src/pages/NotFound.tsx — which exists and is routed — could only ever render
 * during a client-side navigation inside an already-loaded SPA. That is the
 * one case where the visitor is not lost. Every direct hit, stale backlink and
 * crawler fetch got the generic page.
 *
 * Runs immediately after `vike prerender` and before the sitemap and llms.txt
 * generators, and removes the /404/ directory afterwards so the site does not
 * also serve a 200 at /404/ that duplicates the error page.
 */
import { copyFileSync, existsSync, rmSync } from 'fs'
import { join, dirname } from 'path'
import { fileURLToPath } from 'url'

const __dirname = dirname(fileURLToPath(import.meta.url))
const distClient = join(__dirname, '..', 'dist', 'client')
const source = join(distClient, '404', 'index.html')
const target = join(distClient, '404.html')

if (!existsSync(source)) {
  console.error('[404] dist/client/404/index.html is missing — is "/404" still in +onBeforePrerenderStart.ts?')
  process.exit(1)
}

copyFileSync(source, target)
rmSync(join(distClient, '404'), { recursive: true, force: true })

console.log('[404] wrote dist/client/404.html')
