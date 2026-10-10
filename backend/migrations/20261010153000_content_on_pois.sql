-- The open content of the points of interest and of the establishments
-- (docs/data-sources.md, "Open content"): a Mangrove review that no place
-- takes goes to the live point near it whose name it gives, and the
-- OpenStreetMap tags of a point name its Commons and Panoramax photos. A
-- review or a photo hangs on one place or on one point, never both, never
-- neither.
--
-- The POI writers' lock first (lunaway_db::pois::POI_WRITER_LOCK): the
-- foreign keys below lock `pois` against writes for an instant, and a
-- running import then delays the migration rather than failing it. The
-- checks and the keys are added unchecked, so the exclusive locks of
-- `ALTER TABLE` last an instant; the next migration checks them under a
-- lock that lets the API read and the content worker write meanwhile.
SET LOCAL lock_timeout = '2min';
SELECT pg_advisory_xact_lock(7815274093148596595);
SET LOCAL lock_timeout = '3s';

ALTER TABLE content_reviews
    ALTER COLUMN place_id DROP NOT NULL,
    ADD COLUMN poi_id uuid,
    ADD CONSTRAINT content_reviews_poi_id_fkey FOREIGN KEY (poi_id) REFERENCES pois (id)
        NOT VALID,
    ADD CONSTRAINT content_reviews_one_target CHECK ((place_id IS NULL) <> (poi_id IS NULL))
        NOT VALID;

ALTER TABLE content_photos
    ALTER COLUMN place_id DROP NOT NULL,
    ADD COLUMN poi_id uuid,
    ADD CONSTRAINT content_photos_poi_id_fkey FOREIGN KEY (poi_id) REFERENCES pois (id)
        NOT VALID,
    ADD CONSTRAINT content_photos_one_target CHECK ((place_id IS NULL) <> (poi_id IS NULL))
        NOT VALID;

-- One row per file, source and point, as `UNIQUE (place_id, source_id,
-- external_id)` for the places: a refresh of a point replaces its rows.
-- Every row is a place's when this runs, so the indexes are built empty.
CREATE UNIQUE INDEX content_photos_poi_key ON content_photos (poi_id, source_id, external_id)
    WHERE poi_id IS NOT NULL;
-- The reviews of a point, read when its card opens.
CREATE INDEX content_reviews_poi_idx ON content_reviews (poi_id) WHERE poi_id IS NOT NULL;

-- When each source was last asked about each point, as `content_checks`
-- for the places: a weekly pass asks the points least recently checked
-- first, and resumes where a stopped one left off.
CREATE TABLE content_poi_checks (
    poi_id uuid NOT NULL REFERENCES pois (id),
    source_id text NOT NULL REFERENCES sources (id),
    checked_at timestamptz NOT NULL,
    -- Items kept from that check.
    found integer NOT NULL CHECK (found >= 0),
    PRIMARY KEY (poi_id, source_id)
);

CREATE INDEX content_poi_checks_due_idx ON content_poi_checks (source_id, checked_at);

REVOKE ALL ON content_poi_checks FROM lunaway_app, lunaway_ingest;
-- The content worker, run as the import role, keeps it; the API never
-- reads it. The API's rights on the content tables cover their new column.
GRANT SELECT, INSERT, UPDATE, DELETE ON content_poi_checks TO lunaway_ingest;
