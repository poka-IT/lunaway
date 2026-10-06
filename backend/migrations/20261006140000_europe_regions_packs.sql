-- Europe, sync regions, regional first-sync packs, opening windows per time
-- zone and the coalesced version of the points layer
-- (plan/research/23-backend-europe-packs.md). Additive: new columns are
-- nullable or generated, one new table.

-- The country an OpenStreetMap point was imported under: a run of several
-- country extracts retires only the points of the countries it read.
-- Points imported before carry none and count as French (the only country
-- imported before), until the next import tags them.
ALTER TABLE pois ADD COLUMN scope text;

-- When the opening window of a place or a point must move: the next local
-- midnight after the first day of its window, in the zone of its country.
-- The worker compares it with the current instant, so a place in Lisbon and
-- one in Helsinki each move at their own midnight. NULL asks for an
-- evaluation (rows written before this column, and new hours).
ALTER TABLE places ADD COLUMN opening_refresh_at timestamptz;
ALTER TABLE pois ADD COLUMN opening_refresh_at timestamptz;
CREATE INDEX pois_opening_refresh_idx ON pois (opening_refresh_at NULLS FIRST)
    WHERE deleted_at IS NULL AND (opening_hours IS NOT NULL OR laposte_ref IS NOT NULL);

-- The sync region of a place: the French region of its commune in France,
-- `FR` for a French place outside every commune, the region around a
-- microstate, the country elsewhere. lunaway_domain::region::sync_region_of
-- says the same; lunaway-db/tests/regions.rs holds the two together.
CREATE FUNCTION lunaway_sync_region(country text, commune text) RETURNS text
    LANGUAGE sql IMMUTABLE PARALLEL SAFE
    RETURN CASE
        WHEN country IS NULL THEN NULL
        WHEN upper(country) = 'FR' THEN coalesce(
            CASE
                WHEN left(commune, 2) IN ('01', '03', '07', '15', '26', '38', '42', '43', '63',
                                          '69', '73', '74') THEN 'FR-ARA'
                WHEN left(commune, 2) IN ('21', '25', '39', '58', '70', '71', '89', '90')
                    THEN 'FR-BFC'
                WHEN left(commune, 2) IN ('22', '29', '35', '56') THEN 'FR-BRE'
                WHEN left(commune, 2) IN ('18', '28', '36', '37', '41', '45') THEN 'FR-CVL'
                WHEN left(commune, 2) IN ('2A', '2B') THEN 'FR-20R'
                WHEN left(commune, 2) IN ('08', '10', '51', '52', '54', '55', '57', '67', '68',
                                          '88') THEN 'FR-GES'
                WHEN left(commune, 2) IN ('02', '59', '60', '62', '80') THEN 'FR-HDF'
                WHEN left(commune, 2) IN ('75', '77', '78', '91', '92', '93', '94', '95')
                    THEN 'FR-IDF'
                WHEN left(commune, 2) IN ('14', '27', '50', '61', '76') THEN 'FR-NOR'
                WHEN left(commune, 2) IN ('16', '17', '19', '23', '24', '33', '40', '47', '64',
                                          '79', '86', '87') THEN 'FR-NAQ'
                WHEN left(commune, 2) IN ('09', '11', '12', '30', '31', '32', '34', '46', '48',
                                          '65', '66', '81', '82') THEN 'FR-OCC'
                WHEN left(commune, 2) IN ('44', '49', '53', '72', '85') THEN 'FR-PDL'
                WHEN left(commune, 2) IN ('04', '05', '06', '13', '83', '84') THEN 'FR-PAC'
            END,
            'FR')
        WHEN upper(country) = 'MC' THEN 'FR-PAC'
        WHEN upper(country) IN ('AD', 'GI') THEN 'ES'
        WHEN upper(country) IN ('SM', 'VA') THEN 'IT'
        WHEN upper(country) = 'LI' THEN 'CH'
        WHEN upper(country) = 'SJ' THEN 'NO'
        WHEN upper(country) = 'AX' THEN 'FI'
        ELSE upper(country)
    END;

-- Computed by PostgreSQL, so a new commune file or a corrected country moves
-- the place to its region in the same statement. A rewrite of `places` (a
-- few seconds for France).
ALTER TABLE places ADD COLUMN region text
    GENERATED ALWAYS AS (lunaway_sync_region(country_code, municipality_code)) STORED;

-- `changes(region:)` and the pack builder read a region's places in feed
-- order.
CREATE INDEX places_region_seq_idx ON places (region, updated_seq);

-- A change of what a tile shows marks the layer; the worker publishes a new
-- version at most every few hours (`lunaway conflate --poi-layer-every`),
-- so a fuel price poll every 15 minutes does not make every device fetch
-- its tiles again. NULL when nothing waits.
ALTER TABLE poi_layer ADD COLUMN pending_since timestamptz;

-- One downloadable pack per sync region: every live place of the region
-- at the feed position `seq` of the feed named `feed_identity`, in a file
-- the backend serves as is (`LUNAWAY_PACKS_DIR`). Written by `lunaway packs
-- build` (the import role), read by the API (`Query.regions`).
CREATE TABLE region_packs (
    region text PRIMARY KEY CHECK (region ~ '^[A-Z]{2}(-[A-Z0-9]{1,3})?$'),
    seq bigint NOT NULL CHECK (seq >= 0),
    feed_identity text NOT NULL CHECK (feed_identity ~ '^[0-9a-f]{40}$'),
    places integer NOT NULL CHECK (places >= 0),
    south double precision NOT NULL,
    west double precision NOT NULL,
    north double precision NOT NULL,
    east double precision NOT NULL,
    -- Path under the packs directory, `places/<region>-<seq>-<hash>.sqlite.gz`.
    file text NOT NULL CHECK (file ~ '^places/[A-Za-z0-9._-]+$'),
    format text NOT NULL,
    bytes bigint NOT NULL CHECK (bytes > 0),
    raw_bytes bigint NOT NULL CHECK (raw_bytes > 0),
    sha256 text NOT NULL CHECK (sha256 ~ '^[0-9a-f]{64}$'),
    generated_at timestamptz NOT NULL DEFAULT now()
);

REVOKE ALL ON region_packs FROM lunaway_app, lunaway_ingest;
GRANT SELECT ON region_packs TO lunaway_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON region_packs TO lunaway_ingest;
