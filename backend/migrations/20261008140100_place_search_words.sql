-- Fills `places.search_vector` and indexes it, then the words of every
-- place for the correction of typos.
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

UPDATE places SET search_vector = lunaway_search_vector(name, city, municipality);

CREATE INDEX places_search_vector_idx ON places USING gin (search_vector)
    WHERE deleted_at IS NULL;

-- Every word a place was ever found under, for the correction of a typed
-- word that starts no word of any place ("chamonis" for "chamonix"): a
-- trigram similarity over these few tens of thousands of short words finds
-- the candidates in milliseconds, where the same match over every place's
-- text reads thousands of rows. The words of a place that changed or went
-- stay: a correction to a word no place holds any more finds nothing, and
-- the search goes on without it. `COLLATE "C"` so that the primary key
-- serves a prefix (`word >= w AND word < w || U+10FFFF`).
CREATE TABLE place_search_words (
    word text COLLATE "C" PRIMARY KEY CHECK (word <> '')
);

INSERT INTO place_search_words (word)
SELECT DISTINCT w FROM places, unnest(tsvector_to_array(search_vector)) AS w
WHERE deleted_at IS NULL;

CREATE INDEX place_search_words_trgm_idx ON place_search_words USING gin (word gin_trgm_ops);

-- New words come with the statement that writes them, one insert per
-- statement for a batch of places.
CREATE FUNCTION lunaway_place_search_words() RETURNS trigger
    LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO place_search_words (word)
    SELECT DISTINCT w FROM new_places, unnest(tsvector_to_array(search_vector)) AS w
    WHERE deleted_at IS NULL
    ON CONFLICT DO NOTHING;
    RETURN NULL;
END
$$;

CREATE TRIGGER places_search_words_insert AFTER INSERT ON places
    REFERENCING NEW TABLE AS new_places
    FOR EACH STATEMENT EXECUTE FUNCTION lunaway_place_search_words();
CREATE TRIGGER places_search_words_update AFTER UPDATE ON places
    REFERENCING NEW TABLE AS new_places
    FOR EACH STATEMENT EXECUTE FUNCTION lunaway_place_search_words();

REVOKE ALL ON place_search_words FROM lunaway_app, lunaway_ingest;
-- The API reads the words; the writers of places add them through the
-- trigger, which runs with their role.
GRANT SELECT ON place_search_words TO lunaway_app;
GRANT SELECT, INSERT ON place_search_words TO lunaway_ingest;

-- The search reads how many places hold a word from these statistics
-- before it chooses how to look; without them it would look up every word
-- in the index, a generic one included, until the next automatic analyze.
ANALYZE places (search_vector);
