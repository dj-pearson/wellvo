/**
 * Who may act on a receiver's escalation: stop the alerts (cancel-escalation)
 * or send "Check on now" (on-demand-checkin).
 *
 * The family owner and the family's ACTIVE co-caregivers ('viewer' members)
 * may. Receivers, removed or invited members and people from other families may
 * not. Invites, billing, receiver settings, removing members and transfer stay
 * owner-only and do not use this.
 *
 * The decision is pure (caregiverActorRole, unit-tested in
 * caregiver-access_test.ts); resolveCaregiverActor does the lookups.
 */
import { supabaseAdmin } from "./supabase.ts";

export type CaregiverActorRole = "owner" | "viewer";

/**
 * `membership` is the caller's family_members row in THIS family (or null).
 * Only an active 'viewer' row counts; the owner is recognised by owner_id.
 */
export function caregiverActorRole(
  ownerId: string,
  userId: string | null | undefined,
  membership: { role: string; status: string } | null | undefined,
): CaregiverActorRole | null {
  if (!userId) return null;
  if (ownerId.toLowerCase() === userId.toLowerCase()) return "owner";
  if (membership && membership.role === "viewer" && membership.status === "active") return "viewer";
  return null;
}

/**
 * The caller's role for this family, or null when they may not act on its
 * escalations. `ownerId` is the family's owner_id (already loaded by callers).
 */
export async function resolveCaregiverActor(
  familyId: string,
  ownerId: string,
  userId: string | null | undefined,
): Promise<CaregiverActorRole | null> {
  if (!userId) return null;
  if (caregiverActorRole(ownerId, userId, null) === "owner") return "owner";
  const { data: rows } = await supabaseAdmin
    .from("family_members")
    .select("role, status")
    .eq("family_id", familyId)
    .eq("user_id", userId)
    .eq("role", "viewer")
    .eq("status", "active")
    .limit(1);
  return caregiverActorRole(ownerId, userId, rows?.[0] ?? null);
}
