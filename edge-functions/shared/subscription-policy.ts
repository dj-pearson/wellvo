/**
 * Subscription rules with no I/O, so they can be unit-tested (US-EDGE005).
 *
 * Used by /subscription-webhook (the apps) and /app-store-notifications
 * (Apple, server to server).
 */

export interface TierInfo {
  tier: "caregiver" | "family" | "family_plus";
  maxReceivers: number;
  maxViewers: number;
}

// Product ID → tier + seat limits.
//
// Two product-ID namespaces are recognized:
//   - `net.wellvo.*`  — the iOS App Store Connect source of truth (bundle id
//     com.wellvo.ios). iOS `SubscriptionService.ProductIDs` sends these.
//   - `net.dailyok.*` — the original namespace still registered for Android
//     Google Play (`SubscriptionService.PRODUCT_IDS`) and any historical/
//     sandbox iOS purchase.
//
// Per CLAUDE.md §E we never stop recognizing a product ID a subscriber may
// still hold, so BOTH namespaces map to the same tiers.
// FOLLOW-UP: unify on a single namespace once Google Play products are
// re-registered under net.wellvo.* (requires Play Console work).
const CAREGIVER: TierInfo = { tier: "caregiver", maxReceivers: 1, maxViewers: 3 };
const FAMILY: TierInfo = { tier: "family", maxReceivers: 3, maxViewers: 5 };
const FAMILY_PLUS: TierInfo = { tier: "family_plus", maxReceivers: 6, maxViewers: 10 };

export const TIER_MAP: Record<string, TierInfo> = {
  // iOS / App Store Connect (source of truth)
  "net.wellvo.caregiver.monthly": CAREGIVER,
  "net.wellvo.caregiver.yearly": CAREGIVER,
  "net.wellvo.family.monthly": FAMILY,
  "net.wellvo.family.yearly": FAMILY,
  "net.wellvo.familyplus.monthly": FAMILY_PLUS,
  "net.wellvo.familyplus.yearly": FAMILY_PLUS,
  // Android / Google Play + historical iOS sandbox
  "net.dailyok.caregiver.monthly": CAREGIVER,
  "net.dailyok.caregiver.yearly": CAREGIVER,
  "net.dailyok.family.monthly": FAMILY,
  "net.dailyok.family.yearly": FAMILY,
  "net.dailyok.familyplus.monthly": FAMILY_PLUS,
  "net.dailyok.familyplus.yearly": FAMILY_PLUS,
};

// Add-on product IDs, both namespaces.
export const ADDON_IDS = new Set([
  "net.wellvo.addon.receiver",
  "net.dailyok.addon.receiver",
  "net.wellvo.addon.viewer",
  "net.dailyok.addon.viewer",
]);

export function tierForProduct(productId: string | undefined | null): TierInfo | null {
  if (!productId) return null;
  return TIER_MAP[productId] ?? null;
}

export function tierRank(tier: string | null | undefined): number {
  switch (tier) {
    case "caregiver": return 1;
    case "family": return 2;
    case "family_plus": return 3;
    default: return 0; // free / unknown
  }
}

/** Longest a real subscription period runs (a year) plus slack. */
export const MAX_UNVERIFIED_TERM_MS = 370 * 24 * 60 * 60 * 1000;

/**
 * Expiry claimed by a client whose transaction could not be verified.
 * Unparseable → null. Anything further out than a real yearly term is cut back
 * to one, so a forged "2099-01-01" buys at most a year (a forged request can
 * still be replayed; full protection is SUBSCRIPTION_VERIFY_MODE=enforce).
 */
export function capUnverifiedExpiry(raw: string | undefined | null, now: Date): Date | null {
  if (!raw || typeof raw !== "string") return null;
  const t = Date.parse(raw);
  if (Number.isNaN(t)) return null;
  return new Date(Math.min(t, now.getTime() + MAX_UNVERIFIED_TERM_MS));
}

export interface FamilyBillingState {
  subscription_tier: string;
  subscription_status: string;
  subscription_expires_at: string | null;
  billing_original_transaction_id?: string | null;
}

export interface IncomingEntitlement {
  tier: string;
  expiresAt: Date | null;
  originalTransactionId: string | null;
  /**
   * The family's owner is buying a plan for a family someone else pays for
   * (e.g. the ex-owner after an ownership transfer). That is the documented
   * way to take the plan over, so it replaces the running plan even when it
   * is a lower tier — otherwise the owner is charged and nothing changes.
   */
  ownerTakeover?: boolean;
}

export type ApplyDecision = { apply: true } | { apply: false; reason: "already_expired" | "higher_plan_active" };

/**
 * Whether an entitlement may overwrite the family's plan.
 *
 * The webhook used to be last-write-wins. Lowering max_receivers fires the
 * 00005 downgrade trigger, which deactivates the newest receivers — so a stale
 * or lesser transaction (a second Apple ID's old Caregiver plan, an Android
 * purchase next to an iOS one, a late redelivery) silently removed people from
 * daily check-ins. Now:
 *   - an entitlement that has already expired never overwrites anything;
 *   - a lower tier from a DIFFERENT subscription (original transaction) never
 *     replaces a higher plan that is still running. The same subscription may
 *     go down (a real downgrade at renewal keeps its original transaction id).
 */
export function decideApply(current: FamilyBillingState, incoming: IncomingEntitlement, now: Date): ApplyDecision {
  if (incoming.expiresAt && incoming.expiresAt.getTime() <= now.getTime()) {
    return { apply: false, reason: "already_expired" };
  }
  const currentExpiry = current.subscription_expires_at ? Date.parse(current.subscription_expires_at) : NaN;
  const currentRunning = (current.subscription_status === "active" || current.subscription_status === "grace_period") &&
    (Number.isNaN(currentExpiry) ? current.subscription_tier !== "free" : currentExpiry > now.getTime());
  const differentSubscription = !!current.billing_original_transaction_id &&
    !!incoming.originalTransactionId &&
    current.billing_original_transaction_id !== incoming.originalTransactionId;
  if (
    !incoming.ownerTakeover && currentRunning && differentSubscription &&
    tierRank(incoming.tier) < tierRank(current.subscription_tier)
  ) {
    return { apply: false, reason: "higher_plan_active" };
  }
  return { apply: true };
}

export type NotificationAction = "apply" | "payment_issue" | "lapse" | "revoke" | "ignore";

/**
 * What an App Store Server Notification v2 means for the family.
 * Nothing here stops check-ins at once: a lapse or refund moves the family to
 * grace_period, and the nightly job (00005/00059) ends it seven days later, the
 * same path a missed renewal already takes.
 */
export function notificationAction(type: string, _subtype?: string): NotificationAction {
  switch (type) {
    case "SUBSCRIBED":
    case "DID_RENEW":
    case "OFFER_REDEEMED":
    case "RENEWAL_EXTENDED":
    case "REFUND_REVERSED":
    case "DID_CHANGE_RENEWAL_PREF":
      return "apply";
    case "DID_FAIL_TO_RENEW":
      return "payment_issue";
    case "EXPIRED":
    case "GRACE_PERIOD_EXPIRED":
      return "lapse";
    case "REFUND":
    case "REVOKE":
      return "revoke";
    default:
      // DID_CHANGE_RENEWAL_STATUS, PRICE_INCREASE, CONSUMPTION_REQUEST, TEST,
      // RENEWAL_EXTENSION, … change nothing about coverage today.
      return "ignore";
  }
}

export const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
