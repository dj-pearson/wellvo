/**
 * Database side of subscriptions, shared by /subscription-webhook (the apps)
 * and /app-store-notifications (Apple).
 *
 * Billing after an ownership transfer (decision, 2026-09-27):
 *   The family stays covered by whoever pays for it. `families.billing_user_id`
 *   (00059) records the payer. When the owner hands the family to a
 *   co-caregiver, the ex-owner stays in the family as a viewer and their
 *   subscription keeps renewing it until they cancel. The new owner can buy
 *   their own plan at any time; theirs then becomes the family's plan.
 *   A payer who has left the family no longer covers it.
 *
 * Every function tolerates the 00059 columns not existing yet (the edge
 * functions can deploy before the migration runs): it falls back to the
 * previous owner-only behaviour instead of failing purchases.
 */
import { supabaseAdmin } from "./supabase.ts";
import { logInfo, logWarn } from "./logger.ts";
import {
  type AppStoreTransaction,
  AppStoreJWSError,
  verifyAppStoreJWS,
} from "./app-store-jws.ts";
import { APPLE_BUNDLE_ID, lookUpTransaction } from "./app-store-server-api.ts";
import { decideApply, pickBilledFamily, type TierInfo } from "./subscription-policy.ts";
import type { PlayVerdict } from "./google-play.ts";

export interface BillingFamily {
  id: string;
  owner_id: string;
  subscription_tier: string;
  subscription_status: string;
  subscription_expires_at: string | null;
  billing_user_id?: string | null;
  billing_original_transaction_id?: string | null;
}

const BASE_COLUMNS = "id, owner_id, subscription_tier, subscription_status, subscription_expires_at, created_at";
const BILLING_COLUMNS = `${BASE_COLUMNS}, billing_user_id, billing_original_transaction_id`;

// deno-lint-ignore no-explicit-any
function isMissingColumn(error: any): boolean {
  const code = error?.code ?? "";
  return code === "42703" || code === "PGRST204" || /column .* does not exist/i.test(error?.message ?? "");
}

async function isActiveMember(familyId: string, userId: string): Promise<boolean> {
  const { data } = await supabaseAdmin
    .from("family_members")
    .select("id")
    .eq("family_id", familyId)
    .eq("user_id", userId)
    .eq("status", "active")
    .limit(1);
  return (data?.length ?? 0) > 0;
}

/**
 * The family a user's subscription pays for:
 *   1. a family they are recorded as paying for and still belong to;
 *   2. otherwise the family they own (earliest, matching the apps — the old
 *      `.single()` 404'd every purchase when stray duplicates existed).
 */
export async function findBillingFamily(userId: string): Promise<BillingFamily | null> {
  const billed = await supabaseAdmin
    .from("families")
    .select(BILLING_COLUMNS)
    .eq("billing_user_id", userId)
    .order("created_at", { ascending: true })
    .limit(5);

  if (!billed.error) {
    for (const f of (billed.data ?? []) as BillingFamily[]) {
      if (f.owner_id === userId || await isActiveMember(f.id, userId)) return f;
    }
  } else if (!isMissingColumn(billed.error)) {
    throw billed.error;
  }

  const owned = await supabaseAdmin
    .from("families")
    .select(billed.error ? BASE_COLUMNS : BILLING_COLUMNS)
    .eq("owner_id", userId)
    .order("created_at", { ascending: true })
    .limit(1);
  if (owned.error) throw owned.error;
  return ((owned.data ?? [])[0] as BillingFamily | undefined) ?? null;
}

/**
 * Family currently billed to this App Store subscription, if any.
 *
 * More than one family can carry the same id (an unverified legacy request
 * could store any id it was given). Prefer, in order: a family billed to the
 * account the verified receipt is bound to, then one whose billing was
 * verified, then the oldest. It used to be "oldest" alone, which a family
 * owner could win by claiming someone else's id on a family they own.
 */
export async function findFamilyByOriginalTransaction(
  originalTransactionId: string,
  payerUserId?: string | null,
): Promise<BillingFamily | null> {
  const { data, error } = await supabaseAdmin
    .from("families")
    .select(`${BILLING_COLUMNS}, billing_verified_at`)
    .eq("billing_original_transaction_id", originalTransactionId)
    .order("created_at", { ascending: true })
    .limit(10);
  if (error) return null;
  const rows = (data ?? []) as (BillingFamily & { billing_verified_at?: string | null })[];
  return pickBilledFamily(rows, payerUserId ?? null);
}

/**
 * Whether an UNVERIFIED client may record this App Store subscription id on
 * its own family: not when a verified receipt binds it to another account,
 * and not when another account's family is already billed to it.
 */
