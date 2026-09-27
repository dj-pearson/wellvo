import { assertEquals } from "std/assert/mod.ts";
import {
  capUnverifiedExpiry,
  decideApply,
  MAX_UNVERIFIED_TERM_MS,
  notificationAction,
  tierForProduct,
  tierRank,
} from "./subscription-policy.ts";

const now = new Date("2026-09-27T12:00:00Z");
const inDays = (d: number) => new Date(now.getTime() + d * 86_400_000);

Deno.test("both product namespaces map to the same tiers; add-ons and unknowns don't", () => {
  assertEquals(tierForProduct("net.wellvo.familyplus.yearly")?.maxReceivers, 6);
  assertEquals(tierForProduct("net.dailyok.familyplus.yearly")?.maxViewers, 10);
  assertEquals(tierForProduct("net.wellvo.caregiver.monthly")?.tier, "caregiver");
  assertEquals(tierForProduct("net.wellvo.addon.receiver"), null);
  assertEquals(tierForProduct(""), null);
  assertEquals(tierRank("family_plus") > tierRank("family"), true);
  assertEquals(tierRank("free"), 0);
});

Deno.test("an unverified expiry is capped at one yearly term and junk is refused", () => {
  assertEquals(capUnverifiedExpiry("", now), null);
  assertEquals(capUnverifiedExpiry("not a date", now), null);
  assertEquals(capUnverifiedExpiry("2099-01-01T00:00:00Z", now)?.getTime(), now.getTime() + MAX_UNVERIFIED_TERM_MS);
  assertEquals(capUnverifiedExpiry(inDays(30).toISOString(), now)?.getTime(), inDays(30).getTime());
});

Deno.test("an already-expired entitlement never overwrites the plan", () => {
  const d = decideApply(
    { subscription_tier: "free", subscription_status: "expired", subscription_expires_at: null },
    { tier: "family", expiresAt: inDays(-1), originalTransactionId: "1" },
    now,
  );
  assertEquals(d, { apply: false, reason: "already_expired" });
});

Deno.test("a lesser plan from another subscription can't replace a running higher one", () => {
  const current = {
    subscription_tier: "family_plus",
    subscription_status: "active",
    subscription_expires_at: inDays(20).toISOString(),
    billing_original_transaction_id: "A",
  };
  assertEquals(decideApply(current, { tier: "caregiver", expiresAt: inDays(25), originalTransactionId: "B" }, now), {
    apply: false,
    reason: "higher_plan_active",
  });
  // The same subscription may go down (a downgrade at renewal).
  assertEquals(decideApply(current, { tier: "family", expiresAt: inDays(30), originalTransactionId: "A" }, now), { apply: true });
  // A higher plan from another subscription replaces it.
  assertEquals(decideApply(current, { tier: "family_plus", expiresAt: inDays(300), originalTransactionId: "B" }, now), { apply: true });
  // Once the higher plan has lapsed, the lesser one may take over.
  assertEquals(
    decideApply({ ...current, subscription_status: "expired", subscription_expires_at: inDays(-10).toISOString() }, {
      tier: "caregiver",
      expiresAt: inDays(25),
      originalTransactionId: "B",
    }, now),
    { apply: true },
  );
  // The owner buying a plan for a family someone else pays for (after an
  // ownership transfer) takes it over, even at a lower tier.
  assertEquals(
    decideApply(current, { tier: "caregiver", expiresAt: inDays(25), originalTransactionId: "B", ownerTakeover: true }, now),
    { apply: true },
  );
});

Deno.test("a family without a recorded subscription takes the first one (legacy rows)", () => {
  assertEquals(
    decideApply(
      { subscription_tier: "family", subscription_status: "active", subscription_expires_at: inDays(5).toISOString(), billing_original_transaction_id: null },
      { tier: "caregiver", expiresAt: inDays(30), originalTransactionId: "B" },
      now,
    ),
    { apply: true },
  );
});

Deno.test("notifications: renewals apply, failures and lapses wind down, the rest is ignored", () => {
  assertEquals(notificationAction("DID_RENEW"), "apply");
  assertEquals(notificationAction("SUBSCRIBED", "RESUBSCRIBE"), "apply");
  assertEquals(notificationAction("DID_FAIL_TO_RENEW", "GRACE_PERIOD"), "payment_issue");
  assertEquals(notificationAction("EXPIRED", "VOLUNTARY"), "lapse");
  assertEquals(notificationAction("GRACE_PERIOD_EXPIRED"), "lapse");
  assertEquals(notificationAction("REFUND"), "revoke");
  assertEquals(notificationAction("REVOKE"), "revoke");
  assertEquals(notificationAction("DID_CHANGE_RENEWAL_STATUS", "AUTO_RENEW_DISABLED"), "ignore");
  assertEquals(notificationAction("TEST"), "ignore");
});
