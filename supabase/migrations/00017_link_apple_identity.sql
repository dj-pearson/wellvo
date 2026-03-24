-- Migration: Add RPC function to link an Apple identity to an existing user
-- This enables the "Link Apple ID" feature where users who signed up with
-- email/phone can later link their Apple ID for Sign in with Apple.

BEGIN;

-- Function to safely insert an Apple identity into auth.identities.
-- Called by the link-apple-id edge function with service role privileges.
CREATE OR REPLACE FUNCTION public.link_apple_identity(
    p_user_id UUID,
    p_provider_id TEXT,
    p_identity_data JSONB
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = auth, public
AS $$
BEGIN
    -- Ensure the user exists in auth.users
    IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_user_id) THEN
        RAISE EXCEPTION 'User not found';
    END IF;

    -- Ensure this Apple ID isn't already linked to any user
    IF EXISTS (
        SELECT 1 FROM auth.identities
        WHERE provider = 'apple' AND provider_id = p_provider_id
    ) THEN
        RAISE EXCEPTION 'Apple ID already linked to an account';
    END IF;

    -- Insert the identity record
    INSERT INTO auth.identities (
        id,
        user_id,
        provider,
        provider_id,
        identity_data,
        last_sign_in_at,
        created_at,
        updated_at
    ) VALUES (
        gen_random_uuid(),
        p_user_id,
        'apple',
        p_provider_id,
        p_identity_data,
        NOW(),
        NOW(),
        NOW()
    );

    -- Update the user's raw_app_meta_data to include apple in providers
    UPDATE auth.users
    SET raw_app_meta_data = raw_app_meta_data
        || jsonb_build_object(
            'providers',
            CASE
                WHEN raw_app_meta_data->'providers' IS NULL THEN '["apple"]'::jsonb
                WHEN NOT (raw_app_meta_data->'providers' @> '"apple"') THEN
                    (raw_app_meta_data->'providers') || '"apple"'::jsonb
                ELSE raw_app_meta_data->'providers'
            END
        ),
        updated_at = NOW()
    WHERE id = p_user_id;
END;
$$;

-- Only allow the service role (via edge functions) to call this
REVOKE ALL ON FUNCTION public.link_apple_identity(UUID, TEXT, JSONB) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.link_apple_identity(UUID, TEXT, JSONB) FROM anon;
REVOKE ALL ON FUNCTION public.link_apple_identity(UUID, TEXT, JSONB) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.link_apple_identity(UUID, TEXT, JSONB) TO service_role;

-- Helper function to check if a user has an Apple identity linked
CREATE OR REPLACE FUNCTION public.has_apple_identity(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = auth, public
AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM auth.identities
        WHERE user_id = p_user_id AND provider = 'apple'
    );
END;
$$;

-- Allow authenticated users to check their own Apple link status
GRANT EXECUTE ON FUNCTION public.has_apple_identity(UUID) TO authenticated;

COMMIT;
