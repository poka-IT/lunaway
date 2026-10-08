-- The rating a place is filtered with (the map's "minimum rating"), and may
-- be listed with: Lunaway users' average when they rated it, otherwise the
-- average of the other sources' ratings its page shows, one decimal; null
-- when nobody rated it. The worker keeps it
-- (`lunaway_db::place_ratings::refresh_filter_ratings`): the other sources'
-- ratings change with their imports, without the conflation writing the
-- place.
--
-- A plain nullable column: added without rewriting the table. The writers'
-- lock first (lunaway_db::WRITER_LOCK), so a running conflation delays the
-- migration rather than failing it; then the exclusive lock of `ADD COLUMN`,
-- waited for less than the API role's own 5 s, since every read of `places`
-- queues behind a waiting `ALTER` (20261008140000_place_search_vector.sql).
-- The range check is added unchecked: checking it here would read every row
-- under that exclusive lock. The next migration checks it under a lock that
-- lets reads and writes go on.
SET LOCAL lock_timeout = '2min';
SELECT pg_advisory_xact_lock(7815274093265123683);
SET LOCAL lock_timeout = '3s';
ALTER TABLE places
    ADD COLUMN filter_rating double precision,
    ADD CONSTRAINT places_filter_rating_range CHECK (filter_rating BETWEEN 1 AND 5) NOT VALID;

-- The grants of `places` are on the whole table (roles_and_grants): the API
-- reads the column, the worker (lunaway_ingest) writes it.
