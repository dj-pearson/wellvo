-- Daily OK: Co-caregiver (viewer) experience — summaries for co-caregivers,
-- claims that can't be taken over, care notes a removed member can't rewrite,
-- and the family/check-in columns a caller must not choose.
-- Migration: 00062_viewer_experience_integrity
--
-- ─── WHAT AND WHY ────────────────────────────────────────────────────────────
-- 1. dispatch_caregiver_digests(): co-caregivers can now get the daily/weekly
--    check-in summary. The dispatcher only selected users who OWN a family, so
--    a co-caregiver who set users.digest_frequency (their own row, writable
--    since 00051) never got anything. It now also selects users with an active
--    viewer membership and sends `user_id` alongside `owner_id` (same value).
--    send-digest resolves the family through the membership. An older
--    send-digest given a viewer's id finds no owned family and skips (no push,
--    no error), so the order of deploys doesn't matter.
--
-- 2. acknowledge_alert(p_alert_id, p_release) — v1, still granted to
--    `authenticated`. It let any active owner/viewer overwrite someone else's
--    claim (last writer wins) or clear it, which acknowledge_alert_v2 (00055)
--    fixed only for builds that call v2. The same function signature and
--    return type now follow v2's rules: claim only when unclaimed or already
--    yours; release only your own claim (the owner may release any). It still
--    returns the row as it now stands, so older builds render the real holder
--    ("Handled by Sarah") instead of a claim that silently replaced hers.
--    SET search_path is added (v1 had none).
--
-- 3. care_notes: the UPDATE / DELETE policies only check author_id, not that
--    the author is still in the family. A filtered PATCH/DELETE (?id=eq.…)
--    is already stopped by the SELECT policy, but an UNFILTERED one is not
--    (Postgres applies SELECT policies only when the statement reads rows):
--    verified on PG16, a removed co-caregiver's `UPDATE care_notes SET body`
--    rewrote every note they had written. Client UPDATE and DELETE now also
--    need an active owner/viewer membership (or ownership) of the note's
--    family. Service role, SECURITY DEFINER code (account deletion) and FK
--    cascades are unaffected (is_client_role()).
--
-- 4. families.created_at is pinned for client writes (INSERT: now(); UPDATE:
--    unchanged). App Store notifications pick the family billed to a
--    subscription by `billing_original_transaction_id`, oldest family first;
--    an owner could PATCH their own family's created_at to 1970 to win that
--    ordering. (The subscription webhook also stops storing a client-claimed
--    original_id that another family or account already holds — edge code.)
--    No shipped client writes created_at.
--
-- 5. checkins INSERT (client role): the caller must be an active RECEIVER of
--    the family (was: any active member). With the old check an owner or a
--    co-caregiver could insert rows as themselves and inflate the caregiver
--    summary ("7 of 7 check-ins — no misses") while the receiver was missing
--    days. No shipped iOS or Android build inserts checkins directly (both go
--    through process-checkin-response as service_role; audited 00057/00061).
--    send-digest now also counts only active receivers' rows.
--
-- 6. "I'm on it" for a missed check-in. A missed / escalating check-in pages the
--    owner and every co-caregiver, and none of them could see whether someone
--    was already calling Mom — acknowledge_alert only covers `alerts` rows
--    (help requests), and escalation-tick never writes one. New nullable
--    columns checkin_requests.claimed_by / claimed_at / claimed_by_name and a
--    new RPC claim_checkin_request(p_request_id, p_release) with
--    acknowledge_alert_v2's rules: an active owner/co-caregiver claims only an
--    unclaimed (or their own) pending/missed request; release is the claimer's
--    or the owner's. The client-write guard pins the columns, so only the RPC
--    sets them. The row change reaches every dashboard through the existing
--    realtime subscription on checkin_requests.
--
-- 7. A member who leaves or is removed releases their claims: "Tom is on it"
--    (check-in requests still pending / missed) and "Tom is handling this"
--    (alerts from the last 24 hours). Otherwise the family keeps waiting on
--    someone who no longer gets the alerts. AFTER trigger on family_members,
--    like 00058's stand-down on leave.
--
-- ─── COMPATIBILITY (CLAUDE.md §A) ────────────────────────────────────────────
-- Three nullable columns, four functions and two triggers are added (both apps ignore
-- unknown keys). No table, policy or enum is removed or changed. One
-- function signature is re-defined with the same arguments and return type
-- (acknowledge_alert); the rest are trigger bodies for client writes no
-- shipped build makes (created_at, checkins INSERT) or makes only as an
-- active member (care notes), and the digest dispatcher, which only adds
-- recipients. Idempotent: safe to replay.
-- ─────────────────────────────────────────────────────────────────────────────

