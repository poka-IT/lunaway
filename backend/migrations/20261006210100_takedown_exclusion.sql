-- A place taken down must not come back (docs/deploy.md, "Taking a place
-- down"): another account, another OpenStreetMap element or another source
-- could list the same spot again, and it went live as a new place.
--
-- The takedown keeps no position. It stores the keyed hashes of the cells
-- around where the place and its records stood (lunaway_domain::takedown:
-- HMAC-SHA-256 under LUNAWAY_TAKEDOWN_SECRET, a secret outside the database
-- and its dumps, of H3 cells at resolution 11, four rings around each
-- position). The conflation hashes the cell of every place it would create,
-- and of every place it would move, and holds the group when the hash is
-- here: no place is written, and a moderator decides.
CREATE TABLE takedown_cells (
    cell bytea NOT NULL CHECK (length(cell) = 32),
    -- The place taken down. A hint, not a reference: after a restore, the
    -- replay of the takedown journal puts the cells back before the place
    -- exists again.
    place_id uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (cell, place_id)
);

-- A group of records the conflation would have made a new place of, or
-- that would have moved a live place, inside a takedown's cells. It shows
-- nowhere until a moderator releases it (`lunaway moderation approve`, an
-- owner who now welcomes vans); the worker then conflates its records
-- again, and a group holding a released record is no longer held.
CREATE TABLE place_holds (
    id uuid PRIMARY KEY,
    kind text NOT NULL CHECK (kind IN ('create', 'move')),
    -- The live place a move would have moved; none for a new place.
    place_id uuid REFERENCES places (id),
    -- The group's live records when it was last held.
    records uuid[] NOT NULL CHECK (cardinality(records) > 0),
    status text NOT NULL DEFAULT 'held' CHECK (status IN ('held', 'released', 'rejected')),
    held_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    decided_at timestamptz,
    -- When the worker flagged a released hold's records for the conflation.
    requeued_at timestamptz,
    CHECK (kind = 'create' OR place_id IS NOT NULL),
    CHECK ((status = 'held') = (decided_at IS NULL))
);

-- The holds a group's records fall in: a few rows, read by overlap.
CREATE INDEX place_holds_records_idx ON place_holds USING gin (records);

-- The journal of releases: one row per released hold, never changed.
CREATE TABLE place_hold_releases (
    hold_id uuid PRIMARY KEY REFERENCES place_holds (id),
    note text CHECK (length(note) <= 2000),
    released_at timestamptz NOT NULL DEFAULT now()
);

-- A held group is a queue entry of its own kind and target.
ALTER TABLE moderation_queue
    DROP CONSTRAINT moderation_queue_kind_check,
    ADD CONSTRAINT moderation_queue_kind_check CHECK (kind IN (
        'held_review', 'reported_content', 'place_proposal', 'place_check', 'poi_check',
        'road_report', 'place_hold')),
    DROP CONSTRAINT moderation_queue_target_type_check,
    ADD CONSTRAINT moderation_queue_target_type_check CHECK (target_type IN (
        'review', 'photo', 'place', 'submission', 'poi', 'road_event', 'place_hold'));

-- The importers' role writes the catalogue, so it alone stores the cells
-- (at a takedown, under the writers' lock) and reads them (the
-- conflation). The API's role never sees them: the hashes are only as
-- private as the secret, and that secret is never in the API's
-- environment. The moderation commands (the API's role) read the holds,
-- decide them and journal each release; the worker writes the holds and
-- reads the decisions.
REVOKE ALL ON takedown_cells, place_holds, place_hold_releases FROM lunaway_app, lunaway_ingest;
-- The worker never decides a hold: it may not write its status, and it
-- releases nothing a release row does not journal.
GRANT SELECT, INSERT ON takedown_cells TO lunaway_ingest;
GRANT SELECT, INSERT, UPDATE (kind, place_id, records, updated_at, requeued_at)
    ON place_holds TO lunaway_ingest;
GRANT SELECT ON place_hold_releases TO lunaway_ingest;
GRANT SELECT, UPDATE (status, decided_at) ON place_holds TO lunaway_app;
GRANT SELECT, INSERT ON place_hold_releases TO lunaway_app;
