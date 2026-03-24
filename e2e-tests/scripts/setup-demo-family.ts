/**
 * Setup script: Creates a demo family with the owner and receiver demo accounts.
 * Run with: infisical run --env=prod -- npx tsx scripts/setup-demo-family.ts
 */
import { createClient } from "@supabase/supabase-js";
import { config } from "dotenv";
import { resolve, dirname } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));
config({ path: resolve(__dirname, "../.env") });
process.env.NODE_TLS_REJECT_UNAUTHORIZED = "0";

const SUPABASE_URL = process.env.SUPABASE_URL!;
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY!;

async function main() {
  // Sign in as owner
  console.log("Signing in as owner...");
  const ownerClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
  const { data: ownerAuth, error: ownerErr } =
    await ownerClient.auth.signInWithPassword({
      email: process.env.APPLE_OWNER_DEMO_EMAIL!,
      password: process.env.APPLE_OWNER_DEMO_PASS!,
    });
  if (ownerErr) throw new Error(`Owner sign-in failed: ${ownerErr.message}`);
  const ownerId = ownerAuth.user.id;
  console.log(`  Owner ID: ${ownerId}`);

  // Sign in as receiver
  console.log("Signing in as receiver...");
  const receiverClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
  const { data: receiverAuth, error: receiverErr } =
    await receiverClient.auth.signInWithPassword({
      email: process.env.APPLE_RECEIVER_DEMO_EMAIL!,
      password: process.env.APPLE_RECEIVER_DEMO_PASS!,
    });
  if (receiverErr)
    throw new Error(`Receiver sign-in failed: ${receiverErr.message}`);
  const receiverId = receiverAuth.user.id;
  console.log(`  Receiver ID: ${receiverId}`);

  // Check if owner already has a family
  console.log("Checking for existing family...");
  const { data: existingMembers } = await ownerClient
    .from("family_members")
    .select("*, families(*)")
    .eq("user_id", ownerId)
    .eq("role", "owner");

  if (existingMembers && existingMembers.length > 0) {
    const familyId = existingMembers[0].family_id;
    console.log(`  Owner already has a family: ${familyId}`);

    // Check if receiver is already in this family
    const { data: receiverMember } = await ownerClient
      .from("family_members")
      .select("*")
      .eq("family_id", familyId)
      .eq("user_id", receiverId);

    if (receiverMember && receiverMember.length > 0) {
      console.log("  Receiver already in the family. Nothing to do!");
      return;
    }

    // Add receiver to existing family
    console.log("  Adding receiver to existing family...");
    const { data: newMember, error: memberErr } = await ownerClient
      .from("family_members")
      .insert({
        family_id: familyId,
        user_id: receiverId,
        role: "receiver",
        status: "active",
        joined_at: new Date().toISOString(),
      })
      .select()
      .single();

    if (memberErr)
      throw new Error(`Failed to add receiver: ${memberErr.message}`);

    // Create receiver settings
    const { error: settingsErr } = await ownerClient
      .from("receiver_settings")
      .insert({
        family_member_id: newMember.id,
        checkin_time: "08:00",
        timezone: "America/Chicago",
        grace_period_minutes: 30,
        reminder_interval_minutes: 30,
        escalation_enabled: true,
        is_active: true,
      });

    if (settingsErr)
      console.warn(
        `  Warning: receiver_settings insert failed (may already exist): ${settingsErr.message}`
      );

    console.log("  Done! Receiver added to family.");
    return;
  }

  // Create new family
  console.log("Creating new family...");
  const { data: family, error: familyErr } = await ownerClient
    .from("families")
    .insert({
      name: "Demo Family",
      owner_id: ownerId,
      subscription_tier: "free",
      subscription_status: "active",
      max_receivers: 1,
      max_viewers: 0,
    })
    .select()
    .single();

  if (familyErr) throw new Error(`Failed to create family: ${familyErr.message}`);
  console.log(`  Family created: ${family.id}`);

  // Add owner as family member
  console.log("Adding owner as family member...");
  const { error: ownerMemberErr } = await ownerClient
    .from("family_members")
    .insert({
      family_id: family.id,
      user_id: ownerId,
      role: "owner",
      status: "active",
      joined_at: new Date().toISOString(),
    });

  if (ownerMemberErr)
    throw new Error(`Failed to add owner member: ${ownerMemberErr.message}`);

  // Add receiver as family member
  console.log("Adding receiver as family member...");
  const { data: receiverMember, error: receiverMemberErr } = await ownerClient
    .from("family_members")
    .insert({
      family_id: family.id,
      user_id: receiverId,
      role: "receiver",
      status: "active",
      joined_at: new Date().toISOString(),
    })
    .select()
    .single();

  if (receiverMemberErr)
    throw new Error(
      `Failed to add receiver member: ${receiverMemberErr.message}`
    );

  // Create receiver settings
  console.log("Creating receiver settings...");
  const { error: settingsErr } = await ownerClient
    .from("receiver_settings")
    .insert({
      family_member_id: receiverMember.id,
      checkin_time: "08:00",
      timezone: "America/Chicago",
      grace_period_minutes: 30,
      reminder_interval_minutes: 30,
      escalation_enabled: true,
      is_active: true,
    });

  if (settingsErr)
    console.warn(
      `  Warning: receiver_settings failed: ${settingsErr.message}`
    );

  console.log("\nSetup complete!");
  console.log(`  Family: ${family.id} ("Demo Family")`);
  console.log(`  Owner: ${ownerId} (${process.env.APPLE_OWNER_DEMO_EMAIL})`);
  console.log(
    `  Receiver: ${receiverId} (${process.env.APPLE_RECEIVER_DEMO_EMAIL})`
  );
}

main().catch((err) => {
  console.error("Setup failed:", err.message);
  process.exit(1);
});
