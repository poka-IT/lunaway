-- The rating the filters use (`places.filter_rating`) becomes every
-- source's ratings together, each rating weighing the same: Lunaway users'
-- and the other sources' (the external community source's summaries, the
-- open sources' reviews), their mean weighted by how many ratings each
-- counts, one decimal. Until now Lunaway users' average replaced the
-- others as soon as one user rated a place: a single rating of 4 turned
-- 246 ratings of 3.3 elsewhere into a 4.0 that the filter "4 and more"
-- kept (UX audit of 2026-10-10, M7).
--
-- Two writers set the rating: the worker's periodic pass over every place
-- (`lunaway_db::place_ratings`), which reads the other sources, and the
-- community summary of one place (`lunaway_db::summary`), written when a
-- user rates it. The pass keeps what it read of the other sources here,
-- so the summary combines a new rating with them at once, and both apply
-- the one rule below.
--
-- A table of its own rather than columns of `places`: the pass writes a
-- row whenever another source's ratings move, which must neither write the
-- place (its statement triggers, the change feed) nor wait for its locks.
-- No foreign key: a place is never deleted, and the key would lock
-- `places` against writes while this migration adds it. The pass removes
-- the rows of the places that are not live.
CREATE TABLE place_other_ratings (
    place_id uuid PRIMARY KEY,
    -- The sum of every other rating, an average times its count.
    total double precision NOT NULL,
    -- How many ratings that sum holds.
    n bigint NOT NULL CHECK (n > 0)
);

-- The worker computes the ratings with the import role; the API reads the
-- stored `filter_rating` only.
GRANT SELECT, INSERT, UPDATE, DELETE ON place_other_ratings TO lunaway_ingest;

-- The filters' rating of a place from Lunaway users' average and count and
-- the other sources' sum and count: every rating weighs the same, one
-- decimal, rounded half up; null when nobody rated the place. A user
-- count of 0 is no rating, whatever the average says. Pure, so every role
-- may run it, as `lunaway_season_covers`.
CREATE FUNCTION lunaway_filter_rating(
    own_avg double precision,
    own_n integer,
    other_total double precision,
    other_n bigint
) RETURNS double precision
LANGUAGE sql IMMUTABLE PARALLEL SAFE
RETURN round((
    (CASE WHEN own_n > 0 AND own_avg IS NOT NULL THEN own_avg * own_n ELSE 0 END
     + CASE WHEN other_n > 0 THEN coalesce(other_total, 0) ELSE 0 END)
    / nullif(CASE WHEN own_n > 0 AND own_avg IS NOT NULL THEN own_n ELSE 0 END
             + CASE WHEN other_n > 0 THEN other_n ELSE 0 END, 0)
)::numeric, 1)::double precision;
