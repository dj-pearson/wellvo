-- Daily OK: Add Caregiver subscription tier
-- Migration: 00019_add_caregiver_tier
--
-- Introduces a new "caregiver" subscription tier sized for the dominant
-- real-world persona: one adult child monitoring one aging parent with
-- dementia, with 1-3 siblings watching read-only.
--
--  Caregiver: $3.99/mo, $29.99/yr — 1 Receiver, 3 Viewers
--  Family:    $6.99/mo, $49.99/yr — 3 Receivers, 5 Viewers (reprice)
--  Family+:   $9.99/mo, $79.99/yr — 6 Receivers, 10 Viewers (reprice)
--
-- Also grandfathers existing Free-tier families for 90 days before they lose
-- access, so early testers aren't cut off abruptly.
--
-- See docs/PRICING_RESEARCH.md for the full rationale.

-- =============================================================================
-- 1. NEW ENUM VALUE
-- ALTER TYPE ... ADD VALUE cannot run inside a transaction block.
-- Using IF NOT EXISTS so this migration is safe to re-run.
-- =============================================================================

ALTER TYPE subscription_tier ADD VALUE IF NOT EXISTS 'caregiver' BEFORE 'family';

-- =============================================================================
-- 2. SCHEMA CHANGES
-- =============================================================================

BEGIN;

-- Grandfather column: existing Free families keep access until this date,
-- after which they are prompted to upgrade to Caregiver. NULL for families
-- created after this migration — new signups go straight to the trial flow
-- and don't use the Free tier at all.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'families' AND column_name = 'free_tier_expires_at'
    ) THEN
        ALTER TABLE families
            ADD COLUMN free_tier_expires_at TIMESTAMPTZ;
    END IF;
END $$;

-- Backfill: every existing Free family gets a 90-day grandfather window from
-- the migration runtime. After that, the iOS/Android clients show an upgrade
-- banner and gate paid features. Paid families are untouched.
UPDATE families
SET free_tier_expires_at = NOW() + INTERVAL '90 days'
WHERE subscription_tier = 'free'
  AND free_tier_expires_at IS NULL;

-- Widen the Family+ ceiling to match the new pricing table. Existing Family+
-- subscribers keep their old higher limits in practice because the webhook
-- only writes max_receivers/max_viewers on renewal — but update defaults for
-- any new provisioning path.
COMMENT ON COLUMN families.free_tier_expires_at IS
    'Grandfathering deadline for legacy Free-tier families. NULL for new families (Free tier is deprecated — new signups start a trial on the Caregiver/Family/Family+ tiers instead).';

COMMIT;
