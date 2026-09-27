-- Daily OK: close the direct-database holes that no shipped client uses.
-- Migration: 00063_client_access_lockdown
--
-- Earlier passes deferred each item below as "tightens RLS / needs a release
-- boundary". The user has authorised closing them now, on one condition: the
-- access being removed must be proven unused by every shipped client (iOS
-- ios/, Android android/, website website/). Everything here was checked
-- against the current tree AND against every historical revision of ios/ and
-- android/ (`git log -p -- ios android`), because older store builds are
-- still installed. Anything a shipped client still uses is left open and
-- listed under NOT CHANGED at the end.
--
-- Edge functions are not affected: every one of them uses the service-role
-- client (edge-functions/shared/supabase.ts `supabaseAdmin`,
-- shared/auth.ts), so they are subject to neither RLS nor these grants.
-- SECURITY DEFINER RPCs run as their owner and are not affected either. No
-- trigger function that runs as the caller (SECURITY INVOKER) writes checkins,
-- checkin_requests or alerts (checked in pg_proc on a scratch DB).
--
-- The website only touches `users` (src/admin/AdminAuthProvider.tsx) and
-- `blog_posts` (src/pages/Blog.tsx, BlogPost.tsx) directly; everything else
-- goes through edge functions (src/lib/api.ts). It touches none of the tables
-- below.
--
-- ─── 1. Receivers reading other receivers' check-ins (and GPS) ──────────────
-- "Family owners and viewers can read family checkins" (00021) used
-- is_family_owner(family_id) OR is_family_member(family_id), and
-- is_family_member has no role filter. So an active RECEIVER could read every
-- other receiver's rows in the family, including latitude / longitude /
-- location_accuracy_meters / distance_from_home_meters. The policy is
-- replaced with is_active_caregiver_of(family_id) (00055: family owner, or an
-- active owner/viewer membership). Receivers keep "Receivers can read own
-- checkins" (receiver_id = auth.uid()).
--
-- Proof no receiver path reads anyone else's rows. Every client read of
-- `checkins`:
--   iOS  Services/CheckInService.swift todayCheckInStatus / todayCheckIns /
--        checkInHistory: always .eq("receiver_id", …). Receiver callers pass
--        session.user.id (ViewModels/ReceiverViewModel.swift loadState:
--        todayCheckIns + checkInHistory). The other callers are owner/viewer
--        screens (ViewModels/DashboardViewModel.swift, Views/Owner/
--        HistoryView.swift). The realtime subscription on `checkins`
--        (DashboardViewModel.swift ~1337) is in the owner/viewer dashboard.
--        ContentView routes receivers away from OwnerTabView / ViewerTabView.
--   Android services/CheckInService.kt todayCheckInStatus / checkInHistory:
--        receiver callers (viewmodels/ReceiverViewModel.kt) pass their own
--        userId. todayCheckInsForFamily / familyCheckInHistory (family-wide)
--        are only called by viewmodels/DashboardViewModel.kt, and
--        checkInHistoryPaginated only by HistoryViewModel.kt; both live in
--        OwnerTabsScreen / ViewerTabsScreen, which ui/navigation/
--        DailyOKNavHost.kt never routes a receiver to.
--
-- ─── 2. Direct client writes that bypass the edge functions ─────────────────
-- a) INSERT on checkins. Shipped iOS builds 1.0.3-1.0.6 (commits ed50381
--    .. 95fc15b, released via release/1.0.6 = 06e48dd on main) replay their
--    offline queue by POSTing /rest/v1/checkins directly
--    (Services/OfflineCheckInService.swift, OfflineCheckInInsert:
--    receiver_id, family_id, checked_in_at, mood, source) and 00057 was
--    written to keep that working. MIN_SUPPORTED_IOS_APP_VERSION is still
--    0.0.0 (edge-functions/shared/config.ts), so the direct insert can NOT be
--    removed yet: those receivers' queued check-ins would never land and
--    their families would be escalated for a check-in that happened.
--    Instead the policy "Receivers can insert own checkins" stays and INSERT
--    is narrowed to exactly those five columns. A direct insert can no longer
--    set response_type ('need_help'/'call_me'), kid_response_type ('sos'),
--    coordinates, location_label, local_date, scheduled_for or slot_key; the
--    00057/00061/00062 guard still clamps checked_in_at and requires an
--    active receiver. Revoke the remaining columns once
--    MIN_SUPPORTED_IOS_APP_VERSION >= 1.0.7 (95fc15b moved offline replay to
--    process-checkin-response).
-- b) INSERT on checkin_requests ("Owners can create requests"): owners could
--    raise unlimited requests (push/SMS amplification). Requests come from
--    send-checkin / dispatch_scheduled_checkins (service role, pg_cron). Policy
--    dropped, INSERT revoked. No revision of ios/ or android/ inserts them.
-- c) UPDATE on checkin_requests ("Receivers can resolve own requests"): a
--    receiver could mark a request answered without a check-in, silencing its
--    escalation. Answering, snoozing, claiming and standing down go through
--    process-checkin-response / snooze_checkin_request / claim_checkin_request
--    / cancel-escalation. Policy dropped, UPDATE revoked.
--    The one client writer ever shipped is the same iOS 1.0.3-1.0.6 offline
--    replay (c163a02 added the policy for it): after its direct check-in
--    insert it PATCHes that receiver's pending requests to checked_in, inside
--    `try?`, so the refusal is silent. To keep the result it relied on, a
--    client-role check-in insert now resolves those pending requests
--    server-side (trg_checkins_client_insert_resolve, SECURITY DEFINER, the
--    same update process-checkin-response makes). A receiver can therefore
--    only clear a request by actually recording a check-in.
-- d) UPDATE on checkins: the 00057+ guard pins most columns, but scheduled_for
--    and local_date (part of the 00053 one-per-day unique index) were still
--    writable. UPDATE is now granted only on the three columns clients set
--    after a check-in: mood, location_label, kid_response_type (the Android
--    kid SOS PATCH writes kid_response_type and keeps working).
-- Proof (`git log --all -p -- ios android`): apart from the iOS offline
-- replay above, no revision inserts into checkins or checkin_requests or
-- updates checkin_requests. The only client updates of `checkins` ever
-- written are
--   iOS  ViewModels/ReceiverViewModel.swift setMood: .update(["mood": …])
--   Android viewmodels/ReceiverViewModel.kt submitMood / submitLocationLabel /
--        submitKidResponse: mood, location_label, kid_response_type.
-- Current builds send every check-in (online, offline sync, widget, watch,
-- NSE, Siri) through process-checkin-response. iOS HealthService.swift upserts
-- wellness_signals, a different table, untouched here. The Android helpers
-- insertRow/upsertRow in network/SupabaseExtensions.kt have no callers.
--
-- ─── 3. Owners editing arbitrary alert fields ────────────────────────────────
-- "Owners can update family alerts" allowed a whole-row UPDATE, so an owner
-- could write acknowledged_by / acknowledged_by_name ("Handled by Tom") or
-- rewrite title/message/type. Claims must go through acknowledge_alert_v2 (or
-- the fixed v1). UPDATE on alerts is now granted only on is_read, the one
-- column clients write (dismissing an alert):
--   iOS  ViewModels/DashboardViewModel.swift dismissAlert: .update(["is_read": true])
--   Android viewmodels/DashboardViewModel.kt dismissAlert: put("is_read", true)
-- No revision of ios/ or android/ has written any other alerts column. The
-- owner-only UPDATE policy stays, so who may dismiss is unchanged.
--
-- ─── 4. has_apple_identity(p_user_id) answered for any user ─────────────────
-- Any signed-in user could ask whether any other user id has an Apple
-- identity. Every client call ever written passes the caller's own id
-- (ios/DailyOK/Services/AuthService.swift appleIDLinkStatus:
-- ["p_user_id": session.user.id], only as the fallback after
-- has_my_apple_identity; Android and the website never call it). It now raises
-- for a user-JWT caller asking about someone else. A caller with no auth.uid()
-- (service role) is unaffected. EXECUTE is revoked from PUBLIC/anon.
--
-- ─── 5. care_notes INSERT with a receiver_id outside the family ─────────────
-- The INSERT policy checked only the author's membership, so a note could be
-- filed against any user id. The client-write guard now also requires
-- receiver_id to be a receiver (any status) of family_id. The only client
-- writer, ios/DailyOK/Views/Owner/CareNotesView.swift add(), passes the
-- receiverId it was opened with: a receiver card (Views/Owner/
-- DashboardView.swift, card.id) or a receiver's settings (Views/Settings/
-- ReceiverSettingsView.swift, member.userId). Android has no care notes.
-- Any status is accepted so notes on a paused or removed receiver still save.
--
-- ─── NOT CHANGED (a shipped client still depends on the access) ─────────────
-- * families.billing_original_transaction_id / billing_platform readable by
--   members. iOS Services/FamilyService.swift getFamily() and
--   createFamily() read families with .select() (select=*); Android
--   services/FamilyService.kt getFamily() does the same, and its family insert
--   returns the row (select()). A column-level REVOKE makes select=* fail with
--   "permission denied" for every caller, which would break family loading on
--   every shipped iOS and Android build. No client decodes these
--   columns (ios Models/Family.swift decodes billing_user_id only), so the path
--   is: ship an explicit column list in FamilyService, then REVOKE
--   SELECT (billing_original_transaction_id, …) once
--   MIN_SUPPORTED_IOS_APP_VERSION includes it. (A my_family_plan() RPC is not
--   needed: no client reads those values.)
-- * transfer_family_ownership (00045) still accepts a receiver target. iOS
--   builds before commit 4c8adff offered Transfer on any active non-owner
--   member (Views/Owner/FamilyView.swift at 07b5dc2: `member.role != .owner &&
--   member.status == .active`) and called this function. Current builds call
--   transfer_family_ownership_v2 and fall back to v1 only when v2 is missing.
-- * getFamilyMembers' users(*) embed (phone, email, is_system_admin readable
--   by family members): shipped builds select users(*); a column REVOKE would
--   break it the same way as families above.
-- * Receivers' UPDATE of mood / location_label / kid_response_type on their
--   own checkins: used by both apps (item 2d), kept.
-- * Receivers' direct INSERT of their own check-in (receiver_id, family_id,
--   checked_in_at, mood, source only): iOS 1.0.3-1.0.6 offline replay (item
--   2a). Revoke once MIN_SUPPORTED_IOS_APP_VERSION >= 1.0.7.
-- * Owners' DELETE on alerts ("Owners can delete family alerts") and on
--   checkin_requests ("Owners can delete family requests"): no revision of
--   ios/ or android/ deletes these rows, but neither was on the deferred
--   list; left for a separate decision.
-- * acknowledge_alert v1: already given v2's no-takeover rules in 00062 §2;
--   nothing left to close.
-- * care_notes body length cap: shipped iOS doesn't limit characters
--   (CareNotesView TextField lineLimit is visual only), so a cap could reject
--   a note an older build accepts.
--
-- ─── VERIFICATION ────────────────────────────────────────────────────────────
--   SELECT policyname, cmd FROM pg_policies
--    WHERE tablename IN ('checkins','checkin_requests')
--    ORDER BY 1;  -- INSERT only "Receivers can insert own checkins";
--                 -- no "Owners can create requests" / "Receivers can resolve own requests"
--   SELECT qual FROM pg_policies WHERE tablename = 'checkins'
--    AND policyname = 'Family owners and viewers can read family checkins';
--                                            -- is_active_caregiver_of(family_id)
--   SELECT has_table_privilege('authenticated','checkins','INSERT'),          -- f
--          has_column_privilege('authenticated','checkins','source','INSERT'), -- t
--          has_column_privilege('authenticated','checkins','response_type','INSERT'), -- f
--          has_table_privilege('authenticated','checkin_requests','INSERT'),  -- f
--          has_table_privilege('authenticated','checkin_requests','UPDATE'),  -- f
--          has_table_privilege('authenticated','alerts','UPDATE'),            -- f
--          has_column_privilege('authenticated','alerts','is_read','UPDATE'), -- t
--          has_column_privilege('authenticated','alerts','acknowledged_by_name','UPDATE'), -- f
--          has_column_privilege('authenticated','checkins','mood','UPDATE'),  -- t
--          has_column_privilege('authenticated','checkins','local_date','UPDATE'); -- f
--   As a receiver (SET ROLE authenticated; request.jwt.claims {"sub": …}):
--     SELECT count(*) FROM checkins WHERE receiver_id <> auth.uid();   -- 0

