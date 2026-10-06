-- Follow-up of 20261006140000_europe_regions_packs, after its review
-- (plan/research/23-backend-europe-packs.md, part 7).
--
-- A place that leaves a sync region (its commune or its country changed) is
-- reported to the devices that keep that region: the change feed of the
-- region lists it as deleted from the position at which it left, and the
-- region's pack is built again. Without this, a device that keeps only the
-- old region kept the place for good. Filled by a trigger, so no writer of
-- places can forget it; `places.region` is a generated column, which an
-- AFTER trigger sees.
CREATE TABLE place_region_exits (
    place_id uuid NOT NULL REFERENCES places (id),
    region text NOT NULL,
    seq bigint NOT NULL,
    PRIMARY KEY (region, seq, place_id)
);

CREATE FUNCTION lunaway_place_region_exit() RETURNS trigger
    LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO place_region_exits (place_id, region, seq)
    VALUES (OLD.id, OLD.region, NEW.updated_seq);
    RETURN NULL;
END
$$;

CREATE TRIGGER places_region_exit
    AFTER UPDATE ON places
    FOR EACH ROW
    WHEN (OLD.region IS NOT NULL AND OLD.region IS DISTINCT FROM NEW.region)
    EXECUTE FUNCTION lunaway_place_region_exit();

REVOKE ALL ON place_region_exits FROM lunaway_app, lunaway_ingest;
-- The API reads them for the feed; the writers of places add them through
-- the trigger, which runs with their role.
GRANT SELECT ON place_region_exits TO lunaway_app;
GRANT SELECT, INSERT ON place_region_exits TO lunaway_ingest;

-- What a pack was built with besides its places: its format, the selection
-- of fields and the photos' public URL. A pack built otherwise is built
-- again even when its region did not change.
ALTER TABLE region_packs ADD COLUMN fingerprint text;

-- `places.region` is stored: replacing `lunaway_sync_region` later does not
-- recompute it. A new rule comes with a statement that rewrites the column
-- (an UPDATE of `country_code` to itself on every place does).
COMMENT ON FUNCTION lunaway_sync_region(text, text) IS
    'Stored in places.region: replacing it does not recompute existing rows.';
