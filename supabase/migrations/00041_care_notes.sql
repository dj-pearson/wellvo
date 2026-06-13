-- Daily OK: Shared care notes / family timeline per receiver
-- Migration: 00041_care_notes
--
-- US-IOS016. A lightweight shared notes feed per receiver so co-caregivers can
-- record context ("doctor visit Tuesday", "traveling this week", "left phone at
-- home") that everyone on the care team can see. Turns Daily OK from a single
-- signal into a shared caregiving hub.
--
-- Fully ADDITIVE per CLAUDE.md: a brand-new table with its own RLS, added to
-- the realtime publication. No existing table/policy/function is touched.

BEGIN;

CREATE TABLE IF NOT EXISTS care_notes (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    family_id   UUID NOT NULL REFERENCES families(id) ON DELETE CASCADE,
    receiver_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    author_id   UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    -- Denormalized so the feed (and realtime INSERT events) can show the
    -- author without a join. Kept in sync only on insert — display only.
    author_name TEXT NOT NULL DEFAULT 'A caregiver',
    body        TEXT NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_care_notes_receiver
    ON care_notes(family_id, receiver_id, created_at DESC);

-- Keep updated_at fresh on edit.
CREATE OR REPLACE FUNCTION touch_care_note_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_care_notes_touch ON care_notes;
CREATE TRIGGER trg_care_notes_touch
    BEFORE UPDATE ON care_notes
    FOR EACH ROW EXECUTE FUNCTION touch_care_note_updated_at();

-- =============================================================================
-- RLS — scoped to the care team (active owner / viewer of the family).
-- Receivers are intentionally excluded: notes are caregiver-side context.
-- =============================================================================
ALTER TABLE care_notes ENABLE ROW LEVEL SECURITY;

-- Helper predicate: caller is an active owner/viewer of the given family.
-- Inlined into each policy (no SECURITY DEFINER function needed).

-- Read: any active caregiver in the family.
CREATE POLICY "Caregivers read family care notes"
    ON care_notes FOR SELECT
    USING (
        family_id IN (
            SELECT family_id FROM family_members
            WHERE user_id = auth.uid()
              AND role IN ('owner', 'viewer')
              AND status = 'active'
        )
    );

-- Insert: active caregiver, authoring as themselves.
CREATE POLICY "Caregivers add own care notes"
    ON care_notes FOR INSERT
    WITH CHECK (
        author_id = auth.uid()
        AND family_id IN (
            SELECT family_id FROM family_members
            WHERE user_id = auth.uid()
              AND role IN ('owner', 'viewer')
              AND status = 'active'
        )
    );

-- Update: authors may edit their own notes.
CREATE POLICY "Authors edit own care notes"
    ON care_notes FOR UPDATE
    USING (author_id = auth.uid())
    WITH CHECK (author_id = auth.uid());

-- Delete: the author, or the family owner (moderation).
CREATE POLICY "Author or owner deletes care notes"
    ON care_notes FOR DELETE
    USING (
        author_id = auth.uid()
        OR family_id IN (SELECT id FROM families WHERE owner_id = auth.uid())
    );

-- =============================================================================
-- Realtime — stream INSERT/UPDATE/DELETE to co-caregivers.
-- =============================================================================
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime'
    ) THEN
        CREATE PUBLICATION supabase_realtime;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime'
          AND schemaname = 'public'
          AND tablename  = 'care_notes'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.care_notes;
    END IF;
END $$;

ALTER TABLE public.care_notes REPLICA IDENTITY FULL;

COMMIT;

-- Verification:
--   SELECT tablename FROM pg_publication_tables WHERE tablename = 'care_notes';
--   SELECT policyname FROM pg_policies WHERE tablename = 'care_notes';
