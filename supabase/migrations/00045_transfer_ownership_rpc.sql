-- =============================================================================
-- Migration: 00045_transfer_ownership_rpc
-- Story: US-IOS053 — Make Transfer Ownership atomic
--
-- The iOS client previously transferred ownership with three separate writes
-- (families.owner_id, new member -> owner, old owner -> viewer). A crash or
-- network drop between writes could leave the family with two owners, or with
-- families.owner_id pointing at a user whose family_members.role was never
-- updated — an unrecoverable state from the UI. This wraps the whole transfer
-- in one SECURITY DEFINER RPC so it succeeds or fails as a unit, and enforces
-- that only the current owner can perform it.
--
-- Backward-compatibility (per CLAUDE.md): additive only.
--   * One new SECURITY DEFINER RPC; no existing signature changed.
--   * Older clients that still do the three-write path keep working; they just
--     don't get atomicity. New clients call the RPC.
-- =============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION transfer_family_ownership(
    p_family_id UUID,
    p_new_owner_user_id UUID
)
RETURNS void AS $$
DECLARE
    v_family families;
    v_caller UUID := auth.uid();
BEGIN
    IF v_caller IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = 'insufficient_privilege';
    END IF;

    -- Lock the family row so a concurrent transfer can't interleave.
    SELECT * INTO v_family
    FROM families
    WHERE id = p_family_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Family not found' USING ERRCODE = 'no_data_found';
    END IF;

    -- Only the current owner may transfer ownership.
    IF v_family.owner_id <> v_caller THEN
        RAISE EXCEPTION 'Only the current owner can transfer ownership'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    -- Transferring to yourself is a no-op that would corrupt roles below.
    IF p_new_owner_user_id = v_caller THEN
        RAISE EXCEPTION 'You are already the owner' USING ERRCODE = 'invalid_parameter_value';
    END IF;

    -- The new owner must be an active member of this family.
    IF NOT EXISTS (
        SELECT 1 FROM family_members
        WHERE family_id = p_family_id
          AND user_id = p_new_owner_user_id
          AND status = 'active'
    ) THEN
        RAISE EXCEPTION 'New owner must be an active member of this family'
            USING ERRCODE = 'foreign_key_violation';
    END IF;

    -- 1. Point the family at the new owner.
    UPDATE families
    SET owner_id = p_new_owner_user_id
    WHERE id = p_family_id;

    -- 2. Promote the new owner's membership.
    UPDATE family_members
    SET role = 'owner'
    WHERE family_id = p_family_id
      AND user_id = p_new_owner_user_id;

    -- 3. Demote the previous owner to viewer.
    UPDATE family_members
    SET role = 'viewer'
    WHERE family_id = p_family_id
      AND user_id = v_caller;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION transfer_family_ownership(UUID, UUID) TO authenticated;

COMMIT;
