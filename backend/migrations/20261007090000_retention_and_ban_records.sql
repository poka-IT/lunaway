-- How long the contribution tables keep what they hold, and what a banned
-- account leaves when it deletes itself. The durations live in
-- `lunaway_db::retention`, run daily by `lunaway retention` (the API's
-- role); this migration adds what that job and the ban need.

-- A takedown keeps the kind of request only: a free text could name the
-- requester. The codes are `lunaway_domain::takedown::TakedownCode`; a text
-- that is not one of them becomes `other` (production held no row when
-- this was written).
UPDATE place_takedowns SET reason = 'other'
WHERE reason NOT IN ('private-home', 'gdpr', 'court-order', 'other');
ALTER TABLE place_takedowns
    ADD CONSTRAINT place_takedowns_reason_is_a_code
    CHECK (reason IN ('private-home', 'gdpr', 'court-order', 'other'));

-- A banned account may delete itself (the GDPR's erasure), but its device
-- keys must not open a new account at once. What stays is the SHA-256 of
-- each key's public point (SEC1, uncompressed) and the two dates, for two
-- years from the deletion: no account, pseudonym, reason or content.
CREATE TABLE banned_keys (
    key_hash bytea PRIMARY KEY CHECK (octet_length(key_hash) = 32),
    banned_at timestamptz NOT NULL,
    deleted_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX banned_keys_deleted_idx ON banned_keys (deleted_at);

REVOKE ALL ON banned_keys FROM lunaway_app, lunaway_ingest;
GRANT SELECT, INSERT, DELETE ON banned_keys TO lunaway_app;

-- The "still there?" answers older than two years are deleted. What they
-- gave the place stays, on the live place they had become part of: their
-- latest "still ok", and how many accounts with no answer left there they
-- had counted, so neither "last confirmed" nor the verification of a place
-- only the community describes moves back. A count, never who.
CREATE TABLE confirmation_tallies (
    place_id uuid PRIMARY KEY REFERENCES places (id),
    last_ok timestamptz,
    confirmers integer NOT NULL DEFAULT 0 CHECK (confirmers >= 0),
    updated_at timestamptz NOT NULL DEFAULT now()
);

REVOKE ALL ON confirmation_tallies FROM lunaway_app, lunaway_ingest;
GRANT SELECT, INSERT, UPDATE, DELETE ON confirmation_tallies TO lunaway_app;
GRANT SELECT ON confirmation_tallies TO lunaway_ingest;

-- The places an account confirmed count toward its trust level: those
-- whose rows went count on the account, as moderation removals do.
ALTER TABLE accounts
    ADD COLUMN archived_confirmations integer NOT NULL DEFAULT 0
        CHECK (archived_confirmations >= 0);

-- The texts of a banned account's reviews go at the ban (a review becomes
-- a rating without text); this applies it to the accounts banned before.
UPDATE reviews r SET body = NULL, lang = NULL, updated_at = now()
FROM accounts a
WHERE a.id = r.account_id AND a.banned_at IS NOT NULL AND r.body IS NOT NULL;

-- What the daily job looks for, by date.
CREATE INDEX issue_reports_created_idx ON issue_reports (created_at);
CREATE INDEX confirmations_created_idx ON confirmations (created_at);
