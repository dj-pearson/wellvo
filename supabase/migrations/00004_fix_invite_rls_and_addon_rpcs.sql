-- Migration: 00004_fix_invite_rls_and_addon_rpcs
-- Fixes: open invite token read policy, adds add-on RPC functions

-- =============================================================================
-- FIX: Restrict invite_tokens read access
-- Previously allowed anyone to read all invite tokens (USING TRUE).
-- Now only family owners can list their invites; token lookup is done
-- server-side via service role in edge functions.
-- =============================================================================

DROP POLICY IF EXISTS "Anyone can read invite tokens by token value" ON invite_tokens;

-- Only family owners can read their own invite tokens
CREATE POLICY "Owners can read own invite tokens"
    ON invite_tokens FOR SELECT
    USING (is_family_owner(family_id));

-- =============================================================================
-- ADD-ON RPC FUNCTIONS
-- Used by the subscription-webhook edge function to increment slots
-- =============================================================================

CREATE OR REPLACE FUNCTION increment_max_receivers(p_owner_id UUID)
RETURNS void AS $$
BEGIN
    UPDATE families
    SET max_receivers = max_receivers + 1
    WHERE owner_id = p_owner_id
      AND subscription_tier IN ('family', 'family_plus');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION increment_max_viewers(p_owner_id UUID)
RETURNS void AS $$
BEGIN
    UPDATE families
    SET max_viewers = max_viewers + 1
    WHERE owner_id = p_owner_id
      AND subscription_tier IN ('family', 'family_plus');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