BEGIN;

-- 1. Check-in reads: caregivers read the family, receivers read their own.
DROP POLICY IF EXISTS "Family owners and viewers can read family checkins" ON checkins;
CREATE POLICY "Family owners and viewers can read family checkins"
    ON checkins FOR SELECT
    USING (is_active_caregiver_of(family_id));

-- 2a. Direct check-in inserts: only the columns iOS 1.0.3-1.0.6 offline
-- replay sends. The policy "Receivers can insert own checkins" is kept.
REVOKE INSERT ON checkins FROM anon, authenticated;
GRANT INSERT (receiver_id, family_id, checked_in_at, mood, source)
    ON checkins TO authenticated;

-- 2b. No direct client inserts of check-in requests.
DROP POLICY IF EXISTS "Owners can create requests" ON checkin_requests;
REVOKE INSERT ON checkin_requests FROM anon, authenticated;

-- 2c. No direct client updates of check-in requests.
DROP POLICY IF EXISTS "Receivers can resolve own requests" ON checkin_requests;
REVOKE UPDATE ON checkin_requests FROM anon, authenticated;

-- A client-role check-in insert (old iOS offline replay) resolves that
-- receiver's pending requests, as process-checkin-response does for its own
-- inserts. Service-role inserts are skipped (the edge function does it).
CREATE OR REPLACE FUNCTION resolve_requests_on_client_checkin()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    UPDATE checkin_requests
       SET status = 'checked_in',
           responded_at = NOW()
     WHERE receiver_id = NEW.receiver_id
       AND family_id = NEW.family_id
       AND status = 'pending';
    RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION resolve_requests_on_client_checkin() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_checkins_client_insert_resolve ON checkins;
