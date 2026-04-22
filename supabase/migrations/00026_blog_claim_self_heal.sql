-- Daily OK Blog — Self-healing claim for stale generations
-- Migration: 00026_blog_claim_self_heal
--
-- If a generation crashes or its container is killed mid-run, the claimed
-- row stays in 'generating' state forever with no way to recover without
-- manual SQL. This updates claim_next_blog_title() to first reset any
-- generating rows older than 15 minutes back to 'pending' before claiming
-- the next one. 15 minutes is well beyond any realistic generation time
-- (real gens run 30–90 seconds) but tight enough to recover quickly.

BEGIN;

CREATE OR REPLACE FUNCTION claim_next_blog_title()
RETURNS blog_title_bank AS $$
DECLARE
    claimed blog_title_bank;
BEGIN
    -- Self-heal: reclaim rows that have been 'generating' for more than 15
    -- minutes. Whatever was working on them is definitely gone (or should be).
    UPDATE blog_title_bank
    SET status = 'pending',
        last_error = COALESCE(last_error, '') || ' [auto-recovered from stale generating state]',
        claimed_at = NULL
    WHERE status = 'generating'
      AND claimed_at IS NOT NULL
      AND claimed_at < NOW() - INTERVAL '15 minutes';

    SELECT * INTO claimed
    FROM blog_title_bank
    WHERE status = 'pending'
    ORDER BY priority ASC, created_at ASC
    FOR UPDATE SKIP LOCKED
    LIMIT 1;

    IF claimed.id IS NULL THEN
        RETURN NULL;
    END IF;

    UPDATE blog_title_bank
    SET status = 'generating', claimed_at = NOW(), last_error = NULL
    WHERE id = claimed.id
    RETURNING * INTO claimed;

    RETURN claimed;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMIT;
