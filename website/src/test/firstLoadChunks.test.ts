import { existsSync, readFileSync } from 'node:fs'
import { posix, resolve } from 'node:path'
import { describe, it, expect } from 'vitest'

/**
 * Guards the first-load JS of public pages against the admin editor.
 *
 * A `manualChunks` rule in vite.config.ts once routed @tiptap/prosemirror into
 * an "editor" chunk. Under Vite 8/rolldown that chunk also absorbed React core,
 * so every public page statically imported and modulepreloaded ~107 KB gz of
 * ProseMirror it never runs. The editor must only arrive via the admin route's
 * lazy import.
 *
 * The dist check walks the entry script, every modulepreload, and their static
 * imports. It needs a built site (`vite build && vike prerender`) and skips
 * when dist/client is absent so a fresh checkout's `npm test` stays green.
 */

const root = resolve(__dirname, '../..')
const client = resolve(root, 'dist/client')
const builtHome = resolve(client, 'index.html')

function firstLoadScripts(htmlPath: string): string[] {
  const html = readFileSync(htmlPath, 'utf-8')
  const queue = [...html.matchAll(/(?:src|href)="(\/assets\/[^"]+\.js)"/g)].map((m) => m[1])
  const seen = new Set<string>()
  while (queue.length) {
    const file = queue.shift()!
    if (seen.has(file)) continue
    seen.add(file)
    const src = readFileSync(resolve(client, '.' + file), 'utf-8')
    // Static imports only — `import("…")` is lazy and allowed to pull the editor.
    for (const m of src.matchAll(/(?:^|[;\n}])\s*import\s*(?:[^"'()]*?from\s*)?["']([^"']+\.js)["']/g)) {
      queue.push(posix.join(posix.dirname(file), m[1]))
    }
  }
  return [...seen]
}

describe('first-load JS', () => {
  it('vite.config.ts does not hand-assign vendor chunks', () => {
    const config = readFileSync(resolve(root, 'vite.config.ts'), 'utf-8')
    expect(config).not.toMatch(/manualChunks|advancedChunks/)
  })

  it.skipIf(!existsSync(builtHome))('home page does not load ProseMirror/tiptap', () => {
    const scripts = firstLoadScripts(builtHome)
    expect(scripts.length).toBeGreaterThan(0)
    for (const file of scripts) {
      const src = readFileSync(resolve(client, '.' + file), 'utf-8')
      expect(src, file).not.toMatch(/ProseMirror|@tiptap/)
    }
  })

  // AdminAuthProvider used to wrap every page, so supabase-js (~48 KB gz) and
  // a getSession() call shipped to public visitors. It now mounts only under
  // the lazy /admin route; blog pages import their client lazily too.
  it.skipIf(!existsSync(builtHome))('home page does not load supabase-js', () => {
    for (const file of firstLoadScripts(builtHome)) {
      const src = readFileSync(resolve(client, '.' + file), 'utf-8')
      expect(src, file).not.toMatch(/GoTrueClient|PostgrestClient/)
    }
  })

  // src/lib/sentry.ts imports @sentry/react dynamically once the browser is
  // idle; a static import would put ~28 KB gz back on every page's first load.
  it.skipIf(!existsSync(builtHome))('home page does not load the Sentry SDK', () => {
    for (const file of firstLoadScripts(builtHome)) {
      const src = readFileSync(resolve(client, '.' + file), 'utf-8')
      expect(src, file).not.toMatch(/sentry_key|__sentry_instrumentation_handlers__/)
    }
  })
})
