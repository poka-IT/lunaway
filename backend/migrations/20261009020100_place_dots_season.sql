-- The season of the places (migration 20261009020000) in the dots kept per
-- version: `o1` and `o2`, each range as first day * 1000 + last day, as the
-- pins carry them (`lunaway_db::place_tiles::tile`). The filter on the
-- dates of a stay keeps a dot exactly when it keeps one of its places,
-- since a dot's places share their season.
--
-- No place has a season yet: the column is new, and the release before
-- does not know it. The dots and their members are therefore right as
-- they are, with no season, and nothing is rebuilt: the running API keeps
-- reading the dots while this runs, where a refill would hold them under
-- `TRUNCATE` for the half minute 20261008230000 took on production. The
-- places get their season from the conflation and the daily refresh, and
-- each publication then moves their dots, as for any change. The guard
-- below fails the deploy rather than leave a place's dots without its
-- season.
-- The writers of the dots first (`place_layer`, as 20261008230000): a
-- publication running at deploy time delays the migration rather than
-- failing it, and the API's reads go on.
SET LOCAL lock_timeout = '2min';
LOCK TABLE place_layer IN EXCLUSIVE MODE;
SET LOCAL lock_timeout = '3s';

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM places WHERE opening_season IS NOT NULL) THEN
        RAISE EXCEPTION 'places have a season already: their dots would miss it';
    END IF;
END
$$;

-- `o1` and `o2` appended: a view keeps its columns' order when replaced.
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
       END AS r,
       p.opening_season[1] * 1000 + p.opening_season[2] AS o1,
       p.opening_season[3] * 1000 + p.opening_season[4] AS o2
FROM places p
WHERE p.deleted_at IS NULL
  AND ST_Y(p.geom::geometry) BETWEEN -85.0511287798066 AND 85.0511287798066;

DROP VIEW place_dots_computed;
CREATE VIEW place_dots_computed AS
WITH s AS MATERIALIZED (SELECT kind, night, s, price, h, r, o1, o2, gx, gy FROM place_dot_sources)
SELECT t.z, t.tx, t.ty, s.kind, s.night, s.s, s.price, s.h, s.r, s.o1, s.o2, t.py, t.px,
       count(*)::integer AS n
FROM s
CROSS JOIN LATERAL lunaway_place_dot_tiles(s.gx, s.gy) t
GROUP BY t.z, t.tx, t.ty, t.py, t.px, s.s, s.price, s.h, s.r, s.o1, s.o2, s.kind, s.night;
REVOKE ALL ON place_dots_computed FROM lunaway_app, lunaway_ingest;

-- Nullable columns without a default: added without rewriting or reading
-- the tables, each lock released at this migration's commit.
ALTER TABLE place_dot_members ADD COLUMN o1 integer, ADD COLUMN o2 integer;
ALTER TABLE place_dots ADD COLUMN o1 integer, ADD COLUMN o2 integer;
