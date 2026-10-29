import { execFileSync } from 'node:child_process'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, it, expect } from 'vitest'

/**
 * public/app-store-qr.svg is generated from APP_STORE_URL and committed. If the
 * URL changes and nobody re-runs `npm run qr`, desktop visitors would scan
 * their way to the old listing — so regenerate it here and compare.
 */
describe('App Store QR code', () => {
  it('matches what scripts/generate-app-store-qr.mjs renders for APP_STORE_URL', () => {
    const root = resolve(__dirname, '../..')
    const fresh = execFileSync(
      process.execPath,
      [
        '--input-type=module',
        '-e',
        "const m = await import('./scripts/generate-app-store-qr.mjs'); process.stdout.write(await m.renderAppStoreQr(m.readAppStoreUrl()))",
      ],
      { cwd: root, encoding: 'utf-8' },
    )
    expect(readFileSync(resolve(root, 'public/app-store-qr.svg'), 'utf-8')).toBe(fresh)
  })
})
