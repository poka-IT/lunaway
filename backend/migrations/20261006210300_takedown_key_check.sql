-- The takedowns' cells are keyed hashes: under another secret (a server
-- rebuilt with a new one, a mistyped copy) none of them matches, and the
-- conflation would hold nothing without a word. The first takedown stores
-- a check value of its secret, an HMAC of a fixed label
-- (lunaway_domain::takedown::TakedownKey::check), which says nothing of
-- the secret; a takedown or a replay under another secret is refused, and
-- the conflation says so at each run.
CREATE TABLE takedown_key (
    singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
    key_check bytea NOT NULL CHECK (length(key_check) = 32),
    created_at timestamptz NOT NULL DEFAULT now()
);

REVOKE ALL ON takedown_key FROM lunaway_app, lunaway_ingest;
GRANT SELECT, INSERT ON takedown_key TO lunaway_ingest;
