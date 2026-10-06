-- Practical points of interest around a place ("autour de moi"): shops,
-- food vending machines, water and sanitation, fuel and energy, health,
-- services (plan/research/05-poi-sources.md). They are not places: never
-- conflated with them, no overnight status, one source each (OpenStreetMap,
-- or the community for a vending machine a user added). Values another
-- open source gives for a point, joined by an identifier the point's record
-- carries (fuel prices, La Poste's opening days, FINESS), live in
-- `poi_join_records` and are credited per field where they are served.
--
-- Codes are the stable codes of lunaway_domain::poi; the CHECK lists are
-- tested against them (lunaway-db, tests/schema_and_records.rs).
--
-- Who writes what:
--   - the importers and the worker (`lunaway_ingest`) write `pois`,
--     `poi_join_records` and `poi_layer`, each transaction holding the POI
--     writers' advisory lock;
--   - the API (`lunaway_app`) reads them, stores the community's "still
--     there?" answers and queues the point for the worker; a new vending
--     machine is a `place_submissions` row of kind `poi`, which the worker
--     writes as a point of the `community` source; the moderators (with the
--     API's role) hide or show a point in `poi_moderation`;
--   - the worker opens a moderation check for every point it hides.

INSERT INTO sources (id, name, licence, licence_url, attribution, url) VALUES
    ('prix-carburants', 'Prix des carburants', 'Licence Ouverte 2.0',
     'https://www.etalab.gouv.fr/licence-ouverte-open-licence/',
     'Ministère de l''Économie, prix des carburants (data.economie.gouv.fr)',
     'https://www.data.gouv.fr/datasets/prix-des-carburants-en-france-flux-instantane-v2-amelioree/'),
    ('laposte', 'La Poste', 'ODbL 1.0',
     'https://opendatacommons.org/licenses/odbl/1-0/',
     'La Poste, calendrier d''ouverture des bureaux de poste (data.laposte.fr)',
     'https://data.laposte.fr/datasets/laposte-ouvertur'),
    ('finess', 'FINESS', 'Licence Ouverte 2.0',
     'https://www.etalab.gouv.fr/licence-ouverte-open-licence/',
     'FINESS, Agence du numérique en santé (data.gouv.fr)',
     'https://www.data.gouv.fr/datasets/finess-structures-1/');

CREATE TABLE pois (
    -- UUID v7, generated in Rust.
    id uuid PRIMARY KEY,
    source_id text NOT NULL REFERENCES sources (id),
    -- `node/123` for OpenStreetMap, `submission/<id>` for the community.
    external_id text NOT NULL,
    external_url text,
    category text NOT NULL CHECK (category IN (
        'groceries', 'vending', 'water', 'fuel', 'health', 'services')),
    kind text NOT NULL CHECK (kind IN (
        'supermarket', 'convenience', 'bakery', 'butcher', 'greengrocer', 'farm_shop',
        'marketplace', 'vending_pizza', 'vending_bread', 'vending_farm_products',
        'vending_eggs_milk', 'vending_ice', 'vending_other', 'drinking_water', 'water_point',
        'dump_station', 'toilets', 'shower', 'fuel_station', 'ev_charging', 'gas_bottles',
        'pharmacy', 'doctor', 'hospital', 'veterinary', 'laundry', 'atm', 'post_office',
        'tourist_office', 'recycling_centre', 'car_repair', 'car_wash', 'motorhome_shop')),
    -- Promoted from `data` for the map, the search and the joins.
    name text,
    brand text,
    geom geography(Point, 4326) NOT NULL,
    fuel_ref text,
    laposte_ref text,
    finess_ref text,
    -- lunaway_domain::poi::PoiRecord as JSON.
    data jsonb NOT NULL,
    -- The payload as the source sent it.
    raw jsonb NOT NULL,
    -- The hours as the record gives them, and what the worker made of them:
    -- UTC open intervals over the 14 days from local midnight of
    -- `opening_window_start`, from La Poste's calendar when the point has
    -- one (`opening_source` 'laposte'), from `opening_hours` otherwise (the
    -- point's own source).
    -- `opening_window_start` NULL asks the worker to evaluate them again.
    opening_hours text,
    opening_hours_parsed boolean NOT NULL DEFAULT false,
    always_open boolean NOT NULL DEFAULT false,
    opening_intervals jsonb,
    opening_intervals_until timestamptz,
    opening_window_start date,
    opening_source text REFERENCES sources (id),
    -- The same intervals in the map tiles' compact form
    -- (lunaway_domain::poi::encode_hours), written with them.
    opening_tile text,
    -- What the community says, written by the worker: the last "still
    -- there", and hidden after three "gone" answers (05-poi-sources.md B.4).
    last_confirmed_at timestamptz,
    hidden boolean NOT NULL DEFAULT false,
    fetched_at timestamptz NOT NULL,
    first_seen_at timestamptz NOT NULL DEFAULT now(),
    changed_at timestamptz NOT NULL DEFAULT now(),
    -- A point the source no longer lists.
    deleted_at timestamptz,
    search_text text GENERATED ALWAYS AS (
        lunaway_fold(coalesce(name, '') || ' ' || coalesce(brand, ''))) STORED,
    UNIQUE (source_id, external_id)
);

-- Map tiles and the offline download: `geom::geometry && envelope`.
CREATE INDEX pois_geom_box_idx ON pois USING gist ((geom::geometry))
    WHERE deleted_at IS NULL AND NOT hidden;
-- "Around this place": ST_DWithin and distance on geography.
CREATE INDEX pois_geom_idx ON pois USING gist (geom) WHERE deleted_at IS NULL AND NOT hidden;
CREATE INDEX pois_search_idx ON pois USING gin (search_text gin_trgm_ops)
    WHERE deleted_at IS NULL AND NOT hidden;
CREATE INDEX pois_fuel_ref_idx ON pois (fuel_ref) WHERE fuel_ref IS NOT NULL;
CREATE INDEX pois_laposte_ref_idx ON pois (laposte_ref) WHERE laposte_ref IS NOT NULL;
CREATE INDEX pois_finess_ref_idx ON pois (finess_ref) WHERE finess_ref IS NOT NULL;
-- The daily refresh of the opening intervals.
CREATE INDEX pois_opening_window_idx ON pois (opening_window_start)
    WHERE deleted_at IS NULL AND (opening_hours IS NOT NULL OR laposte_ref IS NOT NULL);
-- Retiring what an import no longer saw.
CREATE INDEX pois_source_live_idx ON pois (source_id) WHERE deleted_at IS NULL;

-- What another open source says about a point, keyed by the identifier the
-- point's record carries: a fuel station's id in the price feed, a post
-- office's id at La Poste, a FINESS number. Stored whole per source, so a
-- feed refreshed every few minutes rewrites only this table.
CREATE TABLE poi_join_records (
    source_id text NOT NULL REFERENCES sources (id),
    ref text NOT NULL CHECK (char_length(ref) BETWEEN 1 AND 32),
    -- The adapter's typed reading of the row, as JSON.
    data jsonb NOT NULL,
    raw jsonb NOT NULL,
    fetched_at timestamptz NOT NULL,
    changed_at timestamptz NOT NULL DEFAULT now(),
    -- The source no longer lists it.
    deleted_at timestamptz,
    PRIMARY KEY (source_id, ref)
);

-- The version of the map tiles: every writer that changes what a tile
-- shows moves it in the same transaction, and the tile URLs carry it, so a
-- tile is cached for good and a change reaches the map at once.
CREATE TABLE poi_layer (
    singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
    version bigint NOT NULL DEFAULT 1 CHECK (version > 0),
    changed_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO poi_layer DEFAULT VALUES;

-- "Still there?" answers about a point. They go with their account: an
-- anonymous "gone" would count once per deleted account.
CREATE TABLE poi_confirmations (
    id uuid PRIMARY KEY,
    poi_id uuid NOT NULL REFERENCES pois (id),
    account_id uuid NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
    still_there boolean NOT NULL,
    -- `dismissed` once a moderator found the point still there.
    status text NOT NULL DEFAULT 'published' CHECK (status IN ('published', 'dismissed')),
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX poi_confirmations_poi_idx ON poi_confirmations (poi_id, created_at DESC);
CREATE INDEX poi_confirmations_account_idx ON poi_confirmations (account_id);
-- The worker's purge of the answers past their year, at each run.
CREATE INDEX poi_confirmations_created_idx ON poi_confirmations (created_at);

-- Points whose community state the worker must recompute.
CREATE TABLE poi_refresh_queue (
    poi_id uuid PRIMARY KEY,
    queued_at timestamptz NOT NULL DEFAULT now()
);

-- Points a moderator hid (a check refused, `lunaway moderation hide-poi`):
-- hidden whatever the answers say, until a moderator shows them again.
CREATE TABLE poi_moderation (
    poi_id uuid PRIMARY KEY REFERENCES pois (id),
    hidden_at timestamptz NOT NULL DEFAULT now(),
    note text CHECK (char_length(note) <= 500)
);

-- A vending machine a user adds is a submission of kind `poi`; the point it
-- became is noted on it.
ALTER TABLE place_submissions
    DROP CONSTRAINT place_submissions_kind_check,
    ADD CONSTRAINT place_submissions_kind_check CHECK (kind IN ('create', 'edit', 'poi')),
    DROP CONSTRAINT place_submissions_check,
    ADD CONSTRAINT place_submissions_check CHECK (kind IN ('create', 'poi') OR place_id IS NOT NULL),
    ADD COLUMN poi_id uuid REFERENCES pois (id);

-- A point three accounts say is gone waits for a moderator.
ALTER TABLE moderation_queue
    DROP CONSTRAINT moderation_queue_kind_check,
    ADD CONSTRAINT moderation_queue_kind_check CHECK (kind IN (
        'held_review', 'reported_content', 'place_proposal', 'place_check', 'poi_check')),
    DROP CONSTRAINT moderation_queue_target_type_check,
    ADD CONSTRAINT moderation_queue_target_type_check CHECK (target_type IN (
        'review', 'photo', 'place', 'submission', 'poi'));

REVOKE ALL ON pois, poi_join_records, poi_layer, poi_confirmations, poi_refresh_queue,
    poi_moderation FROM lunaway_app, lunaway_ingest;

-- The API reads the layer and writes the community's answers, never a
-- point.
GRANT SELECT ON pois, poi_join_records, poi_layer TO lunaway_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON poi_confirmations TO lunaway_app;
GRANT INSERT ON poi_refresh_queue TO lunaway_app;
-- The moderation commands run with the API's role.
GRANT SELECT, INSERT, DELETE ON poi_moderation TO lunaway_app;

-- The importers and the worker write the points, the joined values and the
-- layer's version. A point the source drops is a tombstone (deleted_at),
-- so DELETE is not granted on them.
GRANT SELECT, INSERT, UPDATE ON pois, poi_join_records, poi_layer TO lunaway_ingest;
-- The worker purges the answers past their year: they no longer count, and
-- a dated list of where an account was is not kept for nothing.
GRANT SELECT, DELETE ON poi_confirmations TO lunaway_ingest;
GRANT SELECT, DELETE ON poi_refresh_queue TO lunaway_ingest;
GRANT SELECT ON poi_moderation TO lunaway_ingest;
-- The worker, which counts the answers under its lock, opens the check of
-- a point it hides; it only inserts, the moderators decide.
GRANT INSERT ON moderation_queue TO lunaway_ingest;
