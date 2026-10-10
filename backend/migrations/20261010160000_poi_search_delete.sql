-- A point deleted from `pois` (by hand, for an erasure: the importers
-- retire a point, they never delete one) leaves the search's copy of its
-- words and position with it. Retired and hidden points already leave it
-- through the update trigger (20261010135000_poi_search). The words no
-- point bears any more leave `poi_search_words` at the end of each import
-- of the points (`lunaway_db::poi_search::clear_words`).
CREATE FUNCTION lunaway_poi_search_delete() RETURNS trigger
    LANGUAGE plpgsql AS $$
BEGIN
    DELETE FROM poi_search s USING old_pois o WHERE s.id = o.id;
    RETURN NULL;
END
$$;

CREATE TRIGGER pois_search_delete AFTER DELETE ON pois
    REFERENCING OLD TABLE AS old_pois
    FOR EACH STATEMENT EXECUTE FUNCTION lunaway_poi_search_delete();
