-- The joined sources (the fuel feed every quarter of an hour, La Poste,
-- FINESS) write a row only when what their source says of it changed, as
-- the imports of records and points do: rewriting every row at each run
-- doubled `poi_join_records` on an unchanged run of the three (64 to
-- 127 MB on the dev database, 2026-10-06), and the fuel poller runs 96
-- times a day.
--
-- Each run reads its source whole: once it retired what the source no
-- longer lists, it dates that read here under the scope '*', and every
-- query that serves a joined row's date reads it through `lunaway_read_at`
-- (the joined rows carry no scope). The date a user sees on a fuel price,
-- the last time Lunaway read the feed, stays exact.
ALTER TABLE source_reads
    DROP CONSTRAINT source_reads_target_check,
    ADD CONSTRAINT source_reads_target_check CHECK (target IN ('records', 'pois', 'joins'));
