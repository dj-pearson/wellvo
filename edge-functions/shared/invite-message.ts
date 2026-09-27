/**
 * The invite link and text an owner sends a receiver. Kept free of the
 * Supabase client so it can be unit-tested.
 */

export function buildInviteLink(token: string, pairingCode: string): string {
  return `https://dailyok.net/invite/${token}?code=${pairingCode}`;
}

/**
 * The text the owner sends. Works for every receiver: the link opens the app
 * (or the invite page, which routes to the right store and has an "Open Daily
 * OK" button); after signing in (Apple, Google or email — phone-number sign-in
 * was retired), tapping the link again shows the family and joins; and the
 * code covers an iPad or a link that won't open the app.
 */
export function buildInviteMessage(name: string, inviteLink: string, pairingCode: string): string {
  return `Hi ${name}! I'd like to check in with you each day using Daily OK — ` +
    `you just tap "I'm OK" once a day.\n\n` +
    `1. Get the app: ${inviteLink}\n` +
    `2. Sign in, then tap this link again to join.\n\n` +
    `Or enter this setup code in the app: ${pairingCode}`;
}

/**
 * The text an owner sends a co-caregiver (a viewer): someone who is told when
 * a check-in is missed, and never asked to check in themselves.
 */
export function buildCaregiverInviteMessage(name: string, inviteLink: string, pairingCode: string): string {
  return `Hi ${name}! I'm using Daily OK to check in on our family each day. ` +
    `Join me so you're told too if a check-in is missed — you won't be asked to check in yourself.\n\n` +
    `1. Get the app: ${inviteLink}\n` +
    `2. Sign in, then tap this link again to join.\n\n` +
    `Or enter this setup code in the app: ${pairingCode}`;
}
