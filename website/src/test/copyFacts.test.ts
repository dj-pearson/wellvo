import { describe, it, expect } from 'vitest'
import { readFileSync, readdirSync } from 'node:fs'
import { join } from 'node:path'

/**
 * Guards the owner-confirmed product facts the marketing copy kept
 * contradicting: the app is iPhone-only for now, the free trial is 7 days on
 * monthly AND yearly, and location is off unless the loved one shares it.
 *
 * Privacy, Terms and Cookies are legal documents that name Google Play / FCM
 * as processors for the future Android app, so they are deliberately exempt.
 */

const root = join(__dirname, '..', '..')
const LEGAL = new Set(['Privacy.tsx', 'Terms.tsx', 'Cookies.tsx'])

function marketingSources(): [string, string][] {
  const files: [string, string][] = []
  for (const f of readdirSync(join(root, 'src', 'pages'))) {
    if (f.endsWith('.tsx') && !LEGAL.has(f)) files.push([f, readFileSync(join(root, 'src', 'pages', f), 'utf8')])
  }
  for (const f of readdirSync(join(root, 'src', 'data', 'competitors'))) {
    if (f.endsWith('.json')) files.push([f, readFileSync(join(root, 'src', 'data', 'competitors', f), 'utf8')])
  }
  for (const f of ['src/data/whatToDo.ts', 'public/llms-full.txt', 'scripts/generate-llms-txt.mjs', 'pages/+onRenderHtml.tsx']) {
    files.push([f, readFileSync(join(root, f), 'utf8')])
  }
  return files
}

describe('marketing copy matches the confirmed product facts', () => {
  it.each(marketingSources())('%s does not offer an Android app or a 14-day trial', (_name, text) => {
    expect(text).not.toMatch(/google play|play\.google\.com|iphone or android|available on ios and android/i)
    expect(text).not.toMatch(/14-day|14 days/i)
  })

  it('declares only iOS in the SoftwareApplication JSON-LD', () => {
    const head = readFileSync(join(root, 'pages', '+onRenderHtml.tsx'), 'utf8')
    expect(head).toContain('"operatingSystem": "iOS",')
  })

  it('keeps the llms.txt preamble identical to llms-full.txt', () => {
    const full = readFileSync(join(root, 'public', 'llms-full.txt'), 'utf8')
    const gen = readFileSync(join(root, 'scripts', 'generate-llms-txt.mjs'), 'utf8')
    const block = (s: string) => s.split('\n').filter((l) => l.startsWith('> ')).slice(0, 8).join('\n')
    expect(block(gen)).toBe(block(full))
    expect(block(full)).toContain('Available on iPhone.')
  })
})
