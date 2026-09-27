-- Daily OK: the product no longer sends text messages from a server.
-- Migration: 00065_no_server_sms_copy
--
-- ─── WHAT AND WHY ────────────────────────────────────────────────────────────
-- Server-sent SMS (Twilio escalation texts) is switched off: it needs an
-- A2P 10DLC registration the product can't meet. Escalation is push-only
-- (APNs/FCM), and a text between family members is written in the phone's own
-- Messages composer, pre-filled, and sent from the person's own number. The
-- edge functions gate the old code behind SMS_ENABLED (default false).
--
-- This migration changes COPY only, so the blog generator stops telling
-- readers that Daily OK has "SMS fallback":
--   1. conversion.objection_handlers.free_alternatives_exist no longer lists
--      "SMS fallback" as something Daily OK charges for.
--   2. conversion.never_claim gains "Daily OK sends SMS/text-message alerts".
--
-- Data and schema are untouched. In particular receiver_settings
-- .sms_escalation_enabled STAYS (backward compatibility, CLAUDE.md §A): older
-- iOS/Android builds still read and write it, and get_receiver_history (00057)
-- still returns it. The server simply no longer acts on it.
--
-- Idempotent: the value is overwritten, and the never_claim entry is appended
-- only when it's missing. Only touches the singleton row, and only when the
-- conversion section exists (00025).

BEGIN;

UPDATE blog_generation_config
SET config = jsonb_set(
        config,
        '{conversion,objection_handlers,free_alternatives_exist}',
        to_jsonb('Snug Safety has a free tier and it is a real option — say so honestly. Daily OK charges for family-side escalation (push alerts to the caregiver first, then co-caregivers), one-tap call or a pre-written text sent from the caregiver''s own phone, and multi-member coordination. Daily OK does not send SMS alerts. Call out specific differences; do not disparage.'::text),
        true
    )
WHERE id = 1
  AND config #> '{conversion,objection_handlers}' IS NOT NULL;

UPDATE blog_generation_config
SET config = jsonb_set(
        config,
        '{conversion,never_claim}',
        (config #> '{conversion,never_claim}') || to_jsonb('Daily OK sends SMS or text-message alerts (alerts are push notifications; any text is sent by a family member from their own phone)'::text),
        false
    )
WHERE id = 1
  AND jsonb_typeof(config #> '{conversion,never_claim}') = 'array'
  AND NOT EXISTS (
      SELECT 1
      FROM jsonb_array_elements_text(config #> '{conversion,never_claim}') AS c(claim)
      WHERE c.claim LIKE 'Daily OK sends SMS or text-message alerts%'
  );

COMMIT;
