-- Accounts without e-mail, contributions, photos, moderation, favourites.
-- Codes stored as text are the lowercase forms of the
-- GraphQL enums; the CHECK lists are tested against the Rust enums.
--
-- Who writes what:
--   - the API (`lunaway_app`) writes the accounts and the contribution
--     tables, and nothing of the catalogue (sources, source_records, places,
--     place_sources, match_pairs, conflation_constraints);
--   - a new place or a place edit is a row of `place_submissions`, which the
--     conflation worker (`lunaway_ingest`) turns into a record of the
--     `community` source, then into a place, under the writers' lock;
--   - the community summary of a place (ratings, counts, cover photos,
--     verification) lives on `places` so the change feed carries it; the API
--     queues the place in `place_refresh_queue` and the worker recomputes the
--     summary and moves the place in the feed, under the same lock.

INSERT INTO sources (id, name, licence, licence_url, attribution, url) VALUES
    ('community', 'Lunaway community', 'ODbL 1.0',
     'https://opendatacommons.org/licenses/odbl/1-0/',
     'Lunaway contributors',
     'https://lunaway.net');

CREATE TABLE accounts (
    -- UUID v7, generated in Rust.
    id uuid PRIMARY KEY,
    -- Public display name: generated at creation, editable (3 to 32
    -- characters when chosen; a generated one may be longer).
    pseudonym text NOT NULL CHECK (char_length(pseudonym) BETWEEN 3 AND 64),
    -- Level the trust rules last computed (0 to 4).
    trust_level smallint NOT NULL DEFAULT 0 CHECK (trust_level BETWEEN 0 AND 4),
    -- Level set by the administration: a floor the rules never go below
    -- (a moderator, the store reviewers' demo account).
    granted_level smallint NOT NULL DEFAULT 0 CHECK (granted_level BETWEEN 0 AND 4),
    -- Distinct UTC days on which the account used a session.
    active_days integer NOT NULL DEFAULT 1 CHECK (active_days >= 0),
    last_active_on date NOT NULL DEFAULT (now() AT TIME ZONE 'UTC')::date,
    created_at timestamptz NOT NULL DEFAULT now(),
    banned_at timestamptz,
    ban_reason text
);

CREATE TABLE device_keys (
    id uuid PRIMARY KEY,
    account_id uuid NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
    -- RFC 7638 thumbprint of the public JWK (SHA-256, base64url): the key's
    -- identity, whatever member order the client serialised.
    thumbprint text NOT NULL UNIQUE CHECK (thumbprint ~ '^[A-Za-z0-9_-]{43}$'),
    -- The P-256 point, SEC1 uncompressed (0x04, x, y).
    public_key bytea NOT NULL CHECK (octet_length(public_key) = 65),
    created_at timestamptz NOT NULL DEFAULT now(),
    last_used_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX device_keys_account_idx ON device_keys (account_id);

CREATE TABLE sessions (
    -- SHA-256 of the bearer token; the token itself is never stored.
    token_hash bytea PRIMARY KEY CHECK (octet_length(token_hash) = 32),
    account_id uuid NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
    device_key_id uuid NOT NULL REFERENCES device_keys (id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now(),
    last_used_at timestamptz NOT NULL DEFAULT now(),
    -- Sliding: pushed back on use.
    expires_at timestamptz NOT NULL
);

CREATE INDEX sessions_account_idx ON sessions (account_id);
CREATE INDEX sessions_expires_idx ON sessions (expires_at);

CREATE TABLE recovery_codes (
    -- One code per account; a new one replaces it.
    account_id uuid PRIMARY KEY REFERENCES accounts (id) ON DELETE CASCADE,
    -- argon2id of the code under a fixed salt. The code holds 128 random
    -- bits, so a per-row salt protects nothing a guess could reach, and a
    -- fixed one lets a code find its account in one hash.
    code_hash bytea NOT NULL UNIQUE CHECK (octet_length(code_hash) = 32),
    created_at timestamptz NOT NULL DEFAULT now()
);

-- A trusted account vouching for another: a level-2 account sponsoring a new
-- one (level 1), a level-4 account nominating a level-3 one.
CREATE TABLE account_endorsements (
    account_id uuid NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
    kind text NOT NULL CHECK (kind IN ('sponsor', 'nominate')),
    by_account_id uuid NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (account_id, kind, by_account_id),
    CHECK (account_id <> by_account_id)
);

CREATE INDEX account_endorsements_by_idx ON account_endorsements (by_account_id);

-- Authors an account does not want to see.
CREATE TABLE muted_authors (
    account_id uuid NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
    muted_id uuid NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (account_id, muted_id),
    CHECK (account_id <> muted_id)
);

CREATE INDEX muted_authors_muted_idx ON muted_authors (muted_id);

-- A rating, with or without text: one per account and place. A rating
-- alone (no body) is published at once; a body goes through the automatic
-- rules first. A deleted account's published reviews stay, without author.
CREATE TABLE reviews (
    id uuid PRIMARY KEY,
    place_id uuid NOT NULL REFERENCES places (id),
    account_id uuid REFERENCES accounts (id),
    stars smallint NOT NULL CHECK (stars BETWEEN 1 AND 5),
    body text CHECK (body IS NULL OR char_length(body) BETWEEN 10 AND 2000),
    visited_on date,
    vehicle text CHECK (vehicle IN ('van', 'campervan', 'motorhome', 'caravan', 'other')),
    status text NOT NULL CHECK (status IN ('published', 'pending', 'hidden', 'removed')),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX reviews_account_place_idx ON reviews (account_id, place_id)
    WHERE account_id IS NOT NULL;
CREATE INDEX reviews_place_idx ON reviews (place_id, id DESC);

-- A photo of a place. The files are content-addressed under the media root;
-- two rows may share one (the same picture sent twice).
CREATE TABLE photos (
    id uuid PRIMARY KEY,
    place_id uuid NOT NULL REFERENCES places (id),
    -- No ON DELETE: an account is deleted only once its photos and their
    -- files are gone.
    account_id uuid REFERENCES accounts (id),
    status text NOT NULL CHECK (status IN ('published', 'hidden', 'removed')),
    -- Paths relative to the media root (`photos/ab/cd/<sha256>.webp`).
    path text NOT NULL CHECK (path ~ '^photos/[0-9a-f]{2}/[0-9a-f]{2}/[0-9a-f]{64}\.(webp|jpg)$'),
    thumb_path text NOT NULL
        CHECK (thumb_path ~ '^photos/[0-9a-f]{2}/[0-9a-f]{2}/[0-9a-f]{64}\.(webp|jpg)$'),
    width integer NOT NULL CHECK (width > 0),
    height integer NOT NULL CHECK (height > 0),
    thumb_width integer NOT NULL CHECK (thumb_width > 0),
    thumb_height integer NOT NULL CHECK (thumb_height > 0),
    thumbhash bytea NOT NULL CHECK (octet_length(thumbhash) BETWEEN 1 AND 64),
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX photos_place_idx ON photos (place_id, id DESC);
CREATE INDEX photos_account_idx ON photos (account_id);
CREATE INDEX photos_path_idx ON photos (path);
CREATE INDEX photos_thumb_path_idx ON photos (thumb_path);

-- "Still there?" answers. The position a client may send is reduced to the
-- verdict before anything is stored.
CREATE TABLE confirmations (
    id uuid PRIMARY KEY,
    place_id uuid NOT NULL REFERENCES places (id),
    account_id uuid REFERENCES accounts (id),
    status text NOT NULL CHECK (status IN ('still_ok', 'closed', 'changed')),
    -- Read by moderation only, never published.
    note text CHECK (char_length(note) <= 500),
    presence text NOT NULL CHECK (presence IN ('present', 'unverified')),
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX confirmations_place_idx ON confirmations (place_id, created_at DESC);
CREATE INDEX confirmations_account_idx ON confirmations (account_id);

-- Problems a visitor met at a place; the change feed carries the recent
-- ones by kind, the notes stay with moderation.
CREATE TABLE issue_reports (
    id uuid PRIMARY KEY,
    place_id uuid NOT NULL REFERENCES places (id),
    account_id uuid REFERENCES accounts (id),
    kind text NOT NULL CHECK (kind IN ('night_ban', 'service_broken', 'no_access', 'danger')),
    note text CHECK (char_length(note) <= 500),
    status text NOT NULL DEFAULT 'published' CHECK (status IN ('published', 'dismissed')),
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX issue_reports_place_idx ON issue_reports (place_id, created_at DESC);
CREATE INDEX issue_reports_account_idx ON issue_reports (account_id);

-- A user flagging a review, a photo or a place. Three distinct reporters
-- hide a review or a photo until a moderator decides.
CREATE TABLE content_reports (
    id uuid PRIMARY KEY,
    target_type text NOT NULL CHECK (target_type IN ('review', 'photo', 'place')),
    target_id uuid NOT NULL,
    reporter_id uuid NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
    reason text NOT NULL CHECK (reason IN ('spam', 'offensive', 'wrong', 'privacy', 'other')),
    note text CHECK (char_length(note) <= 500),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (target_type, target_id, reporter_id)
);

CREATE INDEX content_reports_reporter_idx ON content_reports (reporter_id);

-- What waits for a moderator (`lunaway moderation list`).
CREATE TABLE moderation_queue (
    id uuid PRIMARY KEY,
    kind text NOT NULL CHECK (kind IN (
        'held_review', 'reported_content', 'place_proposal', 'place_check')),
    target_type text NOT NULL CHECK (target_type IN ('review', 'photo', 'place', 'submission')),
    target_id uuid NOT NULL,
    -- The author of the content, or whoever proposed the change.
    account_id uuid REFERENCES accounts (id) ON DELETE SET NULL,
    -- Why it is here: the automatic rules that fired, the report reasons.
    reason text NOT NULL,
    status text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'approved', 'rejected')),
    created_at timestamptz NOT NULL DEFAULT now(),
    decided_at timestamptz,
    decision_note text
);

CREATE UNIQUE INDEX moderation_queue_open_idx ON moderation_queue (kind, target_type, target_id)
    WHERE status = 'open';
CREATE INDEX moderation_queue_account_idx ON moderation_queue (account_id);

CREATE TABLE favorite_lists (
    id uuid PRIMARY KEY,
    account_id uuid NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
    name text NOT NULL CHECK (char_length(name) BETWEEN 1 AND 60),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (account_id, name)
);

CREATE TABLE favorite_items (
    list_id uuid NOT NULL REFERENCES favorite_lists (id) ON DELETE CASCADE,
    place_id uuid NOT NULL REFERENCES places (id),
    added_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (list_id, place_id)
);

-- New places and place edits, kept as the revision history. `accepted`
-- ones wait for the conflation worker, which writes them into a record of
-- the `community` source and marks them `applied`; `proposed` ones wait
-- for a moderator.
CREATE TABLE place_submissions (
    id uuid PRIMARY KEY,
    account_id uuid REFERENCES accounts (id),
    -- The device key of the session that sent it: the revision is signed
    -- by that session.
    device_key_id uuid REFERENCES device_keys (id) ON DELETE SET NULL,
    kind text NOT NULL CHECK (kind IN ('create', 'edit')),
    -- The place an edit targets, or the place a creation became.
    place_id uuid REFERENCES places (id),
    payload jsonb NOT NULL,
    status text NOT NULL CHECK (status IN (
        'proposed', 'accepted', 'applied', 'rejected', 'withdrawn')),
    -- The community record the submission was written into.
    record_id uuid REFERENCES source_records (id),
    created_at timestamptz NOT NULL DEFAULT now(),
    decided_at timestamptz,
    applied_at timestamptz,
    CHECK (kind = 'create' OR place_id IS NOT NULL)
);

CREATE INDEX place_submissions_accepted_idx ON place_submissions (id) WHERE status = 'accepted';
CREATE INDEX place_submissions_account_idx ON place_submissions (account_id);
CREATE INDEX place_submissions_place_idx ON place_submissions (place_id);

-- Places whose community summary must be recomputed by the worker.
CREATE TABLE place_refresh_queue (
    place_id uuid PRIMARY KEY,
    queued_at timestamptz NOT NULL DEFAULT now()
);

-- The community summary of a place, written by the worker and carried by
-- the change feed. Constant defaults: no table rewrite.
ALTER TABLE places
    ADD COLUMN rating_avg double precision CHECK (rating_avg BETWEEN 1 AND 5),
    ADD COLUMN rating_count integer NOT NULL DEFAULT 0 CHECK (rating_count >= 0),
    ADD COLUMN review_count integer NOT NULL DEFAULT 0 CHECK (review_count >= 0),
    ADD COLUMN photo_count integer NOT NULL DEFAULT 0 CHECK (photo_count >= 0),
    -- The latest published photos: [{id, path, thumbPath, width, height,
    -- thumbhash, authorId}].
    ADD COLUMN cover_photos jsonb NOT NULL DEFAULT '[]',
    -- Issues reported over the last 30 days: [{kind, count, lastReportedAt}].
    ADD COLUMN reported_issues jsonb NOT NULL DEFAULT '[]',
    -- `to_verify` while a place only the community describes has not been
    -- confirmed by two accounts other than its author.
    ADD COLUMN verification text NOT NULL DEFAULT 'verified'
        CHECK (verification IN ('verified', 'to_verify'));

-- Following merges back: the community rows of a place absorbed by another
-- count for the place that absorbed it.
CREATE INDEX places_merged_into_idx ON places (merged_into) WHERE merged_into IS NOT NULL;

-- Grants: each role gets what its code runs, nothing more.
REVOKE ALL ON accounts, device_keys, sessions, recovery_codes, account_endorsements,
    muted_authors, reviews, photos, confirmations, issue_reports, content_reports,
    moderation_queue, favorite_lists, favorite_items, place_submissions, place_refresh_queue
    FROM lunaway_app, lunaway_ingest;

-- The API (and the moderation commands, which run with its role) writes the
-- accounts and every contribution. It reads the catalogue and writes none of
-- it.
GRANT SELECT, INSERT, UPDATE, DELETE ON accounts, device_keys, sessions, recovery_codes,
    account_endorsements, muted_authors, reviews, photos, confirmations, issue_reports,
    content_reports, moderation_queue, favorite_lists, favorite_items, place_submissions
    TO lunaway_app;
GRANT INSERT ON place_refresh_queue TO lunaway_app;

-- The worker reads what the community summary is made of, takes the
-- submissions it applies and the places queued for a refresh, and links an
-- edit's record to the place it targets (a `must_link`).
GRANT SELECT (id, banned_at) ON accounts TO lunaway_ingest;
GRANT SELECT ON reviews, photos, confirmations, issue_reports TO lunaway_ingest;
GRANT SELECT, UPDATE ON place_submissions TO lunaway_ingest;
GRANT SELECT, DELETE ON place_refresh_queue TO lunaway_ingest;
GRANT INSERT ON conflation_constraints TO lunaway_ingest;
