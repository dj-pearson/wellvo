import type { AuthenticatedUser } from "./auth";

/**
 * Query helpers that use authenticated Supabase clients
 * to verify database state after API calls.
 */

export async function getUserProfile(user: AuthenticatedUser) {
  const { data, error } = await user.client
    .from("users")
    .select("*")
    .eq("id", user.userId)
    .single();

  if (error) throw new Error(`Failed to get user profile: ${error.message}`);
  return data;
}

export async function getFamiliesForUser(user: AuthenticatedUser) {
  const { data, error } = await user.client
    .from("family_members")
    .select("*, families(*)")
    .eq("user_id", user.userId);

  if (error) throw new Error(`Failed to get families: ${error.message}`);
  return data;
}

export async function getCheckInRequests(
  user: AuthenticatedUser,
  familyId: string
) {
  const { data, error } = await user.client
    .from("checkin_requests")
    .select("*")
    .eq("family_id", familyId)
    .order("created_at", { ascending: false })
    .limit(10);

  if (error)
    throw new Error(`Failed to get check-in requests: ${error.message}`);
  return data;
}

export async function getCheckIns(
  user: AuthenticatedUser,
  familyId: string,
  receiverId?: string
) {
  let query = user.client
    .from("checkins")
    .select("*")
    .eq("family_id", familyId)
    .order("checked_in_at", { ascending: false })
    .limit(10);

  if (receiverId) {
    query = query.eq("receiver_id", receiverId);
  }

  const { data, error } = await query;
  if (error) throw new Error(`Failed to get check-ins: ${error.message}`);
  return data;
}

export async function getReceiverSettings(
  user: AuthenticatedUser,
  receiverId: string,
  familyId: string
) {
  const { data, error } = await user.client
    .from("receiver_settings")
    .select("*")
    .eq("receiver_id", receiverId)
    .eq("family_id", familyId)
    .single();

  if (error)
    throw new Error(`Failed to get receiver settings: ${error.message}`);
  return data;
}

export async function getAlerts(user: AuthenticatedUser, familyId: string) {
  const { data, error } = await user.client
    .from("alerts")
    .select("*")
    .eq("family_id", familyId)
    .order("created_at", { ascending: false })
    .limit(10);

  if (error) throw new Error(`Failed to get alerts: ${error.message}`);
  return data;
}
