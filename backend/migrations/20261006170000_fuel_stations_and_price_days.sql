-- Fuel for a motorhome: the stations along a route or near a point, and
-- each station's price history (plan/research/23-backend-europe-packs.md,
-- "Carburant sur le trajet"). Additive: one generated column, one table.

-- Where the fuel feed puts a station, from its row: the feed's ~10 000
-- stations are the universe of `fuelNearby` and `fuelAlongRoute`, whether
-- an OpenStreetMap element names them or not. Other sources' rows have no
-- position and stay NULL. A rewrite of the table (a few seconds: about
-- 30 000 rows of the three joined sources on 2026-10-06).
ALTER TABLE poi_join_records ADD COLUMN geom geography(Point, 4326)
    GENERATED ALWAYS AS (
        CASE WHEN jsonb_typeof(data -> 'position') = 'object'
            THEN ST_SetSRID(ST_MakePoint(
                (data -> 'position' ->> 'lon')::double precision,
                (data -> 'position' ->> 'lat')::double precision), 4326)::geography
        END) STORED;

CREATE INDEX poi_join_fuel_geom_idx ON poi_join_records USING gist (geom)
    WHERE source_id = 'prix-carburants' AND deleted_at IS NULL;

-- The lowest and highest price of each station and fuel each day (Paris
-- time), as the fuel poller sees them every quarter of an hour, for 30
-- days: what `priceTrend` shows. Written by the poller only (one writer),
-- each poll raising a high or lowering a low, never rewriting a row that
-- did not move.
CREATE TABLE fuel_price_days (
    -- The station's id in the feed (`poi_join_records.ref`).
    station_ref text NOT NULL CHECK (char_length(station_ref) BETWEEN 1 AND 32),
    -- lunaway_domain::poi::FuelKind.
    fuel text NOT NULL CHECK (fuel IN ('diesel', 'sp95', 'e10', 'sp98', 'e85', 'lpg')),
    day date NOT NULL,
    low_eur double precision NOT NULL CHECK (low_eur > 0),
    high_eur double precision NOT NULL CHECK (high_eur >= low_eur),
    PRIMARY KEY (station_ref, fuel, day)
);

-- The purge of the days past the history, at each poll.
CREATE INDEX fuel_price_days_day_idx ON fuel_price_days (day);

REVOKE ALL ON fuel_price_days FROM lunaway_app, lunaway_ingest;
GRANT SELECT ON fuel_price_days TO lunaway_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON fuel_price_days TO lunaway_ingest;
