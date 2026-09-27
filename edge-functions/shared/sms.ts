/**
 * SMS client using Twilio API — DISABLED BY DEFAULT.
 *
 * Daily OK no longer sends text messages from a server. Server-sent SMS needs
 * an A2P 10DLC registration the product can't meet, so a text between family
 * members is now written on the phone itself: the apps open the Messages
 * composer pre-filled ("Text Mom") and the person sends it from their own
 * number. Escalation still pages owners and co-caregivers by push (APNs/FCM).
 *
 * The code is kept so the paths still compile and a future, compliant sender
 * could be switched back on deliberately. Nothing is sent unless the
 * deployment sets SMS_ENABLED=true (and Twilio credentials) explicitly.
 */

/**
 * Whether the server may send SMS. Only an explicit "true" / "1" turns it on;
 * unset, empty or anything else is off.
 */
export function parseSmsEnabled(raw: string | undefined | null): boolean {
  const v = (raw ?? "").trim().toLowerCase();
  return v === "true" || v === "1";
}

/**
 * Env read that tolerates a missing --allow-env: CI's `deno test` runs with no
 * permissions, and sms_test imports this module. The server always has
 * --allow-env, so production reads are unchanged. Unreadable reads as unset,
 * which keeps SMS off.
 */
function readEnv(name: string): string | undefined {
  try {
    return Deno.env.get(name);
  } catch {
    return undefined;
  }
}

export const SMS_ENABLED = parseSmsEnabled(readEnv("SMS_ENABLED"));

const TWILIO_ACCOUNT_SID = readEnv("TWILIO_ACCOUNT_SID") || "";
const TWILIO_AUTH_TOKEN = readEnv("TWILIO_AUTH_TOKEN") || "";
const TWILIO_FROM_NUMBER = readEnv("TWILIO_FROM_NUMBER") || "";
// Preferred sender for A2P 10DLC: routes through the approved campaign's sender pool.
// When set, takes precedence over TWILIO_FROM_NUMBER.
const TWILIO_MESSAGING_SERVICE_SID = readEnv("TWILIO_MESSAGING_SERVICE_SID") || "";

const hasSender = !!(TWILIO_MESSAGING_SERVICE_SID || TWILIO_FROM_NUMBER);

// Only worth a warning when someone switched SMS on and it still can't send.
if (SMS_ENABLED && (!TWILIO_ACCOUNT_SID || !TWILIO_AUTH_TOKEN || !hasSender)) {
  console.warn(
    JSON.stringify({
      timestamp: new Date().toISOString(),
      level: "warn",
      message: "SMS_ENABLED is set but Twilio credentials are not configured, so no SMS will be sent. Set TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, and either TWILIO_MESSAGING_SERVICE_SID (preferred) or TWILIO_FROM_NUMBER.",
    })
  );
}

export interface SMSResult {
  success: boolean;
  sid?: string;
  error?: string;
}

export async function sendSMS(to: string, body: string): Promise<SMSResult> {
  if (!SMS_ENABLED) {
    // No network call, no Twilio. Callers check SMS_ENABLED first; this is the
    // backstop for any caller that doesn't.
    return { success: false, error: "SMS disabled" };
  }
  if (!TWILIO_ACCOUNT_SID || !TWILIO_AUTH_TOKEN || !hasSender) {
    console.warn("SMS: Twilio credentials not configured, skipping SMS");
    return { success: false, error: "Twilio not configured" };
  }

  // Normalize phone number
  const normalizedTo = normalizePhone(to);
  if (!normalizedTo) {
    return { success: false, error: "Invalid phone number" };
  }

  const url = `https://api.twilio.com/2010-04-01/Accounts/${TWILIO_ACCOUNT_SID}/Messages.json`;
  const auth = btoa(`${TWILIO_ACCOUNT_SID}:${TWILIO_AUTH_TOKEN}`);

  const formData = new URLSearchParams();
  formData.append("To", normalizedTo);
  if (TWILIO_MESSAGING_SERVICE_SID) {
    formData.append("MessagingServiceSid", TWILIO_MESSAGING_SERVICE_SID);
  } else {
    formData.append("From", TWILIO_FROM_NUMBER);
  }
  formData.append("Body", body);

  try {
    const response = await fetch(url, {
      method: "POST",
      headers: {
        Authorization: `Basic ${auth}`,
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: formData.toString(),
    });

    const result = await response.json();

    if (response.ok) {
      return { success: true, sid: result.sid };
    }

    return {
      success: false,
      error: result.message || `HTTP ${response.status}`,
    };
  } catch (error) {
    return {
      success: false,
      error: error instanceof Error ? error.message : "Unknown error",
    };
  }
}

/**
 * Normalize and validate phone number to E.164 format.
 * Accepts: +[1-9][0-9]{1,14} (international E.164)
 * Also handles US numbers without country code (10 or 11 digits).
 * Maximum 20 characters to prevent abuse.
 */
function normalizePhone(phone: string): string | null {
  if (phone.length > 20) return null;

  // Strip all non-digit characters except leading +
  const cleaned = phone.replace(/[^\d+]/g, "");

  // If no country code, try US normalization
  if (!cleaned.startsWith("+")) {
    const digits = cleaned.replace(/\D/g, "");
    if (digits.length === 10 && digits[0] >= "2") {
      return `+1${digits}`;
    }
    if (digits.length === 11 && digits.startsWith("1") && digits[1] >= "2") {
      return `+${digits}`;
    }
    // Try as-is with + prefix for other formats
    if (digits.length >= 7 && digits.length <= 15) {
      return `+${digits}`;
    }
    return null;
  }

  // Validate E.164 format: +[1-9][0-9]{1,14}
  if (/^\+[1-9]\d{1,14}$/.test(cleaned)) {
    return cleaned;
  }

  return null;
}

export function buildEscalationSMS(
  receiverName: string,
  type: "owner_alert" | "viewer_alert"
): string {
  if (type === "owner_alert") {
    return `Daily OK Alert: ${receiverName} has missed their daily check-in. They've been reminded twice with no response. Open the Daily OK app for details. Reply STOP to opt out.`;
  }
  return `Daily OK Family Alert: ${receiverName} has missed their daily check-in today. Please check on them. Reply STOP to opt out.`;
}
