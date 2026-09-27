import { assertEquals } from "std/assert/mod.ts";
import {
  followUpUpgrade,
  isKidInfoSignal,
  isRepeatOfRecentAlert,
  isUndoableRow,
  isUrgentSignal,
} from "./checkin-followup.ts";

// "I'm OK" at 9 AM, "I need help" at 3 PM: the 3 PM request used to be
// answered with the 9 AM row and nobody was told.

Deno.test("Help after an OK upgrades the row", () => {
  assertEquals(followUpUpgrade({ response_type: "ok" }, "need_help", null), { response_type: "need_help" });
  assertEquals(followUpUpgrade({ response_type: "ok" }, "call_me", null), { response_type: "call_me" });
  assertEquals(followUpUpgrade({ response_type: "call_me" }, "need_help", null), { response_type: "need_help" });
});

Deno.test("A follow-up never downgrades", () => {
  assertEquals(followUpUpgrade({ response_type: "need_help" }, "ok", null), {});
  assertEquals(followUpUpgrade({ response_type: "need_help" }, "call_me", null), {});
  assertEquals(followUpUpgrade({ response_type: "ok", kid_response_type: "sos" }, "ok", "can_stay_longer"), {});
  assertEquals(followUpUpgrade({ response_type: "ok", kid_response_type: "picking_me_up" }, "ok", "can_stay_longer"), {});
});

Deno.test("Kid replies rank can_stay_longer < picking_me_up < sos", () => {
  assertEquals(followUpUpgrade({ response_type: "ok", kid_response_type: null }, "ok", "can_stay_longer"), { kid_response_type: "can_stay_longer" });
  assertEquals(followUpUpgrade({ response_type: "ok", kid_response_type: "can_stay_longer" }, "ok", "picking_me_up"), { kid_response_type: "picking_me_up" });
  assertEquals(followUpUpgrade({ response_type: "ok", kid_response_type: "picking_me_up" }, "ok", "sos"), { kid_response_type: "sos" });
});

Deno.test("Unknown values change nothing", () => {
  assertEquals(followUpUpgrade({ response_type: "ok" }, "bogus", "bogus"), {});
  assertEquals(followUpUpgrade({ response_type: null }, undefined, undefined), {});
});

Deno.test("Urgent and kid-info classification", () => {
  assertEquals(isUrgentSignal("need_help", null), true);
  assertEquals(isUrgentSignal("call_me", null), true);
  assertEquals(isUrgentSignal("ok", "sos"), true);
  assertEquals(isUrgentSignal("ok", "picking_me_up"), false);
  assertEquals(isKidInfoSignal("picking_me_up"), true);
  assertEquals(isKidInfoSignal("can_stay_longer"), true);
  assertEquals(isKidInfoSignal("sos"), false);
});

Deno.test("A retry within two minutes is not a second alert; later it is", () => {
  const now = new Date("2026-09-27T15:00:00Z");
  assertEquals(isRepeatOfRecentAlert("2026-09-27T14:59:30Z", now), true);
  assertEquals(isRepeatOfRecentAlert("2026-09-27T14:57:00Z", now), false);
  assertEquals(isRepeatOfRecentAlert(null, now), false);
  assertEquals(isRepeatOfRecentAlert("not a date", now), false);
});

Deno.test("Help rows are not undoable; OK and kid info rows are", () => {
  assertEquals(isUndoableRow({ response_type: "ok" }), true);
  assertEquals(isUndoableRow({ response_type: "ok", kid_response_type: "picking_me_up" }), true);
  assertEquals(isUndoableRow({ response_type: "need_help" }), false);
  assertEquals(isUndoableRow({ response_type: "call_me" }), false);
  assertEquals(isUndoableRow({ response_type: "ok", kid_response_type: "sos" }), false);
});
