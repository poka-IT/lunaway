-- no-transaction
-- The boxes of the tiled points (`lunaway_db::pois::tile`, `in_bbox`):
-- the establishments the next imports add are never walked past by a tile.
-- Built without blocking the writers, outside a transaction, one index per
-- migration (a statement CONCURRENTLY cannot share its migration).
CREATE INDEX CONCURRENTLY IF NOT EXISTS pois_tiles_box_idx ON pois USING gist ((geom::geometry))
    WHERE deleted_at IS NULL AND NOT hidden AND in_tiles;
