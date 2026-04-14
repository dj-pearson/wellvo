-- Daily OK: Enable Supabase Realtime for check-in sync tables
-- Migration: 00020_realtime_publications
--
-- Root cause: the Owner dashboard subscribes to `checkins` (and should subscribe
-- to `checkin_requests` / `alerts`) via the Supabase Realtime client. However,
-- these tables were never added to the `supabase_realtime` publication, so
-- Postgres never streamed changes to the Realtime server. The owner UI would
-- stay on "Pending" indefinitely even after the receiver tapped "I'm OK".
--
-- This migration:
--   1. Ensures the `supabase_realtime` publication exists (defensive — self-hosted
--      Supabase usually pre-creates it, but local bootstraps may not).
--   2. Adds the three tables that drive the owner UI to the publication.
--   3. Sets REPLICA IDENTITY FULL so UPDATE / DELETE events carry full rows
--      (required for client-side filters like `family_id=eq.<uuid>` to match
--      on UPDATE events, since the default replica identity only ships the PK).
--
-- Safe to re-run: uses existence checks before ALTER PUBLICATION / REPLICA IDENTITY.

BEGIN;

-- 1. Ensure publication exists
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
        CREATE PUBLICATION supabase_realtime;
    END IF;
END $$;

-- 2. Add tables to publication (idempotent — skip if already a member)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime'
          AND schemaname = 'public'
          AND tablename  = 'checkins'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.checkins;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime'
          AND schemaname = 'public'
          AND tablename  = 'checkin_requests'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.checkin_requests;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime'
          AND schemaname = 'public'
          AND tablename  = 'alerts'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.alerts;
    END IF;
END $$;

-- 3. Replica identity — ship full rows so RLS + filters work on UPDATE/DELETE.
-- FULL is slightly more WAL-heavy than DEFAULT, but these tables are low-volume
-- (a few rows per user per day), so the cost is negligible.
ALTER TABLE public.checkins          REPLICA IDENTITY FULL;
ALTER TABLE public.checkin_requests  REPLICA IDENTITY FULL;
ALTER TABLE public.alerts            REPLICA IDENTITY FULL;

-- 4. Allow receivers to resolve their own pending check-in requests.
--
-- The `process-checkin-response` edge function (service role) already flips
-- `checkin_requests.status` from `pending` to `checked_in` when the receiver
-- taps "I'm OK" online. When the tap happens offline, the iOS / Android offline
-- queue inserts the checkin directly via RLS — but without this policy the
-- queued sync can't close out the matching request row, leaving the owner
-- dashboard stuck on "Pending" even after the check-in lands.
--
-- Policy is intentionally narrow:
--   * Receivers can only UPDATE rows where they are the `receiver_id`.
--   * The USING + WITH CHECK pair restricts changes to rows they already own.
-- The edge function keeps authoring all OTHER transitions (expired, missed)
-- under the service role, so the surface area stays small.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename  = 'checkin_requests'
          AND policyname = 'Receivers can resolve own requests'
    ) THEN
        CREATE POLICY "Receivers can resolve own requests"
            ON public.checkin_requests
            FOR UPDATE
            USING (receiver_id = auth.uid())
            WITH CHECK (receiver_id = auth.uid());
    END IF;
END $$;

COMMIT;

-- Verification query (for manual post-migration check):
--   SELECT schemaname, tablename FROM pg_publication_tables
--   WHERE pubname = 'supabase_realtime' ORDER BY tablename;
-- Expected rows: public.alerts, public.checkin_requests, public.checkins
