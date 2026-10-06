-- The MVP schema: sources, what each source says (source_records), the
-- canonical places built from them by the conflation, the links between the
-- two, the match decisions and the human constraints.
--
-- Codes (kinds, services, activities, overnight statuses) are the stable
-- codes of lunaway-domain's taxonomy; the CHECK lists below are tested against
-- it (lunaway-db, tests/schema.rs), so a new code fails a test until a
-- migration adds it here.

CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS unaccent;

-- unaccent() is only STABLE (its dictionary can be reloaded), so it cannot
-- back an index or a generated column. Naming the dictionary and parsing the
-- body at creation (SQL-standard body) makes the result depend on the input
-- alone, which is what IMMUTABLE promises.
CREATE FUNCTION lunaway_fold(input text) RETURNS text
    LANGUAGE sql IMMUTABLE PARALLEL SAFE STRICT
    RETURN lower(public.unaccent('public.unaccent'::regdictionary, input));

CREATE TABLE sources (
    id text PRIMARY KEY CHECK (id ~ '^[a-z0-9-]{1,32}$'),
    name text NOT NULL,
    licence text NOT NULL,
    licence_url text NOT NULL,
    attribution text NOT NULL,
    url text NOT NULL
);

INSERT INTO sources (id, name, licence, licence_url, attribution, url) VALUES
    ('osm', 'OpenStreetMap', 'ODbL 1.0',
     'https://opendatacommons.org/licenses/odbl/1-0/',
     '© OpenStreetMap contributors',
     'https://www.openstreetmap.org/copyright'),
    ('atout-france', 'Atout France', 'Licence Ouverte 2.0',
     'https://www.etalab.gouv.fr/licence-ouverte-open-licence/',
     'Atout France, hébergements touristiques classés (data.gouv.fr); positions: Base Adresse Nationale',
     'https://www.data.gouv.fr/datasets/hebergements-touristiques-classes-en-france/');

CREATE TABLE source_records (
    -- UUID v7, generated in Rust.
    id uuid PRIMARY KEY,
    source_id text NOT NULL REFERENCES sources (id),
    external_id text NOT NULL,
    external_url text,
    -- Promoted from `data` for the spatial candidate search and for reading.
    kind text NOT NULL CHECK (kind IN (
        'motorhome_area', 'service_area', 'campsite', 'parking', 'nature', 'rest_area',
        'picnic_area', 'farm', 'homestay', 'off_road', 'extra_service')),
    name text,
    geom geography(Point, 4326) NOT NULL,
    accuracy_m double precision NOT NULL DEFAULT 0 CHECK (accuracy_m >= 0),
    -- lunaway_domain::NormalizedRecord as JSON.
    data jsonb NOT NULL,
    -- The payload as the source sent it, for audit and re-normalisation.
    raw jsonb NOT NULL,
    -- The slice of the source a run covered (an OSM region), so a run over
    -- one slice only retires the records of that slice.
    scope text,
    fetched_at timestamptz NOT NULL,
    first_seen_at timestamptz NOT NULL DEFAULT now(),
    changed_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    -- Set when the content changes or the record disappears; cleared by the
    -- conflation once the record's place reflects it.
    needs_conflation boolean NOT NULL DEFAULT true,
    UNIQUE (source_id, external_id)
);

-- Candidate search: ST_DWithin on geography.
CREATE INDEX source_records_geom_idx ON source_records USING gist (geom);
-- The conflation's work list.
CREATE INDEX source_records_dirty_idx ON source_records (id) WHERE needs_conflation;
-- Retiring the records a run did not see.
CREATE INDEX source_records_scope_idx ON source_records (source_id, scope) WHERE deleted_at IS NULL;

-- Every write to `places` takes the next value, so `updated_seq` is the sync
-- cursor. The conflation holds an advisory lock for its whole transaction:
-- with writers serialised, every committed value is below every value still
-- in flight, so a reader that saw seq N has seen everything up to N.
CREATE SEQUENCE place_change_seq AS bigint;

