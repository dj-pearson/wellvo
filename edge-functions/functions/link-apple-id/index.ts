import { supabaseAdmin } from "../../shared/supabase.ts";
import type { AuthResult } from "../../shared/auth.ts";
import { jwtVerify, createRemoteJWKSet } from "jose";

interface LinkAppleIdRequest {
  identity_token: string;
  nonce: string;
}

const APPLE_ISSUER = "https://appleid.apple.com";
const APPLE_JWKS_URI = "https://appleid.apple.com/auth/keys";
const APP_BUNDLE_ID = Deno.env.get("APPLE_BUNDLE_ID") || "com.wellvo.ios";

// jose handles key rotation and caching internally
const appleJWKS = createRemoteJWKSet(new URL(APPLE_JWKS_URI));

/**
 * Links an Apple identity to the currently authenticated user.
 *
 * Users who signed up with email or phone can link their Apple ID so that
 * "Sign in with Apple" lands on the same account — even though Apple's
 * private-relay email won't match the original account email.
 */
export async function handleLinkAppleId(
  req: Request,
  auth: AuthResult
): Promise<Response> {
  const headers = { "Content-Type": "application/json" };

  if (!auth.userId) {
    return new Response(
      JSON.stringify({ error: "Authentication required" }),
      { status: 401, headers }
    );
  }

  // Parse request
  let body: LinkAppleIdRequest;
  try {
    body = await req.json();
  } catch {
    return new Response(
      JSON.stringify({ error: "Invalid request body" }),
      { status: 400, headers }
    );
  }

  const { identity_token, nonce } = body;
  if (!identity_token || !nonce) {
    return new Response(
      JSON.stringify({ error: "identity_token and nonce are required" }),
      { status: 400, headers }
    );
  }

  // Verify the Apple identity token (signature, issuer, audience, expiry)
  let appleSub: string;
  let appleEmail: string | undefined;
  try {
    const { payload } = await jwtVerify(identity_token, appleJWKS, {
      issuer: APPLE_ISSUER,
      audience: APP_BUNDLE_ID,
    });

    // Apple includes the SHA256-hashed nonce in the token; the client sends
    // the same hash so we can compare directly.
    if (!payload.nonce || payload.nonce !== nonce) {
      return new Response(
        JSON.stringify({ error: "Nonce mismatch" }),
        { status: 400, headers }
      );
    }

    appleSub = payload.sub as string;
    appleEmail = payload.email as string | undefined;

    if (!appleSub) {
      return new Response(
        JSON.stringify({ error: "Invalid Apple token: missing subject" }),
        { status: 400, headers }
      );
    }
  } catch (err) {
    // Log detailed error server-side, return generic message to client
    console.error("Apple token verification failed:", err instanceof Error ? err.message : err);
    return new Response(
      JSON.stringify({ error: "Invalid identity token" }),
      { status: 401, headers }
    );
  }

  // Link the identity via the database function (handles duplicate checks,
  // inserts into auth.identities, and updates app_metadata).
  const identityData = {
    sub: appleSub,
    email: appleEmail,
    email_verified: true,
    iss: APPLE_ISSUER,
    provider_id: appleSub,
  };

  const { error: linkError } = await supabaseAdmin.rpc("link_apple_identity", {
    p_user_id: auth.userId,
    p_provider_id: appleSub,
    p_identity_data: identityData,
  });

  if (linkError) {
    // The RPC raises specific exceptions for known cases
    if (linkError.message?.includes("already linked")) {
      return new Response(
        JSON.stringify({ error: "This Apple ID is already linked to an account" }),
        { status: 409, headers }
      );
    }
    console.error("[link-apple-id] RPC error:", linkError.message);
    return new Response(
      JSON.stringify({ error: "Failed to link Apple ID" }),
      { status: 500, headers }
    );
  }

  return new Response(
    JSON.stringify({
      success: true,
      message: "Apple ID linked successfully",
      apple_email: appleEmail,
    }),
    { headers }
  );
}
