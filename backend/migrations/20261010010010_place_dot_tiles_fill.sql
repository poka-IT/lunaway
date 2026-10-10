-- Every dots tile of the published version, built once (44 s in production
-- on 2026-10-10), so the API reads them from the first request after the
-- release instead of building them (20261010010000_place_dot_tiles.sql).
--
-- `place_layer` locked against its writers, as in 20261008230000: no
-- publication runs beside the fill, the API reads on. The tiles are those
-- of the dots as the last publication left them; when the dots lag behind
-- the version (a version published by a release that did not keep them),
-- the version is not marked and the next publication builds every tile.
SET LOCAL lock_timeout = '2min';
LOCK TABLE place_layer IN EXCLUSIVE MODE;
SET LOCAL statement_timeout = '30min';

INSERT INTO place_dot_tiles (z, tx, ty, mvt)
SELECT b.z, b.tx, b.ty, b.mvt
FROM (
    SELECT t.z, t.tx, t.ty, lunaway_place_dots_tile(t.z, t.tx, t.ty, 512) AS mvt
    FROM (SELECT DISTINCT z::integer AS z, tx, ty FROM place_dots) t
) b
WHERE length(b.mvt) > 0;

ANALYZE place_dot_tiles;

UPDATE place_layer SET dot_tiles_version = version WHERE dots_seq >= published_seq;