BEGIN;

-- =============================================================================
-- 1. Caregiver summaries for co-caregivers
-- =============================================================================
CREATE OR REPLACE FUNCTION dispatch_caregiver_digests()
RETURNS void AS $$
DECLARE
    rec RECORD;
    v_tz TEXT;
    local_now TIMESTAMP;
BEGIN
    FOR rec IN
        SELECT
            u.id AS user_id,
            u.timezone,
            u.digest_frequency,
            u.digest_hour,
            u.digest_last_sent_at
        FROM users u
        -- Owners, and co-caregivers with an active membership.
        WHERE u.digest_frequency IN ('daily', 'weekly')
          AND (
              EXISTS (SELECT 1 FROM families f WHERE f.owner_id = u.id)
              OR EXISTS (
                  SELECT 1 FROM family_members fm
                  WHERE fm.user_id = u.id
                    AND fm.role = 'viewer'
                    AND fm.status = 'active'
              )
          )
    LOOP
        BEGIN
            v_tz := CASE WHEN is_valid_timezone(rec.timezone) THEN rec.timezone ELSE 'UTC' END;

            -- Current wall-clock time in the caregiver's timezone.
            local_now := (NOW() AT TIME ZONE v_tz);

            -- Wrong hour for this caregiver — skip.
            CONTINUE WHEN EXTRACT(HOUR FROM local_now)::int <> rec.digest_hour;

            -- Weekly digests only on Monday (ISO dow = 1).
            CONTINUE WHEN rec.digest_frequency = 'weekly'
                      AND EXTRACT(ISODOW FROM local_now)::int <> 1;

            -- Already sent today (local) — idempotent against multiple cron ticks.
            CONTINUE WHEN rec.digest_last_sent_at IS NOT NULL
                      AND (rec.digest_last_sent_at AT TIME ZONE v_tz)::date
                          = local_now::date;

            -- `owner_id` stays for send-digest builds that only read it; the
            -- current one reads `user_id` and resolves a co-caregiver's family
            -- through their membership.
            PERFORM net.http_post(
                url := current_setting('app.edge_functions_url') || '/send-digest',
                headers := jsonb_build_object(
                    'Content-Type', 'application/json',
                    'Authorization', 'Bearer ' || current_setting('app.service_role_key')
                ),
                body := jsonb_build_object('owner_id', rec.user_id, 'user_id', rec.user_id)
            );

            UPDATE users SET digest_last_sent_at = NOW() WHERE id = rec.user_id;
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'dispatch_caregiver_digests: user % skipped: %', rec.user_id, SQLERRM;
        END;
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =============================================================================
-- 2. acknowledge_alert (v1): same signature, v2's rules
-- =============================================================================
CREATE OR REPLACE FUNCTION acknowledge_alert(
    p_alert_id UUID,
    p_release  BOOLEAN DEFAULT FALSE
)
RETURNS alerts
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
    v_alert     alerts;
    v_family_id UUID;
    v_is_owner  BOOLEAN;
    v_name      TEXT;
