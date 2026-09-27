// Phone matching for auto-join (no imports, so it can be unit-tested).

/**
 * An invite's phone, as the owner typed it, in E.164 digits: a bare 10-digit
 * number without a "+" is North American (the apps only ever prefix +1),
 * anything else is taken as written.
 */
export function inviteE164Digits(raw: string | null): string {
  const digits = (raw ?? "").replace(/[^\d]/g, "");
  if (digits.length === 10 && !(raw ?? "").trim().startsWith("+")) return "1" + digits;
  return digits;
}

/**
 * Whether Supabase Auth's verified phone (always E.164 with its country code)
 * is the number an invite was sent to.
 *
 * This used to add a leading "1" to a 10-digit verified number and strip one
 * from the invite side. A 10-digit verified number is never North American
 * (those are 11 digits with the 1), so that turned e.g. Norway +47 9xxxxxxx
 * into +1 479-xxx-xxxx and let its holder claim a US invite.
 */
export function verifiedPhoneMatchesInvite(verified: string, invitePhone: string | null): boolean {
  const v = verified.replace(/[^\d]/g, "");
  const inv = inviteE164Digits(invitePhone);
  return v !== "" && inv !== "" && v === inv;
}
