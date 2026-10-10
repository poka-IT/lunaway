-- Every dots tile of the published version, built once (35 s for the
-- 6 000 tiles in production on 2026-10-10, one process), so the API reads
-- them from the first request after the release instead of building them
-- (20261010150100_place_dot_tiles.sql).
--
-- Each tile is built by a lateral subquery, never by calling
-- `lunaway_place_dots_tile` per row: the same fill through that function
-- ran 20 minutes in production without finishing (zoom 7 alone, 415 tiles,
-- past 5 minutes) where a call by itself takes under a second; the cause
-- is not established. The function goes: nothing calls it.
--
-- `place_layer` locked against its writers, as in 20261008230000: no
-- publication runs beside the fill, the API reads on. The tiles are those
-- of the dots as the last publication left them; when the dots lag behind
-- the version (a version published by a release that did not keep them),
-- the version is not marked and the worker builds every tile at its next
-- run.
SET LOCAL lock_timeout = '2min';
LOCK TABLE place_layer IN EXCLUSIVE MODE;
SET LOCAL statement_timeout = '30min';

DELETE FROM place_dot_tiles;

INSERT INTO place_dot_tiles (z, tx, ty, mvt)
SELECT t.z, t.tx, t.ty, m.mvt
FROM (SELECT DISTINCT z::integer AS z, tx, ty FROM place_dots) t
CROSS JOIN LATERAL (
    SELECT coalesce(ST_AsMVT(f, 'place_dots', 512, 'geom'
                             ORDER BY f.kind, f.night, f.s, f.price, f.h, f.r, f.o1, f.o2),
                    ''::bytea) AS mvt
    FROM (
        SELECT d.kind, d.night, d.s, d.price, d.h, d.r, d.o1, d.o2,
               ST_Collect(ST_MakePoint(d.px, d.py) ORDER BY d.py, d.px) AS geom
        FROM place_dots d
        WHERE d.z = t.z AND d.tx = t.tx AND d.ty = t.ty
        GROUP BY d.kind, d.night, d.s, d.price, d.h, d.r, d.o1, d.o2
    ) f
) m
WHERE length(m.mvt) > 0;

ANALYZE place_dot_tiles;

UPDATE place_layer SET dot_tiles_version = version WHERE dots_seq >= published_seq;

DROP FUNCTION lunaway_place_dots_tile(integer, integer, integer, integer);