BEGIN
    SELECT family_id INTO v_family_id FROM alerts WHERE id = p_alert_id;
    IF v_family_id IS NULL THEN
        RAISE EXCEPTION 'Alert not found' USING ERRCODE = 'no_data_found';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM family_members
        WHERE family_id = v_family_id
          AND user_id = auth.uid()
          AND role IN ('owner', 'viewer')
          AND status = 'active'
    ) THEN
        RAISE EXCEPTION 'Not authorized to acknowledge alerts for this family'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    v_is_owner := EXISTS (SELECT 1 FROM families WHERE id = v_family_id AND owner_id = auth.uid());

    IF p_release THEN
        UPDATE alerts
           SET acknowledged_by = NULL,
               acknowledged_at = NULL,
               acknowledged_by_name = NULL
         WHERE id = p_alert_id
           AND (acknowledged_by = auth.uid() OR v_is_owner);
    ELSE
        SELECT display_name INTO v_name FROM users WHERE id = auth.uid();
        UPDATE alerts
           SET acknowledged_by = auth.uid(),
               acknowledged_at = NOW(),
               acknowledged_by_name = COALESCE(v_name, 'A caregiver')
         WHERE id = p_alert_id
           AND (acknowledged_at IS NULL OR acknowledged_by = auth.uid());
    END IF;

    SELECT * INTO v_alert FROM alerts WHERE id = p_alert_id;
    RETURN v_alert;
END;
$$;

GRANT EXECUTE ON FUNCTION acknowledge_alert(UUID, BOOLEAN) TO authenticated;

