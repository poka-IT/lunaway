-- no-transaction
-- The evaluation of the hours (`lunaway_db::pois::stale_hours`, in the
-- order of the refresh instant) is for the points the tiles carry: an
-- establishment's hours are read when it is served
-- (`lunaway_api::poi_types`), so its rows, which never get a refresh
-- instant, are left out of this index and never walked past.
CREATE INDEX CONCURRENTLY IF NOT EXISTS pois_tiles_opening_refresh_idx
    ON pois (opening_refresh_at NULLS FIRST)
    WHERE deleted_at IS NULL AND in_tiles
      AND (opening_hours IS NOT NULL OR laposte_ref IS NOT NULL);