CREATE TRIGGER trg_checkins_client_insert_resolve
    AFTER INSERT ON checkins
    FOR EACH ROW
    WHEN (is_client_role())
    EXECUTE FUNCTION resolve_requests_on_client_checkin();

-- 2d. Check-in updates: only the post-check-in annotations. The RLS policy
-- "Receivers can update own checkins" and the 00057+ guard still apply.
REVOKE UPDATE ON checkins FROM anon, authenticated;
GRANT UPDATE (mood, location_label, kid_response_type) ON checkins TO authenticated;

-- 3. Alerts: dismiss only. Claims go through acknowledge_alert_v2 / v1.
REVOKE UPDATE ON alerts FROM anon, authenticated;
GRANT UPDATE (is_read) ON alerts TO authenticated;

-- 4. has_apple_identity: self only for user callers.
CREATE OR REPLACE FUNCTION public.has_apple_identity(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = auth, public
AS $$
BEGIN
    -- A user JWT may only ask about itself. The service role has no
    -- auth.uid() and may ask about anyone.
    IF auth.uid() IS NOT NULL AND p_user_id IS DISTINCT FROM auth.uid() THEN
        RAISE EXCEPTION 'You can only check your own account'
            USING ERRCODE = 'insufficient_privilege';
    END IF;
    RETURN EXISTS (
        SELECT 1 FROM auth.identities
        WHERE user_id = p_user_id AND provider = 'apple'
    );
END;
$$;
REVOKE ALL ON FUNCTION public.has_apple_identity(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.has_apple_identity(UUID) TO authenticated, service_role;

-- 5. care_notes: the note's receiver must be a receiver of that family.
-- Same body as 00062 plus the receiver check on INSERT.
CREATE OR REPLACE FUNCTION guard_care_note_write()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_name TEXT;
BEGIN
    -- Server-side code (service role, SECURITY DEFINER functions) is trusted.
    IF NOT is_client_role() THEN
        RETURN NEW;
    END IF;

    IF TG_OP = 'INSERT' THEN
        -- is_active_receiver_of() is about the caller, so check the row's
        -- receiver directly. Any status, so a paused or removed receiver's
        -- notes still save. family_members is readable by the caregiver
        -- (the INSERT policy already requires an active owner/viewer row).
        IF NOT EXISTS (
            SELECT 1 FROM family_members fm
            WHERE fm.family_id = NEW.family_id
              AND fm.user_id = NEW.receiver_id
              AND fm.role = 'receiver'
        ) THEN
            RAISE EXCEPTION 'Care notes must be about a receiver in this family'
                USING ERRCODE = 'insufficient_privilege';
        END IF;
        SELECT NULLIF(btrim(display_name), '') INTO v_name
        FROM users WHERE id = NEW.author_id;
        NEW.author_name := COALESCE(v_name, 'A caregiver');
        NEW.created_at := NOW();
        NEW.updated_at := NOW();
    ELSE
        -- A removed co-caregiver keeps author_id = auth.uid(), which is all
        -- the UPDATE policy checks.
        IF NOT is_active_caregiver_of(OLD.family_id) THEN
            RAISE EXCEPTION 'Only current caregivers can edit care notes'
                USING ERRCODE = 'insufficient_privilege';
        END IF;
        NEW.id := OLD.id;
        NEW.family_id := OLD.family_id;
        NEW.receiver_id := OLD.receiver_id;
        NEW.author_id := OLD.author_id;
        NEW.author_name := OLD.author_name;
        NEW.created_at := OLD.created_at;
        -- updated_at is set by trg_care_notes_touch.
    END IF;
    RETURN NEW;
END;
$$;

COMMIT;
