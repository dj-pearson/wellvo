-- Daily OK: Receiver home — preferences that save, leaving a family openly,
-- "someone is on it" for a help request, and honest check-in provenance.
-- Migration: 00061_receiver_home_integrity
--
-- ─── WHAT AND WHY ────────────────────────────────────────────────────────────
-- 1. set_my_receiver_display_prefs(): a receiver's own Simple Mode and Spoken
--    Confirmation. receiver_settings only has "Owners can manage" (FOR ALL)
--    and "Receivers can read own settings" (SELECT). The iOS menu toggles and
--    the "Make check-in easier?" offer PATCHed the row as the receiver: RLS
--    matched 0 rows, PostgREST answered 204, the app played a success haptic,
--    and the next load put the old value back. A broad receiver UPDATE policy
--    would also open home coordinates, schedule and escalation settings, so
--    this RPC writes those two columns only, on the caller's own row.
--
-- 2. leave_family(): a receiver or co-caregiver leaves a family and the
--    family is told. Until now the only exits were Sign Out (escalations keep
--    firing for someone who opted out) or deleting the account. The membership
--    is deactivated — the 00058 trigger stands down its pending requests, as
--    when an owner removes someone — the receiver's schedule is switched off,
--    and an alert row tells the owner's dashboard. An owner can't leave their
--    own family this way (transfer ownership first).
--
-- 3. my_open_help_request(): after "I need help" the receiver saw "You're all
--    set!" and could not know whether anyone had seen it. Receivers can't read
--    alerts (owner/viewer policies only, 00006/00039). This returns only the
--    caller's own latest help / call-me alert from the last 12 hours and who,
--    if anyone, has taken it on (acknowledge_alert_v2, 00039).
--
-- 4. checkins.received_at: when the server received a check-in. checked_in_at
--    can legitimately be up to 7 days old (offline replay, US-IOS147), and a
--    direct INSERT may backdate it the same way, so nothing recorded that a
--    row arrived late. New nullable column; existing rows stay NULL (unknown),
--    new rows get now(), and a client insert can't choose it.
--
-- 5. Client INSERT guards (the 00051 pattern; silent for service_role):
--    * checkin_requests: RLS lets an owner insert for any receiver_id, with
--      the escalation step, clock and snooze counters of their choosing, and
--      the cron then pushes reminders to that user. No shipped client inserts
--      requests (on-demand-checkin and dispatch run as service_role). A client
--      insert now needs an active receiver of that family and starts fresh.
--    * location_updates / wellness_signals: INSERT only checked
--      receiver_id = auth.uid(). Now the caller must be an active receiver of
--      that family; a client-supplied distance_from_home_meters (which the
--      geofence check trusts) is discarded; a wellness date must be within a
--      day of today. No shipped client inserts location_updates (report-
--      location runs as service_role); iOS upserts today's wellness signal as
--      an active receiver, which still passes.
--
-- ─── COMPATIBILITY (CLAUDE.md §A) ────────────────────────────────────────────
-- New functions, one nullable column, trigger bodies for client-role inserts
-- no shipped client makes (or makes only in the allowed shape). No policy is
-- added, removed or changed; no existing RPC signature changes.
-- Idempotent: safe to replay.
-- ─────────────────────────────────────────────────────────────────────────────

BEGIN;

