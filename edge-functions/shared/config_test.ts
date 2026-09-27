import { assertEquals } from "std/assert/mod.ts";
import {
  appConfigPayload,
  compareVersions,
  forceUpdatePayload,
  isBelowMinimum,
  MIN_SUPPORTED_ANDROID_APP_VERSION,
  MIN_SUPPORTED_IOS_APP_VERSION,
} from "./config.ts";

Deno.test("compareVersions treats missing segments as zero", () => {
  assertEquals(compareVersions("1.0.10", "1.0.9") > 0, true);
  assertEquals(compareVersions("1.0", "1.0.0"), 0);
  assertEquals(compareVersions("1.0.6", "1.0.7") < 0, true);
  assertEquals(compareVersions("junk", "0.0.0"), 0);
});

Deno.test("the gate is dormant by default and never blocks a header-less build", () => {
  // Default config ("0.0.0"): nothing is below the floor.
  if (MIN_SUPPORTED_IOS_APP_VERSION === "0.0.0") {
    assertEquals(isBelowMinimum("ios", "0.0.1"), false);
    assertEquals(isBelowMinimum(null, "1.0.0"), false);
  }
  if (MIN_SUPPORTED_ANDROID_APP_VERSION === "0.0.0") {
    assertEquals(isBelowMinimum("android", "0.0.1"), false);
  }
  assertEquals(isBelowMinimum("ios", null), false);
  assertEquals(isBelowMinimum("android", ""), false);
});

Deno.test("app-config and 426 payloads carry the fields the apps decode", () => {
  const cfg = appConfigPayload();
  assertEquals(Object.keys(cfg).sort(), [
    "min_android_version",
    "min_ios_version",
    "update_url_android",
    "update_url_ios",
  ]);
  assertEquals(forceUpdatePayload("android").error, "update_required");
  assertEquals(forceUpdatePayload("android").update_url, cfg.update_url_android);
  assertEquals(forceUpdatePayload("ios").update_url, cfg.update_url_ios);
});
