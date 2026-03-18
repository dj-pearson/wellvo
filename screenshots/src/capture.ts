import { chromium, Browser, Page } from 'playwright'
import * as path from 'path'
import * as fs from 'fs'
import { devices, DeviceSpec } from './devices'
import { getScreenHTML } from './screens'

/**
 * App Store Screenshot Generator for Wellvo
 *
 * Generates screenshots at exact App Store required resolutions
 * by rendering HTML mockups of each app screen in a headless browser.
 *
 * Output: screenshots/output/{device-slug}/{screen-id}.png
 * All images are at the exact physical pixel dimensions required.
 */

const SCREEN_IDS = [
  'receiver-checkin',   // 1. Hero: "I'm OK" button
  'receiver-done',      // 2. Check-in confirmed
  'mood-selector',      // 3. Mood selector sheet
  'owner-dashboard',    // 4. Owner dashboard
  'history-heatmap',    // 5. History with heatmap + chart
  'family-management',  // 6. Family member management
  'plan-selection',     // 7. Plan selection / pricing
]

const OUTPUT_DIR = path.resolve(__dirname, '..', 'output')

interface CaptureOptions {
  /** Only capture required devices */
  requiredOnly: boolean
  /** Only capture specific screens (by ID) */
  screens?: string[]
  /** Only capture specific devices (by slug) */
  deviceSlugs?: string[]
}

async function captureScreen(
  page: Page,
  device: DeviceSpec,
  screenId: string,
): Promise<string> {
  const html = getScreenHTML(screenId, device)
  const deviceDir = path.join(OUTPUT_DIR, device.slug)
  fs.mkdirSync(deviceDir, { recursive: true })

  // Set viewport to logical size
  await page.setViewportSize({
    width: device.logicalWidth,
    height: device.logicalHeight,
  })

  await page.setContent(html, { waitUntil: 'networkidle' })

  // Wait for fonts to load
  await page.evaluate(() => document.fonts.ready)
  // Small extra wait for rendering stability
  await page.waitForTimeout(200)

  const outputPath = path.join(deviceDir, `${screenId}.png`)

  // Screenshot at the correct DPR to produce exact physical resolution
  await page.screenshot({
    path: outputPath,
    type: 'png',
    // Clip to exact viewport to avoid any scrollbar artifacts
    clip: {
      x: 0,
      y: 0,
      width: device.logicalWidth,
      height: device.logicalHeight,
    },
    // No omitBackground — we want the white/gradient backgrounds
  })

  // Verify dimensions
  return outputPath
}

async function main() {
  const args = process.argv.slice(2)
  const opts: CaptureOptions = {
    requiredOnly: args.includes('--required-only'),
    screens: args.filter(a => a.startsWith('--screen=')).map(a => a.split('=')[1]),
    deviceSlugs: args.filter(a => a.startsWith('--device=')).map(a => a.split('=')[1]),
  }

  console.log('=== Wellvo App Store Screenshot Generator ===\n')

  // Filter devices
  let targetDevices = devices
  if (opts.requiredOnly) {
    targetDevices = devices.filter(d => d.required)
    console.log(`Mode: Required devices only (${targetDevices.length} devices)`)
  }
  if (opts.deviceSlugs && opts.deviceSlugs.length > 0) {
    targetDevices = targetDevices.filter(d => opts.deviceSlugs!.includes(d.slug))
  }

  // Filter screens
  let targetScreens = SCREEN_IDS
  if (opts.screens && opts.screens.length > 0) {
    targetScreens = targetScreens.filter(s => opts.screens!.includes(s))
  }

  console.log(`Devices: ${targetDevices.map(d => d.name).join(', ')}`)
  console.log(`Screens: ${targetScreens.join(', ')}`)
  console.log(`Total captures: ${targetDevices.length * targetScreens.length}\n`)

  // Clean output
  if (fs.existsSync(OUTPUT_DIR)) {
    fs.rmSync(OUTPUT_DIR, { recursive: true })
  }
  fs.mkdirSync(OUTPUT_DIR, { recursive: true })

  const browser: Browser = await chromium.launch({
    args: ['--hide-scrollbars'],
  })

  let totalCaptured = 0
  const errors: string[] = []

  for (const device of targetDevices) {
    console.log(`\n📱 ${device.name} (${device.width}x${device.height} @ ${device.dpr}x)`)
    console.log(`   Logical: ${device.logicalWidth}x${device.logicalHeight}px`)

    // Create a context with the correct device pixel ratio
    const context = await browser.newContext({
      viewport: {
        width: device.logicalWidth,
        height: device.logicalHeight,
      },
      deviceScaleFactor: device.dpr,
      // Disable animations for clean screenshots
      reducedMotion: 'reduce',
    })

    const page = await context.newPage()

    for (const screenId of targetScreens) {
      try {
        const outputPath = await captureScreen(page, device, screenId)
        const stats = fs.statSync(outputPath)
        console.log(`   ✅ ${screenId}.png (${(stats.size / 1024).toFixed(0)} KB)`)
        totalCaptured++
      } catch (err) {
        const msg = `${device.slug}/${screenId}: ${err}`
        console.log(`   ❌ ${screenId}: ${err}`)
        errors.push(msg)
      }
    }

    await context.close()
  }

  await browser.close()

  // Summary
  console.log('\n=== Summary ===')
  console.log(`✅ ${totalCaptured} screenshots captured`)
  if (errors.length > 0) {
    console.log(`❌ ${errors.length} errors:`)
    errors.forEach(e => console.log(`   - ${e}`))
  }
  console.log(`\n📁 Output: ${OUTPUT_DIR}`)

  // Generate manifest
  const manifest = {
    generated: new Date().toISOString(),
    devices: targetDevices.map(d => ({
      name: d.name,
      slug: d.slug,
      resolution: `${d.width}x${d.height}`,
      required: d.required,
      screenshots: targetScreens.map(s => ({
        screen: s,
        file: `${d.slug}/${s}.png`,
        width: d.width,
        height: d.height,
      })),
    })),
  }
  fs.writeFileSync(
    path.join(OUTPUT_DIR, 'manifest.json'),
    JSON.stringify(manifest, null, 2),
  )
  console.log('📋 Manifest written to output/manifest.json')

  if (errors.length > 0) process.exit(1)
}

main().catch(err => {
  console.error('Fatal error:', err)
  process.exit(1)
})