-- =============================================================================
-- 1. Receiver display preferences
-- =============================================================================
CREATE OR REPLACE FUNCTION set_my_receiver_display_prefs(
    p_family_id UUID,
    p_simple_mode BOOLEAN DEFAULT NULL,
    p_audio_confirmation BOOLEAN DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
    v_member_id UUID;
    v_simple BOOLEAN;
    v_audio BOOLEAN;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Not signed in' USING ERRCODE = 'insufficient_privilege';
    END IF;

    SELECT fm.id INTO v_member_id
    FROM family_members fm
    WHERE fm.family_id = p_family_id
      AND fm.user_id = auth.uid()
      AND fm.role = 'receiver'
      AND fm.status = 'active'
    LIMIT 1;

    IF v_member_id IS NULL THEN
        RAISE EXCEPTION 'Not a receiver in this family' USING ERRCODE = 'insufficient_privilege';
    END IF;

    UPDATE receiver_settings
    SET simple_mode = COALESCE(p_simple_mode, simple_mode),
        audio_confirmation_enabled = COALESCE(p_audio_confirmation, audio_confirmation_enabled)
    WHERE family_member_id = v_member_id
    RETURNING simple_mode, audio_confirmation_enabled INTO v_simple, v_audio;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No settings for this receiver' USING ERRCODE = 'no_data_found';
    END IF;

    RETURN jsonb_build_object(
        'simple_mode', v_simple,
        'audio_confirmation_enabled', v_audio
    );
END;
$$;

REVOKE ALL ON FUNCTION set_my_receiver_display_prefs(UUID, BOOLEAN, BOOLEAN) FROM PUBLIC;
REVOKE ALL ON FUNCTION set_my_receiver_display_prefs(UUID, BOOLEAN, BOOLEAN) FROM anon;
GRANT EXECUTE ON FUNCTION set_my_receiver_display_prefs(UUID, BOOLEAN, BOOLEAN) TO authenticated;

COMMENT ON FUNCTION set_my_receiver_display_prefs(UUID, BOOLEAN, BOOLEAN) IS
    'A receiver sets their own Simple Mode / Spoken Confirmation (NULL = unchanged). Touches only those two columns on the caller''s own active receiver row.';

-- =============================================================================
-- 2. Leave a family
-- =============================================================================
CREATE OR REPLACE FUNCTION leave_family(p_family_id UUID)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
    v_member family_members;
    v_owner UUID;
    v_name TEXT;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Not signed in' USING ERRCODE = 'insufficient_privilege';
    END IF;

    SELECT owner_id INTO v_owner FROM families WHERE id = p_family_id;
    IF v_owner IS NULL THEN
        RAISE EXCEPTION 'Family not found' USING ERRCODE = 'no_data_found';
    END IF;
    IF v_owner = auth.uid() THEN
        RAISE EXCEPTION 'The owner can''t leave; transfer the family first'
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    SELECT * INTO v_member
    FROM family_members
    WHERE family_id = p_family_id
      AND user_id = auth.uid()
      AND status = 'active'
      AND role IN ('receiver', 'viewer')
    LIMIT 1
    FOR UPDATE;

    IF NOT FOUND THEN
        -- Already gone (a retry after a lost answer): nothing to do.
        RETURN jsonb_build_object('left', false, 'already_left', true);
    END IF;

    -- Deactivating fires stand_down_requests_for_departed_member (00058), so
    -- a pending check-in doesn't go on escalating to the family.
    UPDATE family_members SET status = 'deactivated' WHERE id = v_member.id;

    IF v_member.role = 'receiver' THEN
        UPDATE receiver_settings SET is_active = FALSE WHERE family_member_id = v_member.id;
    END IF;

    -- 'User' is the placeholder a profile gets before a name is set.
    SELECT COALESCE(NULLIF(NULLIF(TRIM(display_name), ''), 'User'), 'A family member') INTO v_name
    FROM users WHERE id = auth.uid();
    v_name := COALESCE(v_name, 'A family member');

    -- Shown on the owner's (and co-caregivers') dashboard. Not an urgent type.
    INSERT INTO alerts (family_id, receiver_id, type, title, message, data)
    VALUES (
        p_family_id,
        auth.uid(),
        'member_left',
        'Left the family',
        CASE WHEN v_member.role = 'receiver'
             THEN v_name || ' left your Daily OK check-ins. You won''t get check-ins or missed-check-in alerts for them any more.'
             ELSE v_name || ' is no longer a co-caregiver in your Daily OK family.'
        END,
        jsonb_build_object('role', v_member.role, 'left_at', NOW())
    );

    RETURN jsonb_build_object('left', true, 'role', v_member.role);
END;
$$;

