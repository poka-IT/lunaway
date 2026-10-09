-- The key of the dots with the season (20261009020100): the order a tile
-- is built in, the season with the other properties, so a publication
-- adds to the dot of a place's season (`place_tiles::apply_dots`).
--
-- The new index is built first, under a lock that lets the API read the
-- dots meanwhile and holds a publication back for the seconds it takes;
-- every row has no season yet, so the old key's uniqueness carries over.
-- Only then the old one goes, its exclusive lock held for the end of
-- this transaction alone. The release before still names the old key in
-- its publications: one that runs after this migration and before the new
-- release starts fails, and the new worker publishes it again (the
-- position of the dots does not move on a failure).
-- The writers of the dots first (`place_layer`, as 20261008230000): a
-- publication running at deploy time delays the migration rather than
-- failing it, and the API's reads go on.
SET LOCAL lock_timeout = '2min';
LOCK TABLE place_layer IN EXCLUSIVE MODE;
SET LOCAL lock_timeout = '3s';

CREATE UNIQUE INDEX place_dots_key_season ON place_dots
    (z, tx, ty, kind, night, s, price, h, r, o1, o2, py, px) NULLS NOT DISTINCT;
DROP INDEX place_dots_key;
ALTER INDEX place_dots_key_season RENAME TO place_dots_key;
