import { assertEquals } from "std/assert/mod.ts";
import { normalizeCheckinSource } from "./checkin-source.ts";

Deno.test("Known sources pass through", () => {
  for (const s of ["app", "notification", "on_demand", "need_help", "call_me", "watch", "widget", "control", "siri"]) {
    assertEquals(normalizeCheckinSource(s), s);
  }
});

Deno.test("Case and whitespace from a hand-built shortcut are tolerated", () => {
  assertEquals(normalizeCheckinSource(" Widget "), "widget");
  assertEquals(normalizeCheckinSource("SIRI"), "siri");
});

Deno.test("Anything else is recorded as app instead of failing the check-in", () => {
  assertEquals(normalizeCheckinSource("Good morning shortcut"), "app");
  assertEquals(normalizeCheckinSource(""), "app");
  assertEquals(normalizeCheckinSource(undefined), "app");
  assertEquals(normalizeCheckinSource(42), "app");
});
