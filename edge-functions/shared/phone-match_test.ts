import { assertEquals } from "std/assert/mod.ts";
import { verifiedPhoneMatchesInvite } from "./phone-match.ts";

// Supabase Auth stores verified phones in E.164 digits. Auto-join used to add
// a "1" to any 10-digit verified number, so a Norwegian +47 9xxxxxxx matched
// an invite to +1 479-xxx-xxxx.

Deno.test("US verified number matches the ways an owner types it", () => {
  for (const typed of ["5551234567", "(555) 123-4567", "+1 555 123 4567", "1-555-123-4567", "+15551234567"]) {
    assertEquals(verifiedPhoneMatchesInvite("15551234567", typed), true, typed);
  }
  assertEquals(verifiedPhoneMatchesInvite("+15551234567", "555.123.4567"), true);
});

Deno.test("A 10-digit (non-NANP) verified number no longer claims a US invite", () => {
  assertEquals(verifiedPhoneMatchesInvite("4791234567", "(479) 123-4567"), false);
  assertEquals(verifiedPhoneMatchesInvite("4791234567", "+1 479 123 4567"), false);
  // …but still matches the same foreign number written with its country code.
  assertEquals(verifiedPhoneMatchesInvite("4791234567", "+47 912 34 567"), true);
});

Deno.test("International numbers compare as written", () => {
  assertEquals(verifiedPhoneMatchesInvite("447700900123", "+44 7700 900123"), true);
  assertEquals(verifiedPhoneMatchesInvite("447700900123", "07700 900123"), false);
});

Deno.test("Empty never matches", () => {
  assertEquals(verifiedPhoneMatchesInvite("15551234567", null), false);
  assertEquals(verifiedPhoneMatchesInvite("15551234567", ""), false);
  assertEquals(verifiedPhoneMatchesInvite("", ""), false);
});