CREATE TABLE places (
    -- UUID v7, generated in Rust.
    id uuid PRIMARY KEY,
    kind text NOT NULL CHECK (kind IN (
        'motorhome_area', 'service_area', 'campsite', 'parking', 'nature', 'rest_area',
        'picnic_area', 'farm', 'homestay', 'off_road', 'extra_service')),
    name text,
    geom geography(Point, 4326) NOT NULL,
    overnight text NOT NULL CHECK (overnight IN (
        'allowed', 'tolerated', 'day_only', 'forbidden', 'unknown')),
    services text[] NOT NULL DEFAULT '{}' CHECK (services <@ ARRAY[
        'drinking_water', 'grey_water', 'black_water', 'waste_bin', 'toilets', 'showers',
        'electricity', 'wifi', 'laundry', 'lpg', 'gas_bottles', 'vehicle_wash', 'bakery',
        'swimming_pool', 'pets_allowed', 'mobile_data', 'winter_caravanning']::text[]),
    activities text[] NOT NULL DEFAULT '{}' CHECK (activities <@ ARRAY[
        'monuments', 'windsurf_kitesurf', 'mountain_biking', 'hiking', 'climbing',
        'canoe_kayak', 'fishing', 'shore_fishing', 'swimming', 'motorcycling', 'viewpoint',
        'playground']::text[]),
    description text,
    street text,
    postcode text,
    city text,
    country_code text,
    price_parking_eur double precision CHECK (price_parking_eur >= 0),
    price_services_eur double precision CHECK (price_services_eur >= 0),
    max_height_m double precision CHECK (max_height_m > 0),
    capacity integer CHECK (capacity >= 0),
    opening_hours text,
    -- Whether `opening_hours` parses; false when it is absent.
    opening_hours_parsed boolean NOT NULL DEFAULT false,
    -- UTC open intervals over the 14 days that start at local midnight of
    -- `opening_window_start`, evaluated from `opening_hours` so an offline
    -- device can answer "open now?" without an evaluator. NULL when
    -- `opening_hours` is absent or does not parse; refreshed daily.
    opening_intervals jsonb,
    opening_window_start date,
    website text,
    phone text,
    stars smallint CHECK (stars BETWEEN 1 AND 5),
    last_confirmed_at timestamptz,
    -- lunaway_domain::FieldProvenance list. Always read and written with the
    -- place as a whole, never queried by field, so one column keeps the
    -- write atomic and the read free of a join.
    provenance jsonb NOT NULL DEFAULT '[]',
    -- Digest of the resolved content and of the linked records: a
    -- conflation run that resolves the same thing writes nothing.
    content_hash text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    updated_seq bigint NOT NULL DEFAULT nextval('place_change_seq'),
    -- A deleted place stays as a tombstone so the sync can report it, with
    -- the place that absorbed it when it was merged.
    deleted_at timestamptz,
    merged_into uuid REFERENCES places (id),
    search_text text GENERATED ALWAYS AS (
        lunaway_fold(coalesce(name, '') || ' ' || coalesce(city, ''))) STORED
);

-- Sync: changes since a cursor.
CREATE UNIQUE INDEX places_updated_seq_idx ON places (updated_seq);
-- Viewport: `geom::geometry && envelope` (a planar lat/lon box, which is what
-- a map viewport is; a geography box would bend its edges along great
-- circles).
CREATE INDEX places_geom_box_idx ON places USING gist ((geom::geometry));
-- Distance ranking of the search around a point.
CREATE INDEX places_geom_idx ON places USING gist (geom);
-- Search: word_similarity (`<%`) on the folded name and city.
CREATE INDEX places_search_idx ON places USING gin (search_text gin_trgm_ops)
    WHERE deleted_at IS NULL;
-- Filters of the viewport query.
CREATE INDEX places_services_idx ON places USING gin (services) WHERE deleted_at IS NULL;
-- The daily refresh of the opening intervals.
CREATE INDEX places_opening_window_idx ON places (opening_window_start)
    WHERE deleted_at IS NULL AND opening_hours IS NOT NULL;

CREATE TABLE place_sources (
    -- A record describes one place at a time.
    record_id uuid PRIMARY KEY REFERENCES source_records (id),
    place_id uuid NOT NULL REFERENCES places (id),
    -- Best score that tied the record to the others of its place; NULL when
    -- it is the place's only record.
    match_score double precision CHECK (match_score BETWEEN 0 AND 1)
);

CREATE INDEX place_sources_place_idx ON place_sources (place_id);

-- Scored pairs worth keeping: merges, and the review queue. Distinct pairs
-- are not stored; they are recomputed when either record changes.
CREATE TABLE match_pairs (
    record_a uuid NOT NULL REFERENCES source_records (id),
    record_b uuid NOT NULL REFERENCES source_records (id),
    score double precision NOT NULL CHECK (score BETWEEN 0 AND 1),
    decision text NOT NULL CHECK (decision IN ('merge', 'review')),
    reason text NOT NULL,
    -- lunaway_domain::ScoreComponents, so a decision can be explained.
    components jsonb NOT NULL,
    computed_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (record_a, record_b),
    CHECK (record_a < record_b)
);

CREATE INDEX match_pairs_record_b_idx ON match_pairs (record_b);
CREATE INDEX match_pairs_review_idx ON match_pairs (score DESC) WHERE decision = 'review';

-- Human decisions on a pair of records; the latest replaces the earlier one.
CREATE TABLE conflation_constraints (
    id uuid PRIMARY KEY,
    record_a uuid NOT NULL REFERENCES source_records (id),
    record_b uuid NOT NULL REFERENCES source_records (id),
    kind text NOT NULL CHECK (kind IN ('must_link', 'cannot_link')),
    reason text,
    created_at timestamptz NOT NULL DEFAULT now(),
    CHECK (record_a < record_b),
    UNIQUE (record_a, record_b)
);

CREATE INDEX conflation_constraints_record_b_idx ON conflation_constraints (record_b);
