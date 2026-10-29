/**
 * Writes public/app-store-qr.svg: a QR code for the App Store listing, shown
 * beside the App Store badge to desktop visitors so they can scan it with
 * their iPhone (no phone in hand = no install path otherwise).
 *
 * The URL is read from src/lib/appStore.ts so the QR can never drift from the
 * links. The SVG is committed; re-run `npm run qr` whenever APP_STORE_URL
 * changes (src/test/appStoreQr.test.ts fails until you do). Not part of
 * `npm run build`, so a deploy never depends on this devDependency.
 */
import { readFileSync, writeFileSync } from 'fs'
import { dirname, join } from 'path'
import { fileURLToPath } from 'url'
import QRCode from 'qrcode'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')

export function readAppStoreUrl() {
  const src = readFileSync(join(root, 'src/lib/appStore.ts'), 'utf-8')
  const match = src.match(/APP_STORE_URL\s*=\s*'([^']+)'/)
  if (!match) throw new Error('APP_STORE_URL not found in src/lib/appStore.ts')
  return match[1]
}

/** Dark modules in --gray-900 on white: the same contrast a scanner needs. */
export function renderAppStoreQr(url) {
  return QRCode.toString(url, {
    type: 'svg',
    errorCorrectionLevel: 'M',
    margin: 2,
    color: { dark: '#111827', light: '#ffffff' },
  })
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const svg = await renderAppStoreQr(readAppStoreUrl())
  writeFileSync(join(root, 'public/app-store-qr.svg'), svg)
  console.log('wrote public/app-store-qr.svg')
}
