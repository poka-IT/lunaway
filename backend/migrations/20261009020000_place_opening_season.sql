-- The season of a place whose opening hours are dates without times
-- (`Apr 01-Oct 31`, `Jan 01-Dec 31`, `24/7`; `lunaway_domain::season`):
-- the days of a leap year it is open, as one or two ranges flattened
-- (`{92,305}`, `{1,91,305,366}`), each end included. NULL when the hours
-- are no season or unknown. Such a place carries no intervals: its season
-- answers for every day, and its copy on the devices no longer changes at
-- every local midnight. The conflation writes it with the hours; the daily
-- refresh of the intervals writes it for the places whose hours it reads
-- next (`stale_openings`), which covers the places stored before.
--
-- A plain nullable column: added without rewriting the table. The writers'
-- lock first (lunaway_db::WRITER_LOCK), so a running conflation delays the
-- migration rather than failing it; then the exclusive lock of
-- `ADD COLUMN`, waited for less than the API role's own 5 s
-- (20261008140000_place_search_vector.sql). The check is added unchecked
-- and validated by the next migration.
SET LOCAL lock_timeout = '2min';
SELECT pg_advisory_xact_lock(7815274093265123683);
SET LOCAL lock_timeout = '3s';
ALTER TABLE places
    ADD COLUMN opening_season smallint[],
    -- One or two ranges of days, each in order, the second after the first
    -- with a day closed between them (as `Season::from_ranges` merges
    -- them), no NULL day: a row the readers would refuse cannot be
    -- written.
    ADD CONSTRAINT places_opening_season_days CHECK (
        opening_season IS NULL
        OR (array_position(opening_season, NULL) IS NULL
            AND cardinality(opening_season) IN (2, 4)
            AND 1 <= opening_season[1] AND opening_season[1] <= opening_season[2]
            AND opening_season[2] <= 366
            AND (cardinality(opening_season) = 2
                 OR (opening_season[2] + 1 < opening_season[3]
                     AND opening_season[3] <= opening_season[4]
                     AND opening_season[4] <= 366)))
    ) NOT VALID;

-- Whether `season` (a column above, NULL when unknown) is open on every
-- day of each range of `days` (one or two ranges flattened the same way,
-- NULL for no filter): what the filter "open on my dates" keeps, a place
-- of unknown season included. The same rule as
-- `lunaway_domain::season::Season::covers`, written for two ranges at most
-- on each side (a subscript past the end reads NULL), as one expression
-- the planner inlines into the queries.
CREATE FUNCTION lunaway_season_covers(season smallint[], days smallint[])
RETURNS boolean
LANGUAGE sql IMMUTABLE PARALLEL SAFE
AS $$
    SELECT season IS NULL OR days IS NULL OR coalesce(
        ((season[1] <= days[1] AND days[2] <= season[2])
         OR (season[3] <= days[1] AND days[2] <= season[4]))
        AND (days[3] IS NULL
             OR (season[1] <= days[3] AND days[4] <= season[2])
             OR (season[3] <= days[3] AND days[4] <= season[4])),
        false)
$$;

-- The grants of `places` are on the whole table (roles_and_grants): the API
-- reads the column, the conflation (lunaway_ingest) writes it. A function
-- is executable by every role.
