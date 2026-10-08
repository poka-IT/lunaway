-- Fills `places.search_vector` and indexes it, then the words of the live
-- places for the correction of typos.
--
-- Under the writers' lock (lunaway_db::WRITER_LOCK): a conflation running
-- beside the update would lock the same rows in another order. A writer
-- holding it for long fails the migration rather than holding the deploy.
-- The update takes row locks only, which the API's reads do not wait for;
-- the index build blocks writes, which the lock already holds back, for
-- about a second (0.9 s for the 89,000 places of 2026-10-07 on a 2-vCPU
-- server).
SET LOCAL lock_timeout = '2min';
SELECT pg_advisory_xact_lock(7815274093265123683);
SET LOCAL lock_timeout = '10s';

-- The trigger of the previous migration computes the column it is set.
UPDATE places SET search_vector = NULL;

-- Without the pending list a GIN index keeps by default: every lookup scans
-- that list whole, and a conflation's batch fills it right before the
-- trigger below looks words up (7.3 s to tombstone 5,000 places with it,
-- 0.7 s without; 0.6 s without the triggers at all).
CREATE INDEX places_search_vector_idx ON places USING gin (search_vector)
    WITH (fastupdate = off) WHERE deleted_at IS NULL;

-- The words of the live places, for the correction of a typed word that
-- starts none of them ("chamonis" for "chamonix"): a trigram similarity
-- over these few tens of thousands of short words finds the candidates in
-- milliseconds, where the same match over every place's text reads
-- thousands of rows. `COLLATE "C"` so that the primary key serves a prefix
-- (`word >= w AND word < w || U+10FFFF`).
CREATE TABLE place_search_words (
    word text COLLATE "C" PRIMARY KEY CHECK (word <> '')
);

INSERT INTO place_search_words (word)
SELECT DISTINCT w FROM places, unnest(tsvector_to_array(search_vector)) AS w
WHERE deleted_at IS NULL;

CREATE INDEX place_search_words_trgm_idx ON place_search_words USING gin (word gin_trgm_ops);

-- The words follow the statement that writes places, once per statement
-- for a batch, in word order so that two writers could not deadlock on
-- them. A word leaves when no live place holds it any more: a place
-- renamed, merged or taken down under a request (whose name is erased,
-- `lunaway_db::takedowns`) leaves no word of its own behind for a typo to
-- be corrected to. Only the places whose words changed are looked at, so
-- the updates of what the search does not read cost a join.
CREATE FUNCTION lunaway_place_search_words_insert() RETURNS trigger
    LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO place_search_words (word)
    SELECT DISTINCT w FROM new_places, unnest(tsvector_to_array(search_vector)) AS w
    WHERE deleted_at IS NULL
    ORDER BY w
    ON CONFLICT DO NOTHING;
    RETURN NULL;
END
$$;

CREATE FUNCTION lunaway_place_search_words_update() RETURNS trigger
    LANGUAGE plpgsql AS $$
BEGIN
    -- Most updates change no word (a place's summary, one place at a time).
    IF NOT EXISTS (
        SELECT 1 FROM old_places o JOIN new_places n ON n.id = o.id
        WHERE o.search_vector IS DISTINCT FROM n.search_vector
           OR o.deleted_at IS DISTINCT FROM n.deleted_at) THEN
        RETURN NULL;
    END IF;
    INSERT INTO place_search_words (word)
    SELECT DISTINCT w
    FROM old_places o
    JOIN new_places n ON n.id = o.id,
         unnest(tsvector_to_array(n.search_vector)) AS w
    WHERE n.deleted_at IS NULL
      AND (o.search_vector IS DISTINCT FROM n.search_vector OR o.deleted_at IS NOT NULL)
    ORDER BY w
    ON CONFLICT DO NOTHING;
    -- The words the statement took from a live place, but neither those it
    -- gave one nor the most common ones: thousands of places hold each of
    -- those, and the check of one reads its whole list in the index (3.8 s
    -- for 5,000 places renamed, against 1 s without the triggers).
    DELETE FROM place_search_words x
    WHERE x.word IN (
            SELECT w
            FROM old_places o
            JOIN new_places n ON n.id = o.id,
                 unnest(tsvector_to_array(o.search_vector)) AS w
            WHERE o.deleted_at IS NULL
              AND (o.search_vector IS DISTINCT FROM n.search_vector OR n.deleted_at IS NOT NULL)
            EXCEPT
            SELECT w FROM new_places, unnest(tsvector_to_array(search_vector)) AS w
            WHERE deleted_at IS NULL
            EXCEPT
            SELECT unnest(most_common_elems::text::text[]) FROM pg_stats
            WHERE schemaname = 'public' AND tablename = 'places' AND attname = 'search_vector')
      AND NOT EXISTS (
            SELECT 1 FROM places p
            WHERE p.deleted_at IS NULL AND p.search_vector @@ quote_literal(x.word)::tsquery);
    RETURN NULL;
END
$$;

CREATE TRIGGER places_search_words_insert AFTER INSERT ON places
    REFERENCING NEW TABLE AS new_places
    FOR EACH STATEMENT EXECUTE FUNCTION lunaway_place_search_words_insert();
CREATE TRIGGER places_search_words_update AFTER UPDATE ON places
    REFERENCING OLD TABLE AS old_places NEW TABLE AS new_places
    FOR EACH STATEMENT EXECUTE FUNCTION lunaway_place_search_words_update();

REVOKE ALL ON place_search_words FROM lunaway_app, lunaway_ingest;
-- The API reads the words; the writers of places keep them through the
-- triggers, which run with their role.
GRANT SELECT ON place_search_words TO lunaway_app;
GRANT SELECT, INSERT, DELETE ON place_search_words TO lunaway_ingest;

-- The search reads how many places hold a word from these statistics
-- before it chooses how to look; without them it would look up every word
-- in the index, a generic one included, until the next automatic analyze.
ANALYZE places (search_vector);
