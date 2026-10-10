-- The rows the photo proxy cut off the bottom of a partner's photo before
-- it made its files (`lunaway_domain::extcom::mark_band_rows`: the band the
-- source stamps its mark in). NULL for files made before the proxy cut
-- anything, or not made yet: `lunaway extcom purge-media` forgets the files
-- of a live photo made with another band than its source's (their rows
-- emptied, their files removed), so the proxy makes them again at the next
-- view.
--
-- A plain nullable column: added without rewriting the table. The writers'
-- lock first (lunaway_db::WRITER_LOCK, which the importer of the feed holds
-- while it writes its photos), so a running import delays the migration
-- rather than failing it; then the exclusive lock of `ADD COLUMN`, waited
-- for less than the API role's own 5 s, since every read of the photos
-- queues behind a waiting `ALTER` (20261008140000_place_search_vector.sql).
-- The check is added unchecked and validated by the next migration.
SET LOCAL lock_timeout = '2min';
SELECT pg_advisory_xact_lock(7815274093265123683);
SET LOCAL lock_timeout = '3s';
ALTER TABLE external_photos
    ADD COLUMN cut_rows smallint,
    -- Only files made have a cut, and a cut is a number of rows.
    ADD CONSTRAINT external_photos_cut_rows_check
        CHECK (cut_rows IS NULL OR (cut_rows >= 0 AND processed_at IS NOT NULL)) NOT VALID;

-- The API makes the files and records the cut with them, and forgets both;
-- its grants on this table are per column
-- (20261007180100_extcom_author_id_out_of_the_api.sql). The importers' are
-- on the whole table.
GRANT SELECT (cut_rows), UPDATE (cut_rows) ON external_photos TO lunaway_app;
