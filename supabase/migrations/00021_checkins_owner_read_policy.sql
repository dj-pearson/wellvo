-- Daily OK: allow family owners to read checkins even without a family_members row
-- Migration: 00021_checkins_owner_read_policy
--
-- Root cause: the `checkins` SELECT policy named "Family owners and viewers can
-- read family checkins" only checks `is_family_member(family_id)`. That helper
-- requires an active row in `family_members` — but some owner accounts were
-- created before `FamilyService.createFamily` started inserting the owner into
-- `family_members`, and invite / auto-join flows can also leave the owner out.
-- In that state the owner is still `families.owner_id` (so on-demand-checkin
-- and request creation work) but cannot read `checkins` for their own family,
-- which leaves the dashboard stuck on "Pending" forever.
--
-- Fix: replace the policy with one that allows either path — `is_family_owner`
-- OR `is_family_member`. Matches the already-correct policies on
-- `checkin_requests` (owner read path at migration 00002) and `alerts` (owner
-- path at migration 00006).
--
-- Safe to re-run: DROP IF EXISTS then CREATE.

BEGIN;

DROP POLICY IF EXISTS "Family owners and viewers can read family checkins" ON checkins;

CREATE POLICY "Family owners and viewers can read family checkins"
    ON checkins FOR SELECT
    USING (is_family_owner(family_id) OR is_family_member(family_id));

-- Drop the UTC-day uniqueness index added in 00007. It partitioned
-- duplicates by UTC calendar date, but the iOS/Android clients and the
-- dashboard query for "today" using the user's local calendar day. In a
-- west-of-UTC timezone a late-evening-local check-in (e.g. 23:51 EDT =
-- 03:51 UTC next day) lives in the *same* UTC day as the next morning's
-- check-in, so the constraint blocked a legitimate new row and the owner
-- dashboard stayed on Pending. Dedup now lives in the
-- process-checkin-response edge function where the receiver's IANA
-- timezone (`users.timezone`) is available.
DROP INDEX IF EXISTS idx_checkins_unique_daily;

COMMIT;
