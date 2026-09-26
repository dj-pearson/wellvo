/** Helpers for the receiver invite page (pages/Invite.tsx). */

export const APP_STORE_URL = 'https://apps.apple.com/us/app/dailyok-daily-check-in/id6760836697'
export const PLAY_STORE_URL = 'https://play.google.com/store/apps/details?id=net.dailyok.android'

const TOKEN_RE = /^[0-9a-f]{16,128}$/i
const CODE_RE = /^\d{6}$/

export type Platform = 'ios' | 'android' | 'other'

export function detectPlatform(userAgent: string): Platform {
  if (/android/i.test(userAgent)) return 'android'
  // iPadOS reports itself as a Mac; the touch check tells them apart.
  if (/iphone|ipad|ipod/i.test(userAgent)) return 'ios'
  if (/macintosh/i.test(userAgent) && typeof navigator !== 'undefined' && navigator.maxTouchPoints > 1) {
    return 'ios'
  }
  return 'other'
}

export function readInvite(pathToken: string | undefined, search: string): { token: string | null; code: string | null } {
  const params = new URLSearchParams(search)
  const rawToken = pathToken ?? params.get('token') ?? ''
  const rawCode = params.get('code') ?? ''
  return {
    token: TOKEN_RE.test(rawToken) ? rawToken : null,
    code: CODE_RE.test(rawCode) ? rawCode : null,
  }
}
