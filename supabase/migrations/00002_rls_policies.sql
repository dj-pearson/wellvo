-- Wellvo Row Level Security Policies
-- Migration: 00002_rls_policies

-- Enable RLS on all tables
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE families ENABLE ROW LEVEL SECURITY;
ALTER TABLE family_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE receiver_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE checkins ENABLE ROW LEVEL SECURITY;
ALTER TABLE checkin_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE push_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE notification_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE invite_tokens ENABLE ROW LEVEL SECURITY;

-- =============================================================================
-- HELPER FUNCTIONS
-- =============================================================================

-- Check if the current user is an owner of a given family
CREATE OR REPLACE FUNCTION is_family_owner(p_family_id UUID)
RETURNS BOOLEAN AS $$
    SELECT EXISTS (
        SELECT 1 FROM families
        WHERE id = p_family_id AND owner_id = auth.uid()
    );
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- Check if the current user is a member of a given family
CREATE OR REPLACE FUNCTION is_family_member(p_family_id UUID)
RETURNS BOOLEAN AS $$
    SELECT EXISTS (
        SELECT 1 FROM family_members
        WHERE family_id = p_family_id
          AND user_id = auth.uid()
          AND status = 'active'
    );
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- Get the family ID(s) for the current user
CREATE OR REPLACE FUNCTION user_family_ids()
RETURNS SETOF UUID AS $$
    SELECT family_id FROM family_members
    WHERE user_id = auth.uid() AND status = 'active';
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- =============================================================================
-- USERS POLICIES
-- =============================================================================

CREATE POLICY "Users can read own profile"
    ON users FOR SELECT
    USING (id = auth.uid());

CREATE POLICY "Users can update own profile"
    ON users FOR UPDATE
    USING (id = auth.uid());

CREATE POLICY "Users can insert own profile"
    ON users FOR INSERT
    WITH CHECK (id = auth.uid());

-- Owners/viewers can see family members' profiles
CREATE POLICY "Family members can read each other"
    ON users FOR SELECT
    USING (
        id IN (
            SELECT fm.user_id FROM family_members fm
            WHERE fm.family_id IN (SELECT user_family_ids())
              AND fm.status = 'active'
        )
    );

-- =============================================================================
-- FAMILIES POLICIES
-- =============================================================================

CREATE POLICY "Owners can read own families"
    ON families FOR SELECT
    USING (owner_id = auth.uid() OR is_family_member(id));

CREATE POLICY "Owners can create families"
    ON families FOR INSERT
    WITH CHECK (owner_id = auth.uid());

CREATE POLICY "Owners can update own families"
    ON families FOR UPDATE
    USING (owner_id = auth.uid());

-- =============================================================================
-- FAMILY_MEMBERS POLICIES
-- =============================================================================

CREATE POLICY "Members can read family members in their family"
    ON family_members FOR SELECT
    USING (is_family_member(family_id) OR is_family_owner(family_id));

CREATE POLICY "Owners can add family members"
    ON family_members FOR INSERT
    WITH CHECK (is_family_owner(family_id));

CREATE POLICY "Owners can update family members"
    ON family_members FOR UPDATE
    USING (is_family_owner(family_id));

CREATE POLICY "Owners can remove family members"
    ON family_members FOR DELETE
    USING (is_family_owner(family_id));

-- =============================================================================
-- RECEIVER_SETTINGS POLICIES
-- =============================================================================

CREATE POLICY "Owners can manage receiver settings"
    ON receiver_settings FOR ALL
    USING (
        family_member_id IN (
            SELECT fm.id FROM family_members fm
            WHERE is_family_owner(fm.family_id)
        )
    );

CREATE POLICY "Receivers can read own settings"
    ON receiver_settings FOR SELECT
    USING (
        family_member_id IN (
            SELECT fm.id FROM family_members fm
            WHERE fm.user_id = auth.uid()
        )
    );

-- =============================================================================
-- CHECKINS POLICIES
-- =============================================================================

CREATE POLICY "Receivers can insert own checkins"
    ON checkins FOR INSERT
    WITH CHECK (receiver_id = auth.uid());

CREATE POLICY "Receivers can read own checkins"
    ON checkins FOR SELECT
    USING (receiver_id = auth.uid());

CREATE POLICY "Family owners and viewers can read family checkins"
    ON checkins FOR SELECT
    USING (is_family_member(family_id));

-- =============================================================================
-- CHECKIN_REQUESTS POLICIES
-- =============================================================================

CREATE POLICY "Receivers can read own requests"
    ON checkin_requests FOR SELECT
    USING (receiver_id = auth.uid());

CREATE POLICY "Owners can read family requests"
    ON checkin_requests FOR SELECT
    USING (is_family_owner(family_id));

CREATE POLICY "Owners can create requests"
    ON checkin_requests FOR INSERT
    WITH CHECK (is_family_owner(family_id));

-- =============================================================================
-- PUSH_TOKENS POLICIES
-- =============================================================================

CREATE POLICY "Users can manage own push tokens"
    ON push_tokens FOR ALL
    USING (user_id = auth.uid());

-- =============================================================================
-- NOTIFICATION_LOG POLICIES
-- =============================================================================

CREATE POLICY "Users can read own notifications"
    ON notification_log FOR SELECT
    USING (user_id = auth.uid());

-- =============================================================================
-- INVITE_TOKENS POLICIES
-- =============================================================================

CREATE POLICY "Owners can manage invite tokens"
    ON invite_tokens FOR ALL
    USING (is_family_owner(family_id));

CREATE POLICY "Anyone can read invite tokens by token value"
    ON invite_tokens FOR SELECT
    USING (TRUE);

-- =============================================================================
-- SERVICE ROLE BYPASS
-- Edge functions use the service role key and bypass RLS automatically.
-- =============================================================================