export async function unverifiedOriginalIdIsSafe(originalTransactionId: string, userId: string): Promise<boolean> {
  const owner = await receiptOwner(originalTransactionId);
  if (owner && owner !== userId) return false;
  const { data, error } = await supabaseAdmin
    .from("families")
    .select("id, billing_user_id")
    .eq("billing_original_transaction_id", originalTransactionId)
    .limit(10);
  // Before 00059 there is no such column: nothing to collide with.
  if (error) return isMissingColumn(error);
  return !(data ?? []).some((f: { billing_user_id: string | null }) => f.billing_user_id !== userId);
}

/** Account a verified App Store subscription is bound to, if recorded. */
export async function receiptOwner(originalTransactionId: string): Promise<string | null> {
  const { data, error } = await supabaseAdmin
    .from("subscription_receipts")
    .select("user_id")
    .eq("original_transaction_id", originalTransactionId)
    .limit(1);
  if (error) return null;
  return (data?.[0]?.user_id as string | undefined) ?? null;
}

export type BindResult = "ok" | "bound_to_other_user";

/**
 * Bind a VERIFIED App Store subscription to one Daily OK account. The first
 * account to present it keeps it, so one purchase can't provision any number
 * of accounts. A binding to an account that has since been deleted is gone
 * (ON DELETE CASCADE), so the payer can reuse the plan after re-registering.
 */
export async function bindReceipt(args: {
  tx: AppStoreTransaction;
  userId: string;
  familyId: string | null;
}): Promise<BindResult> {
  const { tx, userId, familyId } = args;
  const existing = await receiptOwner(tx.originalTransactionId);
  if (existing && existing !== userId) return "bound_to_other_user";

  const { error } = await supabaseAdmin.from("subscription_receipts").upsert({
    original_transaction_id: tx.originalTransactionId,
    platform: "ios",
    user_id: userId,
    family_id: familyId,
    product_id: tx.productId,
    expires_at: tx.expiresDate ? new Date(tx.expiresDate).toISOString() : null,
    revoked_at: tx.revocationDate ? new Date(tx.revocationDate).toISOString() : null,
    environment: tx.environment ?? null,
    last_transaction_id: tx.transactionId,
    updated_at: new Date().toISOString(),
  }, { onConflict: "original_transaction_id" });
  if (error && !isMissingColumn(error) && error.code !== "42P01") {
    logWarn("subscription_receipts upsert failed", { code: error.code });
  }
  return "ok";
}

/**
 * Bind a VERIFIED Google Play subscription (keyed by playSubscriptionKey, a
 * hash of the purchase token) to one Daily OK account, like bindReceipt.
 * A plan change (new token linked to the old) keeps the old binding's owner.
 */
export async function bindPlayReceipt(args: {
  key: string;
  linkedKey?: string | null;
  userId: string;
  familyId: string | null;
  verdict: PlayVerdict;
}): Promise<BindResult> {
  const { key, userId, familyId, verdict } = args;
  const existing = await receiptOwner(key) ?? (args.linkedKey ? await receiptOwner(args.linkedKey) : null);
  if (existing && existing !== userId) return "bound_to_other_user";

  const { error } = await supabaseAdmin.from("subscription_receipts").upsert({
    original_transaction_id: key,
    platform: "android",
    user_id: userId,
    family_id: familyId,
    product_id: verdict.productId,
    expires_at: verdict.expiresAt ? verdict.expiresAt.toISOString() : null,
    revoked_at: null,
    environment: verdict.isTest ? "Sandbox" : "Production",
    last_transaction_id: verdict.orderId,
    updated_at: new Date().toISOString(),
  }, { onConflict: "original_transaction_id" });
  if (error && !isMissingColumn(error) && error.code !== "42P01") {
    logWarn("subscription_receipts upsert failed", { code: error.code });
  }
  return "ok";
}

export type AppleClaim =
  | { kind: "verified"; tx: AppStoreTransaction }
  | { kind: "invalid"; reason: string }
  | { kind: "unavailable"; reason: string }
  | { kind: "unsigned" };

/**
 * Establish what Apple actually sold, from the most trustworthy source present:
 *   1. `signed_transaction` (jwsRepresentation, sent by builds from this one on);
 *   2. an App Store Server API lookup of `transaction_id` (shipped builds);
 *   3. nothing — "unsigned".
 */