REVOKE ALL ON FUNCTION leave_family(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION leave_family(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION leave_family(UUID) TO authenticated;

COMMENT ON FUNCTION leave_family(UUID) IS
    'The caller (an active receiver or co-caregiver, never the owner) leaves the family: membership deactivated, pending requests stood down (00058 trigger), schedule off, and a member_left alert for the family.';

-- =============================================================================
-- 3. The receiver's own open help request
-- =============================================================================
CREATE OR REPLACE FUNCTION my_open_help_request(p_family_id UUID)
RETURNS JSONB
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public AS $$
    SELECT jsonb_build_object(
        'alert_id', a.id,
        'type', a.type,
        'created_at', a.created_at,
        'acknowledged_at', a.acknowledged_at,
        'acknowledged_by_name', a.acknowledged_by_name
    )
    FROM alerts a
    WHERE a.family_id = p_family_id
      AND a.receiver_id = auth.uid()
      AND a.type IN ('need_help', 'call_me')
      AND a.created_at > NOW() - INTERVAL '12 hours'
      AND EXISTS (
          SELECT 1 FROM family_members fm
          WHERE fm.family_id = p_family_id
            AND fm.user_id = auth.uid()
            AND fm.role = 'receiver'
            AND fm.status = 'active'
      )
    ORDER BY a.created_at DESC
    LIMIT 1;
$$;

REVOKE ALL ON FUNCTION my_open_help_request(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION my_open_help_request(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION my_open_help_request(UUID) TO authenticated;

COMMENT ON FUNCTION my_open_help_request(UUID) IS
    'The calling receiver''s latest help / call-me alert in the last 12 hours and who has taken it on, or NULL.';

-- =============================================================================
-- 4. When a check-in actually arrived
-- =============================================================================
-- Added without a default so existing rows stay NULL ("unknown") instead of
-- all reading as received at migration time; the default applies to new rows.
ALTER TABLE checkins ADD COLUMN IF NOT EXISTS received_at TIMESTAMPTZ;
ALTER TABLE checkins ALTER COLUMN received_at SET DEFAULT NOW();

COMMENT ON COLUMN checkins.received_at IS
    'Server time the check-in arrived. checked_in_at can be up to 7 days earlier (offline replay). NULL for rows before 00061.';

-- Same body as 00057, plus received_at: server-set on a client insert, pinned
-- on update.
CREATE OR REPLACE FUNCTION guard_checkins_client_write()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT is_client_role() THEN
        RETURN NEW;
    END IF;

    IF TG_OP = 'INSERT' THEN
        IF NOT is_family_member(NEW.family_id) THEN
            RAISE EXCEPTION 'Not a member of this family'
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

DROP TRIGGER IF EXISTS checkins_guard_client_write ON checkins;
CREATE TRIGGER checkins_guard_client_write
    BEFORE INSERT OR UPDATE ON checkins
    FOR EACH ROW EXECUTE FUNCTION guard_checkins_client_write();

-- =============================================================================
-- 5a. checkin_requests: a client insert targets a real receiver and starts fresh
-- =============================================================================
-- Same body as 00055 for UPDATE (00051 plus the stand-down columns); the
-- INSERT branch is new.
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
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS checkin_requests_guard_client_write ON checkin_requests;
CREATE TRIGGER checkin_requests_guard_client_write
    BEFORE INSERT OR UPDATE ON checkin_requests
    FOR EACH ROW EXECUTE FUNCTION guard_checkin_requests_client_write();

-- =============================================================================
-- 5b. location_updates / wellness_signals: only an active receiver of that
--     family, and no client-chosen distance from home
-- =============================================================================
CREATE OR REPLACE FUNCTION is_active_receiver_of(p_family_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public AS $$
    SELECT EXISTS (
        SELECT 1 FROM family_members fm
        WHERE fm.family_id = p_family_id
          AND fm.user_id = auth.uid()
          AND fm.role = 'receiver'
          AND fm.status = 'active'
    );
$$;

REVOKE ALL ON FUNCTION is_active_receiver_of(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION is_active_receiver_of(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION is_active_receiver_of(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION guard_location_updates_client_write()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT is_client_role() THEN
        RETURN NEW;
    END IF;
    IF NOT is_active_receiver_of(NEW.family_id) THEN
        RAISE EXCEPTION 'Not an active receiver in this family'
            USING ERRCODE = 'insufficient_privilege';
    END IF;
    -- check_geofence_alerts trusts this column. report-location computes it
    -- server-side; a direct insert doesn't get to choose it.
    NEW.distance_from_home_meters := NULL;
    NEW.recorded_at := NOW();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS location_updates_guard_client_write ON location_updates;
CREATE TRIGGER location_updates_guard_client_write
    BEFORE INSERT ON location_updates
    FOR EACH ROW EXECUTE FUNCTION guard_location_updates_client_write();

CREATE OR REPLACE FUNCTION guard_wellness_signals_client_write()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT is_client_role() THEN
        RETURN NEW;
    END IF;
    IF NOT is_active_receiver_of(NEW.family_id) THEN
        RAISE EXCEPTION 'Not an active receiver in this family'
            USING ERRCODE = 'insufficient_privilege';
    END IF;
    -- The receiver's local "today" is within a day of the server's.
    IF NEW.signal_date < CURRENT_DATE - 1 OR NEW.signal_date > CURRENT_DATE + 1 THEN
        RAISE EXCEPTION 'signal_date must be today'
            USING ERRCODE = 'invalid_parameter_value';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS wellness_signals_guard_client_write ON wellness_signals;
CREATE TRIGGER wellness_signals_guard_client_write
    BEFORE INSERT OR UPDATE ON wellness_signals
    FOR EACH ROW EXECUTE FUNCTION guard_wellness_signals_client_write();

COMMIT;
