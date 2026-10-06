-- Taking a place down: a private home listed as a spot, a request under the
-- GDPR, a court order (docs/deploy.md, "Taking a place down"). Two steps,
-- each under the role allowed to take it:
--   1. `lunaway conflate --take-down` (the importers' role, under the
--      writers' lock) empties the place, the places merged into it and the
--      records that described them, which keep a `taken_down_at` that every
--      later import and conflation respects, and logs the takedown here;
--   2. `lunaway moderation take-down` (the API's role) then deletes the
--      community's content of the emptied place, which no longer accepts
--      any.
-- The API's role cannot take a place down: a leak of its credentials must
-- not empty the catalogue.
CREATE TABLE place_takedowns (
    -- The place taken down, merges followed to the last.
    place_id uuid PRIMARY KEY REFERENCES places (id),
    -- Why: the kind of request and its reference, never the requester's
    -- personal data. The first one is kept when the command runs again.
    reason text NOT NULL CHECK (length(reason) BETWEEN 1 AND 500),
    taken_down_at timestamptz NOT NULL DEFAULT now()
);

-- A taken-down record is never written again by an import, though its
-- source may still list it; a taken-down place is never revived by the
-- conflation, and the change feed hands its tombstone to every device that
-- syncs by box, since it keeps no position to filter on.
ALTER TABLE places ADD COLUMN taken_down_at timestamptz;
ALTER TABLE source_records ADD COLUMN taken_down_at timestamptz;
CREATE INDEX places_taken_down_seq_idx ON places (updated_seq) WHERE taken_down_at IS NOT NULL;

-- The place a record was linked to when the conflation unlinked it (a
-- record its source retired, a group held back), written at the unlink
-- only: a takedown empties those records too, or one listed again by its
-- source would bring the place back. A linked record is found through its
-- link. A hint, not a reference: the places it names are never deleted.
ALTER TABLE source_records ADD COLUMN last_place_id uuid;
CREATE INDEX source_records_last_place_idx ON source_records (last_place_id)
    WHERE last_place_id IS NOT NULL;

-- The planner learns now that the new column of `places` is empty: a box
-- of the change feed (`places::changes`) then reads the two indexes, not
-- the whole table in feed order, until the next automatic analyze.
ANALYZE places;

REVOKE ALL ON place_takedowns FROM lunaway_app, lunaway_ingest;
GRANT SELECT, INSERT ON place_takedowns TO lunaway_ingest;
