/**
 * Platform-aware notification dispatcher.
 * Routes push tokens to APNs (iOS) or FCM (Android) based on platform field.
 */

import { supabaseAdmin } from "./supabase.ts";
import { sendPushNotification } from "./apns.ts";
import type { sendPushNotification as APNsResult } from "./apns.ts";
import { sendFCMNotification } from "./fcm.ts";

interface PushToken {
  token: string;
  platform: string;
}

interface APNsPayload {
  aps: {
    alert: { title: string; body: string };
    sound?: string;
    badge?: number;
    category?: string;
    "thread-id"?: string;
    "interruption-level"?: string;
    "relevance-score"?: number;
  };
  [key: string]: unknown;
}

interface FCMPayload {
  title: string;
  body: string;
  data?: Record<string, string>;
}

interface NotificationResult {
  success: boolean;
  statusCode: number;
  reason?: string;
}

/**
 * Send notifications to all active tokens for a user, routing by platform.
 * Deactivates invalid/expired tokens automatically.
 */
export async function sendNotificationToUser(
  userId: string,
  apnsPayload: APNsPayload,
  fcmPayload: FCMPayload,
  apnsOptions?: { collapseId?: string; priority?: number }
): Promise<{ sent: number; failed: number; results: NotificationResult[] }> {
  const { data: tokens, error } = await supabaseAdmin
    .from("push_tokens")
    .select("token, platform")
    .eq("user_id", userId)
    .eq("is_active", true);

  if (error || !tokens?.length) {
    return { sent: 0, failed: 0, results: [] };
  }

  const results = await Promise.all(
    tokens.map((t: PushToken) => {
      if (t.platform === "android") {
        return sendFCMNotification(t.token, fcmPayload);
      } else {
        return sendPushNotification(t.token, apnsPayload, apnsOptions);
      }
    })
  );

  // Deactivate invalid tokens
  for (let i = 0; i < results.length; i++) {
    const isInvalid =
      results[i].statusCode === 410 ||
      results[i].reason === "NOT_FOUND" ||
      results[i].reason === "UNREGISTERED";

    if (isInvalid) {
      await supabaseAdmin
        .from("push_tokens")
        .update({ is_active: false })
        .eq("token", tokens[i].token);

      console.log(`Deactivated invalid ${tokens[i].platform} token for user ${userId}`);
    }
  }

  const sent = results.filter((r) => r.success).length;
  return { sent, failed: results.length - sent, results };
}
