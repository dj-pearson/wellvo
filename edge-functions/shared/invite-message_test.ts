import { assertEquals, assertStringIncludes } from "std/assert/mod.ts";
import { buildInviteLink, buildInviteMessage } from "./invite-message.ts";

// The link must be path-based: the AASA and Android App Links match
// `/invite/*`, and the website serves /invite/:token. The query form the
// server used to send matched neither and landed on a 404.
Deno.test("invite link is path-based and carries the code", () => {
  assertEquals(buildInviteLink("ab12", "123456"), "https://dailyok.net/invite/ab12?code=123456");
});

Deno.test("invite text has the link and the setup code, and no hard-coded store id", () => {
  const link = buildInviteLink("ab12", "123456");
  const text = buildInviteMessage("Mom", link, "123456");
  assertStringIncludes(text, "Hi Mom!");
  assertStringIncludes(text, link);
  assertStringIncludes(text, "123456");
  // The old text hard-coded an App Store id that did not match the app's.
  assertEquals(text.includes("apps.apple.com"), false);
});
