-- The account's home, and the merge of one account into another.
--
-- The home is one point per account: an address, a town, a bare point of
-- the map or a shop, as a saved point is (`favorite_points`), kept apart
-- from the lists so an app that reads the lists never meets it. It is the
-- account's own and private: only its owner reads it, nothing logs it,
-- and it goes with the account (ON DELETE CASCADE).
CREATE TABLE favorite_homes (
    account_id uuid PRIMARY KEY REFERENCES accounts (id) ON DELETE CASCADE,
    kind text NOT NULL CHECK (kind IN ('address', 'town', 'point', 'poi')),
    name text NOT NULL CHECK (char_length(name) BETWEEN 1 AND 120),
    address text CHECK (char_length(address) BETWEEN 1 AND 200),
    lat double precision NOT NULL CHECK (lat BETWEEN -90 AND 90),
    lon double precision NOT NULL CHECK (lon BETWEEN -180 AND 180),
    -- A shop or a service: the point of interest and its kind.
    poi_id uuid,
    poi_kind text,
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK ((kind = 'poi') = (poi_id IS NOT NULL)),
    CHECK ((poi_id IS NULL) = (poi_kind IS NULL))
);

REVOKE ALL ON favorite_homes FROM lunaway_app, lunaway_ingest;
GRANT SELECT, INSERT, UPDATE, DELETE ON favorite_homes TO lunaway_app;

-- The device keys of an account merged into another (`mergeAccount`): the
-- SHA-256 of each key, and the account it went into. The merged account
-- is deleted; its other devices sign in with a key no account holds, and
-- this row lets the sign-in say where the account went instead of "no
-- account" alone. A key, never the account it was: nothing here names the
-- account merged. Kept a year (`retention::MERGED_KEY_DAYS`), and gone
-- with the account it points to.
CREATE TABLE merged_keys (
    key_hash bytea PRIMARY KEY CHECK (octet_length(key_hash) = 32),
    into_account uuid NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
    merged_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX merged_keys_into_idx ON merged_keys (into_account);
CREATE INDEX merged_keys_merged_idx ON merged_keys (merged_at);

REVOKE ALL ON merged_keys FROM lunaway_app, lunaway_ingest;
GRANT SELECT, INSERT, UPDATE, DELETE ON merged_keys TO lunaway_app;

-- A merge never raises a level: the account that receives another one's
-- history keeps at most the higher of the two levels, until its next
-- contribution, when the trust rules count the merged history as theirs
-- (`auth::compute_level`). Null for every account no merge capped.
ALTER TABLE accounts
    ADD COLUMN level_ceiling smallint CHECK (level_ceiling BETWEEN 0 AND 4);
