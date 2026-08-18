-- =============================================================================
-- Migration: 00050_invite_tokens_used_by_on_delete
-- Story: US-LEG001 — Account deletion no longer throws for members who joined
--                    via an invite link
--
-- invite_tokens.used_by was declared inline as `used_by UUID REFERENCES
-- users(id)` (00001_create_core_tables.sql:163) with no ON DELETE clause, so it
-- defaults to NO ACTION. Every other user-referencing foreign key in the schema
-- specifies ON DELETE CASCADE; this one is the sole exception.
--
-- Consequence: delete_user_account() ends with `DELETE FROM users WHERE id =
-- p_user_id`, which raises a foreign-key violation for any user whose id still
-- appears in invite_tokens.used_by — that is, anyone who joined a family by
-- redeeming an invite. Owners usually escape it because the function runs
-- `DELETE FROM families WHERE owner_id = p_user_id` first and that cascades the
-- family's invite_tokens away; invited Receivers and Viewers do not own the
-- family, so their redeemed token survives and blocks the delete. The user sees
-- the generic error alert (ios/DailyOK/Views/Settings/SettingsView.swift:315)
-- after typing DELETE to confirm.
--
-- That makes an advertised right unusable: Privacy.tsx:289 offers Deletion /
-- Erasure and Terms.tsx:286 says "You may delete your account at any time from
-- the app's settings" (GDPR Art. 17, CCPA 1798.105).
--
-- SET NULL rather than CASCADE is deliberate. used_by is an audit breadcrumb on
-- a token belonging to someone else's family; erasing the departing user should
-- clear the reference to them, not delete the family owner's token record.
--
-- Backward-compatibility (per CLAUDE.md): additive and forward-only.
--   * No column renamed, no table dropped, no type changed.
--   * used_by stays UUID and stays nullable — it was already nullable, and rows
--     with used_by IS NULL (unredeemed invites) are already the common case, so
--     no client can be surprised by a NULL here.
--   * No RPC signature changes; no on-the-wire JSON shape changes.
--   * Existing rows are untouched; only the constraint's delete action changes.
-- =============================================================================

BEGIN;

-- Drop the existing FK by its catalog name rather than assuming the default
-- `invite_tokens_used_by_fkey`, so this is safe if the constraint was ever
-- created or restored under a different name.
DO $$
DECLARE
    v_constraint_name TEXT;
BEGIN
    SELECT con.conname
      INTO v_constraint_name
      FROM pg_constraint con
      JOIN pg_class rel        ON rel.oid = con.conrelid
      JOIN pg_namespace nsp    ON nsp.oid = rel.relnamespace
      JOIN pg_attribute att    ON att.attrelid = con.conrelid
                              AND att.attnum = con.conkey[1]
     WHERE con.contype = 'f'
       AND nsp.nspname = 'public'
       AND rel.relname = 'invite_tokens'
       AND att.attname = 'used_by'
       AND array_length(con.conkey, 1) = 1;

    IF v_constraint_name IS NULL THEN
        RAISE NOTICE 'No FK found on invite_tokens.used_by; nothing to drop.';
    ELSE
        EXECUTE format(
            'ALTER TABLE public.invite_tokens DROP CONSTRAINT %I',
            v_constraint_name
        );
    END IF;
END $$;

ALTER TABLE public.invite_tokens
    ADD CONSTRAINT invite_tokens_used_by_fkey
    FOREIGN KEY (used_by)
    REFERENCES public.users(id)
    ON DELETE SET NULL;

-- =============================================================================
-- VERIFICATION
-- confdeltype: 'n' = SET NULL, 'c' = CASCADE, 'a' = NO ACTION, 'r' = RESTRICT.
-- Expect exactly one row, with delete_action = 'n'.
-- =============================================================================

DO $$
DECLARE
    v_delete_action "char";
BEGIN
    SELECT con.confdeltype
      INTO v_delete_action
      FROM pg_constraint con
      JOIN pg_class rel     ON rel.oid = con.conrelid
      JOIN pg_namespace nsp ON nsp.oid = rel.relnamespace
      JOIN pg_attribute att ON att.attrelid = con.conrelid
                           AND att.attnum = con.conkey[1]
     WHERE con.contype = 'f'
       AND nsp.nspname = 'public'
       AND rel.relname = 'invite_tokens'
       AND att.attname = 'used_by';

    IF v_delete_action IS DISTINCT FROM 'n' THEN
        RAISE EXCEPTION
            'invite_tokens.used_by FK delete action is %, expected n (SET NULL)',
            COALESCE(v_delete_action::text, 'missing');
    END IF;

    RAISE NOTICE 'OK: invite_tokens.used_by is ON DELETE SET NULL';
END $$;

SELECT
    con.conname                         AS constraint_name,
    con.confdeltype                     AS delete_action,
    (con.confdeltype = 'n')             AS is_set_null
  FROM pg_constraint con
  JOIN pg_class rel     ON rel.oid = con.conrelid
  JOIN pg_namespace nsp ON nsp.oid = rel.relnamespace
  JOIN pg_attribute att ON att.attrelid = con.conrelid
                       AND att.attnum = con.conkey[1]
 WHERE con.contype = 'f'
   AND nsp.nspname = 'public'
   AND rel.relname = 'invite_tokens'
   AND att.attname = 'used_by';

COMMIT;
