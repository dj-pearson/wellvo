-- Migration: 00016_invite_pairing_code
-- Adds a short pairing code to invite_tokens so receivers can set up
-- on a different device (e.g. iPad) by entering a 6-digit code from
-- the SMS they received on their phone.

BEGIN;

ALTER TABLE invite_tokens
  ADD COLUMN pairing_code TEXT;

CREATE UNIQUE INDEX idx_invite_tokens_pairing_code
  ON invite_tokens(pairing_code)
  WHERE pairing_code IS NOT NULL AND used_by IS NULL;

COMMIT;
