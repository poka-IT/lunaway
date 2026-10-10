-- The places' dots tiles (zooms 2 to 9) as bytes, built by each publication
-- of the places layer for the tiles whose dots it changed, so that the API
-- reads a tile instead of building it.
--
-- Built at a request, a tile of zoom 2 to 5 holds up to 255 000 dots (3/4/2,
-- eastern Europe, 1 MB) and took the production database 1 to 7 s: past
-- the API's 4 s, the request was answered 503, the tile stayed out of the
-- cache, and a first launch on 2026-10-09 showed the east of Europe empty
-- for 40 to 90 s while the map asked again (audit of 2026-10-10, M9). Every
-- tile of zooms 2 to 9 together took 44 s to build and weigh 25 MB
-- (production, 2026-10-10); a publication rebuilds only those it touched.
--
-- `place_layer.dot_tiles_version` is the version the stored tiles are
-- complete for: the API reads them only when it is the current version,
-- and builds a tile from `place_dots` otherwise (after a publication by a
-- release that does not store them, until the next one rebuilds them all).
--
-- The column in a migration of its own: adding it locks `place_layer`
-- against every reader, for an instant here; the next migration fills the
-- tiles under a lock that lets the readers go on
-- (20261008210000_place_layer_dots_seq.sql).
SET LOCAL lock_timeout = '10s';
ALTER TABLE place_layer ADD COLUMN dot_tiles_version bigint;

-- A tile with no dot has no row: the API answers it empty.
CREATE TABLE place_dot_tiles (
    z integer NOT NULL,
    tx integer NOT NULL,
    ty integer NOT NULL,
    mvt bytea NOT NULL CHECK (length(mvt) > 0),
    PRIMARY KEY (z, tx, ty)
);

-- The dots tile `z/tx/ty` at `extent` units a side, from `place_dots`: one
-- MultiPoint per set of properties, its points row by row, in the order
-- of the dots' key (a third smaller once compressed at zoom 5), the same
-- bytes from the same dots whatever plan reads them. Empty bytes when the
-- tile holds no dot. The API's own build when the stored tiles are not
-- those of the current version, and every publication's.
CREATE FUNCTION lunaway_place_dots_tile(integer, integer, integer, integer)
RETURNS bytea LANGUAGE sql STABLE PARALLEL SAFE AS $$
    SELECT coalesce(ST_AsMVT(f, 'place_dots', $4, 'geom'
                             ORDER BY f.kind, f.night, f.s, f.price, f.h, f.r, f.o1, f.o2),
                    ''::bytea)
    FROM (
        SELECT d.kind, d.night, d.s, d.price, d.h, d.r, d.o1, d.o2,
               ST_Collect(ST_MakePoint(d.px, d.py) ORDER BY d.py, d.px) AS geom
        FROM place_dots d
        WHERE d.z = $1 AND d.tx = $2 AND d.ty = $3
        GROUP BY d.kind, d.night, d.s, d.price, d.h, d.r, d.o1, d.o2
    ) f
$$;

REVOKE ALL ON place_dot_tiles FROM lunaway_app, lunaway_ingest;
-- The API serves the tiles; the worker and a takedown publish them.
GRANT SELECT ON place_dot_tiles TO lunaway_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON place_dot_tiles TO lunaway_ingest;
