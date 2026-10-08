-- The filters' minimum rating in the places' dots kept per version: `r`,
-- the place's `filter_rating` (migration 20261008220000) in tenths cut to
-- the steps the app offers (`place_tiles::DOTS_RATING_STEPS`: 45 from 4.5,
-- 40 from 4, 30 from 3, none below), as the dots tiles carried it when
-- they read the places directly. A filter at a step keeps a dot exactly
-- when it keeps one of its places, since a dot's places share its step.
--
-- After both 20261008210100 (the dots) and 20261008220000 (the rating),
-- whichever ran first: on a new database the dots come first, on the
-- production database of 2026-10-08 the rating was already there.
--
-- `place_layer` locked against its writers, as in 20261008210100: no
-- publication runs beside the refill, the API reads on. The members and
-- the dots are written again whole, the dots from the members; a place
-- written meanwhile is past `dots_seq` and applied again by the next
-- publication. `TRUNCATE` locks the two tables against their readers too:
-- this migration ships with the release that first reads them, whose API
-- starts after it.
SET LOCAL lock_timeout = '2min';
LOCK TABLE place_layer IN EXCLUSIVE MODE;
SET LOCAL lock_timeout = '10s';

-- The change feed's end before the places are read.
CREATE TEMP TABLE place_dots_rating_seq ON COMMIT DROP AS
SELECT coalesce(max(updated_seq), 0) AS seq FROM places;

-- `r` appended: a view keeps its columns' order when replaced.
CREATE OR REPLACE VIEW place_dot_sources AS
SELECT p.id, p.kind, p.overnight AS night, p.services_mask & 511 AS s,
       CASE WHEN p.price_parking_eur = 0 THEN 0 WHEN p.price_parking_eur > 0 THEN 1 END AS price,
       -- Capped, so a wrong height in one row cannot overflow the integer.
       round(CASE WHEN p.max_height_m > 1000 THEN 1000 ELSE p.max_height_m END * 100)::integer AS h,
       lunaway_grid_x(ST_X(p.geom::geometry)) AS gx,
       lunaway_grid_y(ST_Y(p.geom::geometry)) AS gy,
       CASE WHEN round(p.filter_rating * 10)::integer >= 45 THEN 45
            WHEN round(p.filter_rating * 10)::integer >= 40 THEN 40
            WHEN round(p.filter_rating * 10)::integer >= 30 THEN 30
       END AS r
FROM places p
WHERE p.deleted_at IS NULL
  AND ST_Y(p.geom::geometry) BETWEEN -85.0511287798066 AND 85.0511287798066;

DROP VIEW place_dots_computed;
CREATE VIEW place_dots_computed AS
WITH s AS MATERIALIZED (SELECT kind, night, s, price, h, r, gx, gy FROM place_dot_sources)
SELECT t.z, t.tx, t.ty, s.kind, s.night, s.s, s.price, s.h, s.r, t.py, t.px,
       count(*)::integer AS n
FROM s
CROSS JOIN LATERAL lunaway_place_dot_tiles(s.gx, s.gy) t
GROUP BY t.z, t.tx, t.ty, t.py, t.px, s.s, s.price, s.h, s.r, s.kind, s.night;

TRUNCATE place_dot_members, place_dots;
ALTER TABLE place_dot_members ADD COLUMN r integer;
ALTER TABLE place_dots ADD COLUMN r integer;
DROP INDEX place_dots_key;

INSERT INTO place_dot_members (place_id, kind, night, s, price, h, r, gx, gy)
SELECT id, kind, night, s, price, h, r, gx, gy FROM place_dot_sources;

INSERT INTO place_dots (z, tx, ty, kind, night, s, price, h, r, py, px, n)
SELECT t.z, t.tx, t.ty, m.kind, m.night, m.s, m.price, m.h, m.r, t.py, t.px, count(*)::integer
FROM place_dot_members m
CROSS JOIN LATERAL lunaway_place_dot_tiles(m.gx, m.gy) t
GROUP BY t.z, t.tx, t.ty, t.py, t.px, m.s, m.price, m.h, m.r, m.kind, m.night;

-- The order a tile is built in, the step with the other properties.
CREATE UNIQUE INDEX place_dots_key ON place_dots
    (z, tx, ty, kind, night, s, price, h, r, py, px) NULLS NOT DISTINCT;

ANALYZE place_dot_members;
ANALYZE place_dots;

REVOKE ALL ON place_dots_computed FROM lunaway_app, lunaway_ingest;

-- The last migration of the release moves both versions: a tile the
-- release before built meanwhile under the versions of 20261008210100 is
-- then kept by no device.
UPDATE place_layer SET version = version + 1, changed_at = now(),
    dots_seq = (SELECT seq FROM place_dots_rating_seq);
UPDATE poi_layer SET version = version + 1, changed_at = now();
