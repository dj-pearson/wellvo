import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { env } from "./env";

export interface AuthenticatedUser {
  client: SupabaseClient;
  userId: string;
  accessToken: string;
  email: string;
}

async function signIn(
  email: string,
  password: string
): Promise<AuthenticatedUser> {
  console.log(`[auth] Signing in ${email} via ${env.supabaseUrl}`);
  const client = createClient(env.supabaseUrl, env.supabaseAnonKey);

  const { data, error } = await client.auth.signInWithPassword({
    email,
    password,
  });

  if (error) throw new Error(`Auth failed for ${email}: ${error.message}`);
  if (!data.session) throw new Error(`No session returned for ${email}`);

  return {
    client,
    userId: data.user.id,
    accessToken: data.session.access_token,
    email,
  };
}

export async function signInOwner(): Promise<AuthenticatedUser> {
  return signIn(env.ownerEmail, env.ownerPassword);
}

export async function signInReceiver(): Promise<AuthenticatedUser> {
  return signIn(env.receiverEmail, env.receiverPassword);
}