-- =============================================================================
-- 3. Care notes: only current caregivers edit or delete
-- =============================================================================
CREATE OR REPLACE FUNCTION is_active_caregiver_of(p_family_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public AS $$
    SELECT EXISTS (SELECT 1 FROM families f WHERE f.id = p_family_id AND f.owner_id = auth.uid())
        OR EXISTS (
            SELECT 1 FROM family_members fm
            WHERE fm.family_id = p_family_id
              AND fm.user_id = auth.uid()
              AND fm.role IN ('owner', 'viewer')
              AND fm.status = 'active'
        );
$$;

REVOKE ALL ON FUNCTION is_active_caregiver_of(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION is_active_caregiver_of(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION is_active_caregiver_of(UUID) TO authenticated;

-- Same body as 00056, plus the membership check on UPDATE.
CREATE OR REPLACE FUNCTION guard_care_note_write()
RETURNS TRIGGER
-- SECURITY INVOKER on purpose: is_client_role() reads current_user, which a
-- SECURITY DEFINER function would replace with its owner.
LANGUAGE plpgsql AS $$
DECLARE
    v_name TEXT;
BEGIN
    -- Server-side code (service role, SECURITY DEFINER functions) is trusted.
    IF NOT is_client_role() THEN
        RETURN NEW;
    END IF;

    IF TG_OP = 'INSERT' THEN
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

CREATE OR REPLACE FUNCTION guard_care_note_delete()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT is_client_role() THEN
        RETURN OLD;
    END IF;
    IF NOT is_active_caregiver_of(OLD.family_id) THEN
        RAISE EXCEPTION 'Only current caregivers can delete care notes'
            USING ERRCODE = 'insufficient_privilege';
    END IF;
    RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trg_care_notes_guard_delete ON care_notes;
CREATE TRIGGER trg_care_notes_guard_delete
    BEFORE DELETE ON care_notes
    FOR EACH ROW EXECUTE FUNCTION guard_care_note_delete();

-- =============================================================================
-- 4. families.created_at is the server's
-- =============================================================================
-- Same body as 00059, plus created_at.
CREATE OR REPLACE FUNCTION guard_families_client_write()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT is_client_role() THEN
        RETURN NEW;
    END IF;

    IF TG_OP = 'INSERT' THEN
        -- A new family always starts on the base allowance; the subscription
        -- webhook (service_role) upgrades it once a purchase is verified.
        NEW.subscription_tier := 'free';
        NEW.subscription_status := 'active';
        NEW.subscription_expires_at := NULL;
        NEW.free_tier_expires_at := NULL;
        NEW.max_receivers := 1;
        NEW.max_viewers := 0;
        NEW.billing_user_id := NULL;
        NEW.billing_original_transaction_id := NULL;
        NEW.billing_platform := NULL;
        NEW.billing_verified_at := NULL;
        -- "Oldest family" decides which family an App Store subscription and
        -- the apps' family lookup resolve to; a client can't choose it.
        NEW.created_at := NOW();
    ELSE
        NEW.id := OLD.id;
        -- Ownership moves only through transfer_family_ownership() (00045).
        -- Raise rather than silently keep: the RLS WITH CHECK already rejected
        -- this write, and a quiet no-op would tell the caller it had worked.
        IF NEW.owner_id IS DISTINCT FROM OLD.owner_id THEN
            RAISE EXCEPTION 'Use transfer_family_ownership to change the owner'
                USING ERRCODE = 'insufficient_privilege';
        END IF;
        NEW.created_at := OLD.created_at;
        NEW.subscription_tier := OLD.subscription_tier;
        NEW.subscription_status := OLD.subscription_status;
        NEW.subscription_expires_at := OLD.subscription_expires_at;
        NEW.free_tier_expires_at := OLD.free_tier_expires_at;
        NEW.max_receivers := OLD.max_receivers;
        NEW.max_viewers := OLD.max_viewers;
        NEW.billing_user_id := OLD.billing_user_id;
        NEW.billing_original_transaction_id := OLD.billing_original_transaction_id;
        NEW.billing_platform := OLD.billing_platform;
        NEW.billing_verified_at := OLD.billing_verified_at;
    END IF;

    -- Retention: silently keep it in a sane range (shipped apps only send
    -- 90–730, so nothing they do changes).
    IF NEW.data_retention_days IS NULL THEN
        NEW.data_retention_days := 365;
    ELSIF NEW.data_retention_days < 30 THEN
        NEW.data_retention_days := 30;
    ELSIF NEW.data_retention_days > 3650 THEN
        NEW.data_retention_days := 3650;
    END IF;
    RETURN NEW;
END;
$$;

-- =============================================================================
-- 5. checkins: only an active receiver inserts (client role)
-- =============================================================================
-- Same body as 00061, with the INSERT membership check narrowed.
CREATE OR REPLACE FUNCTION guard_checkins_client_write()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT is_client_role() THEN
        RETURN NEW;
    END IF;

    IF TG_OP = 'INSERT' THEN
        -- RLS already requires receiver_id = auth.uid(); an owner or a
        -- co-caregiver inserting rows as themselves padded the family's
        -- check-in counts.
        IF NOT is_active_receiver_of(NEW.family_id) THEN
            RAISE EXCEPTION 'Not an active receiver in this family'
                USING ERRCODE = 'insufficient_privilege';
        END IF;
        -- Same window process-checkin-response accepts for occurred_at: no
        -- check-ins in the future, none backdated more than 7 days.
        NEW.checked_in_at := LEAST(
            GREATEST(COALESCE(NEW.checked_in_at, NOW()), NOW() - INTERVAL '7 days'),
            NOW()
        );
        NEW.received_at := NOW();
    ELSE
        NEW.id := OLD.id;
        NEW.receiver_id := OLD.receiver_id;
        NEW.family_id := OLD.family_id;
        NEW.checked_in_at := OLD.checked_in_at;
        NEW.received_at := OLD.received_at;
        NEW.response_type := OLD.response_type;
        NEW.source := OLD.source;
        NEW.slot_key := OLD.slot_key;
        -- Where a check-in happened is a fact of that check-in.
        NEW.latitude := OLD.latitude;
        NEW.longitude := OLD.longitude;
        NEW.location_accuracy_meters := OLD.location_accuracy_meters;
        NEW.distance_from_home_meters := OLD.distance_from_home_meters;
        -- An SOS can't be taken back after the alert went out.
        IF OLD.kid_response_type = 'sos' THEN
            NEW.kid_response_type := OLD.kid_response_type;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

-- =============================================================================
-- 6. Claiming a missed / escalating check-in
-- =============================================================================
ALTER TABLE checkin_requests
    ADD COLUMN IF NOT EXISTS claimed_by UUID REFERENCES users(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS claimed_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS claimed_by_name TEXT;

CREATE OR REPLACE FUNCTION claim_checkin_request(
    p_request_id UUID,
    p_release    BOOLEAN DEFAULT FALSE
)
RETURNS checkin_requests
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
    v_request   checkin_requests;
    v_family_id UUID;
    v_is_owner  BOOLEAN;
    v_name      TEXT;
BEGIN
    SELECT family_id INTO v_family_id FROM checkin_requests WHERE id = p_request_id;
    IF v_family_id IS NULL THEN
        RAISE EXCEPTION 'Check-in request not found' USING ERRCODE = 'no_data_found';
    END IF;

    IF NOT is_active_caregiver_of(v_family_id) THEN
        RAISE EXCEPTION 'Not authorized for this family'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    v_is_owner := EXISTS (SELECT 1 FROM families WHERE id = v_family_id AND owner_id = auth.uid());

    IF p_release THEN
        UPDATE checkin_requests
           SET claimed_by = NULL,
               claimed_at = NULL,
               claimed_by_name = NULL
         WHERE id = p_request_id
           AND (claimed_by = auth.uid() OR v_is_owner);
    ELSE
        SELECT NULLIF(btrim(display_name), '') INTO v_name FROM users WHERE id = auth.uid();
        UPDATE checkin_requests
           SET claimed_by = auth.uid(),
               claimed_at = NOW(),
               claimed_by_name = COALESCE(v_name, 'A caregiver')
         WHERE id = p_request_id
           AND status IN ('pending', 'missed')
           AND (claimed_at IS NULL OR claimed_by = auth.uid());
    END IF;

    -- Whether or not this call changed anything, hand back the row as it now
    -- stands so the caller sees who actually holds the claim.
    SELECT * INTO v_request FROM checkin_requests WHERE id = p_request_id;
    RETURN v_request;
END;
$$;

REVOKE ALL ON FUNCTION claim_checkin_request(UUID, BOOLEAN) FROM PUBLIC;
REVOKE ALL ON FUNCTION claim_checkin_request(UUID, BOOLEAN) FROM anon;
GRANT EXECUTE ON FUNCTION claim_checkin_request(UUID, BOOLEAN) TO authenticated;

COMMENT ON FUNCTION claim_checkin_request(UUID, BOOLEAN) IS
    'An active owner/co-caregiver says "I''m on it" for a pending or missed check-in (or releases their claim; the owner may release any). Returns the row as it stands.';

-- Same body as 00061, plus the claim columns (server-owned: claim_checkin_request).
CREATE OR REPLACE FUNCTION guard_checkin_requests_client_write()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT is_client_role() THEN
        RETURN NEW;
    END IF;

    IF TG_OP = 'INSERT' THEN
        IF NOT EXISTS (
            SELECT 1 FROM family_members fm
            WHERE fm.family_id = NEW.family_id
              AND fm.user_id = NEW.receiver_id
              AND fm.role = 'receiver'
              AND fm.status = 'active'
        ) THEN
            RAISE EXCEPTION 'Not an active receiver in this family'
                USING ERRCODE = 'insufficient_privilege';
        END IF;
        NEW.requested_by := auth.uid();
        NEW.status := 'pending';
        NEW.responded_at := NULL;
        NEW.escalation_step := 0;
        NEW.next_escalation_at := GREATEST(
            COALESCE(NEW.next_escalation_at, NOW()),
            NOW() + INTERVAL '15 minutes'
        );
        NEW.snoozed_until := NULL;
        NEW.snooze_count := 0;
        NEW.stood_down_at := NULL;
        NEW.stood_down_by := NULL;
        NEW.claimed_by := NULL;
        NEW.claimed_at := NULL;
        NEW.claimed_by_name := NULL;
        RETURN NEW;
    END IF;

    NEW.id := OLD.id;
    NEW.family_id := OLD.family_id;
    NEW.receiver_id := OLD.receiver_id;
    NEW.requested_by := OLD.requested_by;
    NEW.type := OLD.type;
    NEW.created_at := OLD.created_at;
    NEW.escalation_step := OLD.escalation_step;
    NEW.next_escalation_at := OLD.next_escalation_at;
    NEW.snoozed_until := OLD.snoozed_until;
    NEW.snooze_count := OLD.snooze_count;
    NEW.slot_key := OLD.slot_key;
    -- Server-owned since 00055 (cancel-escalation); must stay pinned.
    NEW.stood_down_at := OLD.stood_down_at;
    NEW.stood_down_by := OLD.stood_down_by;
    -- Server-owned (claim_checkin_request).
    NEW.claimed_by := OLD.claimed_by;
    NEW.claimed_at := OLD.claimed_at;
    NEW.claimed_by_name := OLD.claimed_by_name;
    RETURN NEW;
END;
$$;

-- =============================================================================
-- 7. A caregiver who leaves (or is removed) gives up their claims
-- =============================================================================
-- "Tom is on it" must not outlive Tom's membership: the others would keep
-- waiting on someone who no longer gets the alerts. Releases their claim on
-- open (pending / missed) check-in requests and on the last day's urgent
-- alerts in that family. Older handled alerts keep "Handled by Tom" as history.
CREATE OR REPLACE FUNCTION release_claims_for_departed_member()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
    v_family UUID;
    v_user UUID;
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_family := OLD.family_id;
        v_user := OLD.user_id;
    ELSE
        IF NOT (NEW.status = 'deactivated' AND OLD.status IS DISTINCT FROM 'deactivated') THEN
            RETURN NEW;
        END IF;
        v_family := NEW.family_id;
        v_user := NEW.user_id;
    END IF;

    UPDATE checkin_requests
       SET claimed_by = NULL,
           claimed_at = NULL,
           claimed_by_name = NULL
     WHERE family_id = v_family
       AND claimed_by = v_user
       AND status IN ('pending', 'missed');

    UPDATE alerts
       SET acknowledged_by = NULL,
           acknowledged_at = NULL,
           acknowledged_by_name = NULL
     WHERE family_id = v_family
       AND acknowledged_by = v_user
       AND created_at > NOW() - INTERVAL '24 hours';

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS family_members_release_claims_on_leave ON family_members;
CREATE TRIGGER family_members_release_claims_on_leave
    AFTER UPDATE OF status OR DELETE ON family_members
    FOR EACH ROW EXECUTE FUNCTION release_claims_for_departed_member();

COMMIT;

-- Verification:
--   SELECT proname FROM pg_proc
--    WHERE proname IN ('is_active_caregiver_of', 'guard_care_note_delete');       -- 2 rows
--   SELECT tgname FROM pg_trigger WHERE tgname = 'trg_care_notes_guard_delete';     -- 1 row
--   SELECT prosrc LIKE '%acknowledged_at IS NULL%' FROM pg_proc
--    WHERE proname = 'acknowledge_alert';                                          -- true
--   SELECT column_name FROM information_schema.columns
--    WHERE table_name = 'checkin_requests' AND column_name LIKE 'claimed%';       -- 3 rows
--   SELECT proname FROM pg_proc WHERE proname = 'claim_checkin_request';           -- 1 row
--   SELECT tgname FROM pg_trigger WHERE tgname = 'family_members_release_claims_on_leave'; -- 1 row
