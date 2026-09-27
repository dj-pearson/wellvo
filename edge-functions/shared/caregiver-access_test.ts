import { assertEquals } from "std/assert/mod.ts";
import { caregiverActorRole } from "./caregiver-access.ts";

Deno.test("the owner may act on their family's escalations", () => {
  assertEquals(caregiverActorRole("owner-1", "owner-1", null), "owner");
  assertEquals(caregiverActorRole("OWNER-1", "owner-1", null), "owner");
});

Deno.test("an active co-caregiver may act; anyone else may not", () => {
  assertEquals(caregiverActorRole("owner-1", "tom", { role: "viewer", status: "active" }), "viewer");
  // Removed (deactivated) / invited but not yet joined.
  assertEquals(caregiverActorRole("owner-1", "tom", { role: "viewer", status: "deactivated" }), null);
  assertEquals(caregiverActorRole("owner-1", "tom", { role: "viewer", status: "invited" }), null);
  // Receivers never stand down or send check-ins.
  assertEquals(caregiverActorRole("owner-1", "mom", { role: "receiver", status: "active" }), null);
  // Not a member of this family (another family's caregiver).
  assertEquals(caregiverActorRole("owner-1", "stranger", null), null);
  // No user.
  assertEquals(caregiverActorRole("owner-1", null, { role: "viewer", status: "active" }), null);
});
