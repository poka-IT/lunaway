-- What the low zooms of the map tiles read, computed when a layer's version
-- is published rather than for each tile (`docs/deploy.md`, "Places layer"
-- and "Points of interest"): the places' dots of zooms 2 to 9 and the
-- clusters of the points of zooms 6 to 9. On 2026-10-08 (200,961 places,
-- 1,908,026 points), a cluster tile of zoom 6 over France took the
-- production database up to 10 s, more than the API waits, and a dots tile
-- of zoom 5 1.5 s: each read every point of its square and projected it.
-- From these tables the same tiles took 4 and 45 ms on a copy of that data.
--
-- Under the POI writers' lock (`pois::begin_poi_writer`), and with
-- `place_layer` locked against its writers (every publication of the
-- places' tiles locks its row first), not against its readers: no
-- publication runs beside the fill, the API reads on. The writers of places
-- do run beside it: the dots are filled from the members, so both come from
-- one reading of the places, and a place written meanwhile is past
-- `dots_seq` and applied again by the next publication. The new tables are
-- filled before they are indexed, and nobody sees them before the commit.
SET LOCAL lock_timeout = '2min';
SELECT pg_advisory_xact_lock(7815274093148596595);
LOCK TABLE place_layer IN EXCLUSIVE MODE;
SET LOCAL lock_timeout = '10s';

-- The change feed's end before the places are read: a place written while
-- they are is past it, so the next publication applies it again (to no
-- effect when the fill saw it already).
CREATE TEMP TABLE tile_pyramids_seq ON COMMIT DROP AS
SELECT coalesce(max(updated_seq), 0) AS seq FROM places;

-- A position on a grid of 2^28 cells a side over the Web Mercator world, x
-- eastwards from 180 degrees west, y southwards from 85.05 degrees north,
-- as map tiles count: the tile of zoom z holding the point is
-- (gx >> (28 - z), gy >> (28 - z)), its pixel in a 512 px tile
-- gx >> (19 - z), its unit in a 4096 extent gx >> (16 - z). Integers, so a
-- cell of one zoom is exactly four cells of the next and sums of positions
-- are exact; the spherical formula of EPSG:3857 rather than ST_Transform,
-- several times cheaper per point. Not STRICT, so the planner inlines them
-- (a position is never NULL); a latitude past Web Mercator's edge is held
-- at the edge.
CREATE FUNCTION lunaway_grid_x(lon double precision) RETURNS integer
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT least(greatest(floor((lon + 180) / 360 * 268435456), 0), 268435455)::integer
$$;

CREATE FUNCTION lunaway_grid_y(lat double precision) RETURNS integer
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT least(greatest(floor(
        (1 - ln(tan(radians(least(greatest(lat, -85.0511287798066), 85.0511287798066)))
                + 1 / cos(radians(least(greatest(lat, -85.0511287798066), 85.0511287798066))))
             / pi()) / 2 * 268435456), 0), 268435455)::integer
$$;

-- The places' dots.
--
-- A live place as a dot: the properties the dots carry (`place_tiles.rs`:
-- the services 0 to 8 only, the price as free or paid, the height in whole
-- centimetres) and its position on the grid. Web Mercator ends at 85.05
-- degrees: a place beyond is in no tile.
CREATE VIEW place_dot_sources AS
SELECT p.id, p.kind, p.overnight AS night, p.services_mask & 511 AS s,
       CASE WHEN p.price_parking_eur = 0 THEN 0 WHEN p.price_parking_eur > 0 THEN 1 END AS price,
       -- Capped, so a wrong height in one row cannot overflow the integer.
       round(CASE WHEN p.max_height_m > 1000 THEN 1000 ELSE p.max_height_m END * 100)::integer AS h,
       lunaway_grid_x(ST_X(p.geom::geometry)) AS gx,
       lunaway_grid_y(ST_Y(p.geom::geometry)) AS gy
FROM places p
WHERE p.deleted_at IS NULL
  AND ST_Y(p.geom::geometry) BETWEEN -85.0511287798066 AND 85.0511287798066;

-- The dots a place at (gx, gy) makes, zoom 2 to 9: its pixel in its own
-- tile, and the same dot in the margin of each neighbouring tile it lies
-- within 8 pixels of, at -8 to -1 or 512 to 519 (`place_tiles::DOTS_MARGIN`).
-- MapLibre Native cuts what a tile draws at its edge: a dot of the next
-- tile that spills over is drawn only if this tile has it too.
CREATE FUNCTION lunaway_place_dot_tiles(gx integer, gy integer)
RETURNS TABLE (z smallint, tx integer, ty integer, py smallint, px smallint)
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT zoom::smallint, tx, ty, (d.y - ty * 512)::smallint, (d.x - tx * 512)::smallint
    FROM generate_series(2, 9) AS zoom
    CROSS JOIN LATERAL (SELECT gx >> (19 - zoom) AS x, gy >> (19 - zoom) AS y) d
    CROSS JOIN LATERAL generate_series(greatest((d.x - 8) >> 9, 0),
                                       least((d.x + 8) >> 9, (1 << zoom) - 1)) AS tx
    CROSS JOIN LATERAL generate_series(greatest((d.y - 8) >> 9, 0),
                                       least((d.y + 8) >> 9, (1 << zoom) - 1)) AS ty
$$;

-- Every dot of every live place, counted: what `place_dots` holds once the
-- places are published, which the tests compare it with. The positions are
-- computed once per place (MATERIALIZED), not once per dot.
CREATE VIEW place_dots_computed AS
WITH s AS MATERIALIZED (SELECT kind, night, s, price, h, gx, gy FROM place_dot_sources)
SELECT t.z, t.tx, t.ty, s.kind, s.night, s.s, s.price, s.h, t.py, t.px, count(*)::integer AS n
FROM s
CROSS JOIN LATERAL lunaway_place_dot_tiles(s.gx, s.gy) t
GROUP BY t.z, t.tx, t.ty, t.py, t.px, s.s, s.price, s.h, s.kind, s.night;

-- Each live place as the current tiles show it: a publication takes away
-- the dots of a place written since, as they are here, and adds those of
-- its new state.
CREATE TABLE place_dot_members (
    place_id uuid PRIMARY KEY,
    kind text NOT NULL,
    night text NOT NULL,
    s integer NOT NULL,
    price integer,
    h integer,
    gx integer NOT NULL,
    gy integer NOT NULL
);

-- The dots tiles, one row per dot of a tile with the number of places in
-- it; a dot goes when its last place does. The key's order is the order a
-- tile is built in (one MultiPoint per set of properties, its points row
-- by row), so a tile is read from the index alone, without a sort.
CREATE TABLE place_dots (
    z smallint NOT NULL,
    tx integer NOT NULL,
    ty integer NOT NULL,
    kind text NOT NULL,
    night text NOT NULL,
    s integer NOT NULL,
    price integer,
    h integer,
    py smallint NOT NULL,
    px smallint NOT NULL,
    n integer NOT NULL
);

INSERT INTO place_dot_members (place_id, kind, night, s, price, h, gx, gy)
SELECT id, kind, night, s, price, h, gx, gy FROM place_dot_sources;

-- From the members, not from the places again: the writers of places run
-- beside this migration, and a second reading could see a place in another
-- state than the members hold, a difference no publication would mend.
INSERT INTO place_dots (z, tx, ty, kind, night, s, price, h, py, px, n)
SELECT t.z, t.tx, t.ty, m.kind, m.night, m.s, m.price, m.h, t.py, t.px, count(*)::integer
FROM place_dot_members m
CROSS JOIN LATERAL lunaway_place_dot_tiles(m.gx, m.gy) t
GROUP BY t.z, t.tx, t.ty, t.py, t.px, m.s, m.price, m.h, m.kind, m.night;

CREATE UNIQUE INDEX place_dots_key ON place_dots
    (z, tx, ty, kind, night, s, price, h, py, px) NULLS NOT DISTINCT;
-- The dots a publication emptied, removed in the same transaction.
CREATE INDEX place_dots_emptied_idx ON place_dots (z) WHERE n <= 0;

-- The clusters of the points of interest.
--
-- Every visible point counted per zoom (6 to 9), cell of a 32 by 32 grid
-- aligned on the tile, and category, with the sum of its positions on the
-- grid for the barycentre; and again per kind for the food vending
-- machines (`kind` empty in the category's rows, `vending_other` only in
-- them). Each zoom is summed from the next one, so its counts are those of
-- its four cells. The points are read once (MATERIALIZED).
CREATE VIEW poi_cluster_cells_computed AS
WITH m AS MATERIALIZED (
    SELECT p.category,
           CASE WHEN p.category = 'vending' AND p.kind <> 'vending_other' THEN p.kind END AS kind,
           lunaway_grid_x(ST_X(p.geom::geometry)) AS gx,
           lunaway_grid_y(ST_Y(p.geom::geometry)) AS gy
    FROM pois p
    WHERE p.deleted_at IS NULL AND NOT p.hidden
      AND ST_Y(p.geom::geometry) BETWEEN -85.0511287798066 AND 85.0511287798066
),
c9 AS (
    SELECT gx >> 14 AS cx, gy >> 14 AS cy, category, ''::text AS kind,
           count(*) AS n, sum(gx) AS sx, sum(gy) AS sy
    FROM m GROUP BY gx >> 14, gy >> 14, category
    UNION ALL
    SELECT gx >> 14, gy >> 14, category, kind, count(*), sum(gx), sum(gy)
    FROM m WHERE kind IS NOT NULL GROUP BY gx >> 14, gy >> 14, category, kind
),
c8 AS (
    SELECT cx >> 1 AS cx, cy >> 1 AS cy, category, kind,
           sum(n)::bigint AS n, sum(sx)::bigint AS sx, sum(sy)::bigint AS sy
    FROM c9 GROUP BY cx >> 1, cy >> 1, category, kind
),
c7 AS (
    SELECT cx >> 1 AS cx, cy >> 1 AS cy, category, kind,
           sum(n)::bigint AS n, sum(sx)::bigint AS sx, sum(sy)::bigint AS sy
    FROM c8 GROUP BY cx >> 1, cy >> 1, category, kind
),
c6 AS (
    SELECT cx >> 1 AS cx, cy >> 1 AS cy, category, kind,
           sum(n)::bigint AS n, sum(sx)::bigint AS sx, sum(sy)::bigint AS sy
    FROM c7 GROUP BY cx >> 1, cy >> 1, category, kind
),
cells AS (
    SELECT 9 AS z, * FROM c9
    UNION ALL SELECT 8, * FROM c8
    UNION ALL SELECT 7, * FROM c7
    UNION ALL SELECT 6, * FROM c6
)
SELECT z::smallint AS z, (cx >> 5)::integer AS tx, (cy >> 5)::integer AS ty,
       ((cy & 31) * 32 + (cx & 31))::smallint AS cell, category, kind,
       n::integer AS n, sx::bigint AS sx, sy::bigint AS sy
FROM cells;

-- The clusters as the current version of the points' tiles shows them,
-- written again (only the cells that changed) when a version is published.
CREATE TABLE poi_cluster_cells (
    z smallint NOT NULL,
    tx integer NOT NULL,
    ty integer NOT NULL,
    -- cy * 32 + cx, the cell in the tile's grid.
    cell smallint NOT NULL,
    category text NOT NULL,
    -- A vending machine's kind, or empty for every point of the category.
    kind text NOT NULL,
    n integer NOT NULL,
    -- Sums of the points' grid positions: the barycentre is (sx / n, sy / n).
    sx bigint NOT NULL,
    sy bigint NOT NULL
);

INSERT INTO poi_cluster_cells (z, tx, ty, cell, category, kind, n, sx, sy)
SELECT z, tx, ty, cell, category, kind, n, sx, sy FROM poi_cluster_cells_computed;

ALTER TABLE poi_cluster_cells ADD PRIMARY KEY (z, tx, ty, cell, category, kind);

-- The planner's statistics from the first tile on, before autovacuum
-- comes by.
ANALYZE place_dot_members;
ANALYZE place_dots;
ANALYZE poi_cluster_cells;

REVOKE ALL ON place_dot_members, place_dots, poi_cluster_cells FROM lunaway_app, lunaway_ingest;
REVOKE ALL ON place_dot_sources, place_dots_computed, poi_cluster_cells_computed
    FROM lunaway_app, lunaway_ingest;
-- The API builds the tiles from the pyramids.
GRANT SELECT ON place_dots, poi_cluster_cells TO lunaway_app;
-- The worker and a takedown publish the versions, and the pyramids with
-- them.
GRANT SELECT, INSERT, UPDATE, DELETE ON place_dot_members, place_dots, poi_cluster_cells
    TO lunaway_ingest;
GRANT SELECT ON place_dot_sources, poi_cluster_cells_computed TO lunaway_ingest;

-- The dots now reach past the tile's edge and the clusters' cells are
-- aligned on it: devices keep the tiles of the current versions a year
-- (`immutable`), so both versions move and every device fetches the new
-- tiles.
UPDATE place_layer SET version = version + 1, changed_at = now(),
    dots_seq = (SELECT seq FROM tile_pyramids_seq);
UPDATE poi_layer SET version = version + 1, changed_at = now();