export async function verifyAppleClaim(body: { signed_transaction?: string; transaction_id?: string }): Promise<AppleClaim> {
  let jws: string | null = null;
  if (typeof body.signed_transaction === "string" && body.signed_transaction.length > 0) {
    jws = body.signed_transaction;
  } else if (typeof body.transaction_id === "string" && body.transaction_id.length > 0) {
    const lookup = await lookUpTransaction(body.transaction_id);
    if (lookup.status === "ok") jws = lookup.signedTransactionInfo;
    else if (lookup.status === "not_found") return { kind: "invalid", reason: "transaction_not_found" };
    else if (lookup.reason === "not_configured") return { kind: "unsigned" };
    else return { kind: "unavailable", reason: lookup.reason };
  } else {
    return { kind: "unsigned" };
  }

  try {
    const tx = await verifyAppStoreJWS<AppStoreTransaction>(jws);
    if (tx.bundleId !== APPLE_BUNDLE_ID) return { kind: "invalid", reason: "bundle_mismatch" };
    if (!tx.productId || !tx.originalTransactionId) return { kind: "invalid", reason: "incomplete_transaction" };
    return { kind: "verified", tx };
  } catch (err) {
    return { kind: "invalid", reason: err instanceof AppStoreJWSError ? err.message : "verification_error" };
  }
}

/**
 * Write a plan to a family, unless decideApply says it would wrongly lower or
 * resurrect it. Returns whether it was applied.
 */
export async function applyEntitlement(args: {
  family: BillingFamily;
  tierInfo: TierInfo;
  expiresAt: Date | null;
  originalTransactionId: string | null;
  payerUserId: string;
  platform: "ios" | "android";
  verified: boolean;
  now?: Date;
  /** Google Play: the subscription this purchase replaces (see decideApply). */
  replacesTransactionId?: string | null;
}): Promise<{ applied: true } | { applied: false; reason: string }> {
  const now = args.now ?? new Date();
  const ownerTakeover = args.payerUserId === args.family.owner_id &&
    !!args.family.billing_user_id && args.family.billing_user_id !== args.payerUserId;
  const decision = decideApply(args.family, {
    tier: args.tierInfo.tier,
    expiresAt: args.expiresAt,
    originalTransactionId: args.originalTransactionId,
    ownerTakeover,
    replacesTransactionId: args.replacesTransactionId ?? null,
  }, now);
  if (!decision.apply) {
    logInfo("Subscription update not applied", { familyId: args.family.id, reason: decision.reason });
    return { applied: false, reason: decision.reason };
  }

  const base = {
    subscription_tier: args.tierInfo.tier,
    subscription_status: "active",
    subscription_expires_at: args.expiresAt ? args.expiresAt.toISOString() : null,
    max_receivers: args.tierInfo.maxReceivers,
    max_viewers: args.tierInfo.maxViewers,
  };
  const withBilling = {
    ...base,
    billing_user_id: args.payerUserId,
    billing_platform: args.platform,
    billing_verified_at: args.verified ? now.toISOString() : null,
    // Keep the known subscription id when an unverified legacy request has none.
    ...(args.originalTransactionId ? { billing_original_transaction_id: args.originalTransactionId } : {}),
  };

  let { error } = await supabaseAdmin.from("families").update(withBilling).eq("id", args.family.id);
  if (error && isMissingColumn(error)) {
    ({ error } = await supabaseAdmin.from("families").update(base).eq("id", args.family.id));
  }
  if (error) throw error;

  await resumeBillingPausedSchedules(args.family.id);
  return { applied: true };
}

/**
 * Turn back on the schedules the expiry job switched off (00059). Before this,
 * resubscribing after a lapse restored the plan but never the check-ins.
 */
export async function resumeBillingPausedSchedules(familyId: string): Promise<void> {
  const { data, error } = await supabaseAdmin.rpc("resume_billing_paused_schedules", { p_family_id: familyId });
  if (error) {
    logWarn("resume_billing_paused_schedules failed", { familyId, code: error.code });
  } else if (typeof data === "number" && data > 0) {
    logInfo("Resumed check-in schedules after resubscribe", { familyId, count: data });
  }
}

/**
 * Start the seven-day wind-down the nightly job already uses for a missed
 * renewal, instead of stopping check-ins at once.
 */
export async function startGracePeriod(family: BillingFamily, endedAt: Date): Promise<void> {
  if (family.subscription_status === "expired") return;
  const currentExpiry = family.subscription_expires_at ? Date.parse(family.subscription_expires_at) : NaN;
  const expiresAt = Number.isNaN(currentExpiry) ? endedAt : new Date(Math.min(currentExpiry, endedAt.getTime()));
  const { error } = await supabaseAdmin
    .from("families")
    .update({ subscription_status: "grace_period", subscription_expires_at: expiresAt.toISOString() })
    .eq("id", family.id);
  if (error) throw error;
}
