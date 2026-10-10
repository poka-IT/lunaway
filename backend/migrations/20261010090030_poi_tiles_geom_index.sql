-- no-transaction
-- "Around this place" (`lunaway_db::pois::nearby`, distance on geography)
-- reads the tiled points: the establishments are not walked past.
CREATE INDEX CONCURRENTLY IF NOT EXISTS pois_tiles_geom_idx ON pois USING gist (geom)
    WHERE deleted_at IS NULL AND NOT hidden AND in_tiles;
