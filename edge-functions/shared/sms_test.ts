import { assertEquals } from "std/assert/mod.ts";
import { parseSmsEnabled, SMS_ENABLED, sendSMS } from "./sms.ts";

Deno.test("server SMS is off unless explicitly switched on", () => {
  assertEquals(parseSmsEnabled(undefined), false);
  assertEquals(parseSmsEnabled(null), false);
  assertEquals(parseSmsEnabled(""), false);
  assertEquals(parseSmsEnabled("false"), false);
  assertEquals(parseSmsEnabled("0"), false);
  assertEquals(parseSmsEnabled("yes"), false);
  assertEquals(parseSmsEnabled("true"), true);
  assertEquals(parseSmsEnabled(" TRUE "), true);
  assertEquals(parseSmsEnabled("1"), true);
});

Deno.test("sendSMS sends nothing while SMS is disabled", async () => {
  if (SMS_ENABLED) return; // only meaningful in the default configuration
  const result = await sendSMS("+15555550100", "hello");
  assertEquals(result, { success: false, error: "SMS disabled" });
});
