/**
 * The invite link and text an owner sends a receiver. Kept free of the
 * Supabase client so it can be unit-tested.
 */

export function buildInviteLink(token: string, pairingCode: string): string {
  return `https://dailyok.net/invite/${token}?code=${pairingCode}`;
}

/**
 * The text the owner sends. Works for every receiver: the link opens the app
 * (or the invite page, which routes to the right store); signing in with the
 * invited number connects them automatically; and the code covers an iPad, a
 * different number, or Apple / email sign-in.
 */
export function buildInviteMessage(name: string, inviteLink: string, pairingCode: string): string {
  return `Hi ${name}! I'd like to check in with you each day using Daily OK — ` +
    `you just tap "I'm OK" once a day.\n\n` +
    `1. Get the app: ${inviteLink}\n` +
    `2. Sign in with this phone number and we're connected.\n\n` +
    `Using a different phone, an iPad, or no phone number? Enter this setup code in the app: ${pairingCode}`;
}
