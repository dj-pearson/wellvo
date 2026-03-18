/**
 * SMS client using Twilio API.
 * Used as a fallback escalation channel when push notifications fail
 * or as an additional alert for critical escalation steps.
 */

const TWILIO_ACCOUNT_SID = Deno.env.get("TWILIO_ACCOUNT_SID") || "";
const TWILIO_AUTH_TOKEN = Deno.env.get("TWILIO_AUTH_TOKEN") || "";
const TWILIO_FROM_NUMBER = Deno.env.get("TWILIO_FROM_NUMBER") || "";

// Log startup warning if Twilio is not configured
if (!TWILIO_ACCOUNT_SID || !TWILIO_AUTH_TOKEN || !TWILIO_FROM_NUMBER) {
  console.warn(
    JSON.stringify({
      timestamp: new Date().toISOString(),
      level: "warn",
      message: "Twilio SMS credentials not configured. SMS escalation will be disabled. Set TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, and TWILIO_FROM_NUMBER.",
    })
  );
}

export interface SMSResult {
  success: boolean;
  sid?: string;
  error?: string;
}

export async function sendSMS(to: string, body: string): Promise<SMSResult> {
  if (!TWILIO_ACCOUNT_SID || !TWILIO_AUTH_TOKEN || !TWILIO_FROM_NUMBER) {
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
  formData.append("From", TWILIO_FROM_NUMBER);
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

function normalizePhone(phone: string): string | null {
  // Strip all non-digit characters except leading +
  const cleaned = phone.replace(/[^\d+]/g, "");
  if (cleaned.length < 10) return null;

  // Add +1 for US numbers without country code
  if (!cleaned.startsWith("+")) {
    return `+1${cleaned}`;
  }
  return cleaned;
}

export function buildEscalationSMS(
  receiverName: string,
  type: "owner_alert" | "viewer_alert"
): string {
  if (type === "owner_alert") {
    return `Wellvo Alert: ${receiverName} has missed their daily check-in. They've been reminded twice with no response. Open the Wellvo app for details.`;
  }
  return `Wellvo Family Alert: ${receiverName} has missed their daily check-in today. Please check on them.`;
}
