-- =============================================================================
-- Migration 00011: Auto-create public.users profile on auth.users insert
--
-- When a user is created in auth.users (via sign-up, Supabase dashboard, or
-- direct SQL), this trigger automatically creates a matching row in
-- public.users so the app never encounters a missing profile.
-- =============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.users (id, email, display_name, timezone)
    VALUES (
        NEW.id,
        COALESCE(NEW.email, ''),
        COALESCE(NEW.raw_user_meta_data ->> 'display_name', NEW.raw_user_meta_data ->> 'full_name', 'User'),
        COALESCE(NEW.raw_user_meta_data ->> 'timezone', 'America/New_York')
    )
    ON CONFLICT (id) DO NOTHING;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Drop if exists to make migration re-runnable
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_new_auth_user();

COMMIT;
