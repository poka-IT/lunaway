-- The map tiles of the places (`GET /places/...`, lunaway-api `tiles.rs`):
-- the services of a place as a bit mask, and the version of the tiles.

-- Bit i set when the place has the i-th service of
-- `lunaway_domain::Service::ALL` (drinking_water bit 0, ...,
-- winter_caravanning bit 16). The tiles carry the mask and the app filters
-- it with the same bits; `lunaway-db/tests/place_tiles.rs` checks every bit
-- against the domain's list. A new service goes last: this function then
-- gets a new version with the new code appended, and the column below is
-- recomputed.
CREATE FUNCTION lunaway_services_mask(services text[]) RETURNS integer
LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE AS $$
    SELECT coalesce(sum(1 << (array_position(ARRAY[
        'drinking_water', 'grey_water', 'black_water', 'waste_bin', 'toilets', 'showers',
        'electricity', 'wifi', 'laundry', 'lpg', 'gas_bottles', 'vehicle_wash', 'bakery',
        'swimming_pool', 'pets_allowed', 'mobile_data', 'winter_caravanning']::text[], s) - 1)),
        0)::integer
    FROM unnest(services) AS s
$$;

-- Stored, so a tile of a whole region reads it instead of computing it
-- per place: on 86 000 places, the computation took more than half of a
-- low-zoom tile's time (230 of 390 ms, `docs/deploy.md`, "Places layer").
-- A rewrite of `places`, a few seconds for Europe.
ALTER TABLE places ADD COLUMN services_mask integer
    GENERATED ALWAYS AS (lunaway_services_mask(services)) STORED;

-- The version of the places' tiles, as `poi_layer` for the points: the tile
-- URLs carry it, so a tile is cached for good, and it moves at most every
-- `--place-layer-every-mins` (the worker) or at once after a takedown.
-- `published_seq` is the change feed's position the current version
-- covers: a place written since has a higher `updated_seq`, so the worker
-- knows a new version is due without any writer marking anything.
CREATE TABLE place_layer (
    singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
    version bigint NOT NULL DEFAULT 1 CHECK (version > 0),
    changed_at timestamptz NOT NULL DEFAULT now(),
    published_seq bigint NOT NULL
);
INSERT INTO place_layer (published_seq)
SELECT coalesce(max(updated_seq), 0) FROM places;

REVOKE ALL ON place_layer FROM lunaway_app, lunaway_ingest;
-- The API names the version in the tile URLs; the worker and a takedown
-- move it.
GRANT SELECT ON place_layer TO lunaway_app;
GRANT SELECT, UPDATE ON place_layer TO lunaway_ingest;
