-- The cells of the points' positions among their words, so that a search
-- around a point reads the matches near it first (`lunaway_db::poi_search`,
-- `lunaway_domain::poi_search::CELL_LENGTHS`).
--
-- On production on 2026-10-10, with 3.6 million points, a search by kind
-- walked out from the map's centre through every point until it had 40 of
-- the kind (10,963 for the launderettes around Paris, 211 to 268 ms), and
-- a chain's name ranked all of its shops in Europe (8,524 McDonald's: 62 ms
-- with every page in memory, seconds from the disk). Each point now also
-- bears `h_<geohash>` for the cells of 3, 4, 5 and 6 characters holding
-- it: the index finds the matches in the nine cells around the point
-- asked, and only those rows are read.
--
-- The table is written again rather than updated, in the order of the
-- cells, so that the rows of one neighbourhood share their pages: a search
-- that misses the cache reads a few pages, not one per match. Under the
-- POI writers' lock, as the table's first fill: a writer running beside it
-- would write rows the copy does not see. The API keeps reading the old
-- table until the swap at the end.
SET LOCAL lock_timeout = '2min';
SELECT pg_advisory_xact_lock(7815274093148596595);
SET LOCAL lock_timeout = '10s';

CREATE FUNCTION lunaway_poi_cells(g geography) RETURNS tsvector
    LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE
    RETURN array_to_tsvector(ARRAY[
        'h_' || ST_GeoHash(g::geometry, 3), 'h_' || ST_GeoHash(g::geometry, 4),
        'h_' || ST_GeoHash(g::geometry, 5), 'h_' || ST_GeoHash(g::geometry, 6)]);

-- The words written from the rows a statement wrote (RETURNING), never
-- read back from the table: reading them back fetched a row of the table
-- for every point of a batch, changed or not.
CREATE OR REPLACE FUNCTION lunaway_poi_search_insert() RETURNS trigger
    LANGUAGE plpgsql AS $$
BEGIN
    WITH added AS (
        INSERT INTO poi_search (id, source_id, kind, geom, words, name_length)
        SELECT id, source_id, kind, geom,
               lunaway_poi_words(name, brand, kind, category, data -> 'cuisine')
                   || lunaway_poi_cells(geom),
               char_length(coalesce(name, brand, ''))
        FROM new_pois
        WHERE deleted_at IS NULL AND NOT hidden
        ON CONFLICT (id) DO NOTHING
        RETURNING words
    )
    INSERT INTO poi_search_words (word)
    SELECT DISTINCT w
    FROM added, unnest(tsvector_to_array(added.words)) AS w
    WHERE strpos(w, '_') = 0
    ORDER BY w
    ON CONFLICT DO NOTHING;
    RETURN NULL;
END
$$;

CREATE OR REPLACE FUNCTION lunaway_poi_search_update() RETURNS trigger
    LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM old_pois o JOIN new_pois n ON n.id = o.id
        WHERE o.name IS DISTINCT FROM n.name
           OR o.brand IS DISTINCT FROM n.brand
           OR o.kind IS DISTINCT FROM n.kind
           OR o.category IS DISTINCT FROM n.category
           OR o.source_id IS DISTINCT FROM n.source_id
           OR (o.data -> 'cuisine') IS DISTINCT FROM (n.data -> 'cuisine')
           OR ST_AsBinary(o.geom) IS DISTINCT FROM ST_AsBinary(n.geom)
           OR o.deleted_at IS DISTINCT FROM n.deleted_at
           OR o.hidden IS DISTINCT FROM n.hidden) THEN
        RETURN NULL;
    END IF;
    DELETE FROM poi_search
    WHERE id = ANY (ARRAY(SELECT n.id FROM new_pois n WHERE n.deleted_at IS NOT NULL OR n.hidden));
    WITH written AS (
        INSERT INTO poi_search (id, source_id, kind, geom, words, name_length)
        SELECT n.id, n.source_id, n.kind, n.geom,
               lunaway_poi_words(n.name, n.brand, n.kind, n.category, n.data -> 'cuisine')
                   || lunaway_poi_cells(n.geom),
               char_length(coalesce(n.name, n.brand, ''))
        FROM old_pois o
        JOIN new_pois n ON n.id = o.id
        WHERE n.deleted_at IS NULL AND NOT n.hidden
          AND (o.name IS DISTINCT FROM n.name
               OR o.brand IS DISTINCT FROM n.brand
               OR o.kind IS DISTINCT FROM n.kind
               OR o.category IS DISTINCT FROM n.category
               OR o.source_id IS DISTINCT FROM n.source_id
               OR (o.data -> 'cuisine') IS DISTINCT FROM (n.data -> 'cuisine')
               OR ST_AsBinary(o.geom) IS DISTINCT FROM ST_AsBinary(n.geom)
               OR o.deleted_at IS DISTINCT FROM n.deleted_at
               OR o.hidden IS DISTINCT FROM n.hidden)
        ORDER BY n.id
        ON CONFLICT (id) DO UPDATE SET
            source_id = EXCLUDED.source_id,
            kind = EXCLUDED.kind,
            geom = EXCLUDED.geom,
            words = EXCLUDED.words,
            name_length = EXCLUDED.name_length
        RETURNING words
    )
    INSERT INTO poi_search_words (word)
    SELECT DISTINCT w
    FROM written, unnest(tsvector_to_array(written.words)) AS w
    WHERE strpos(w, '_') = 0
    ORDER BY w
    ON CONFLICT DO NOTHING;
    RETURN NULL;
END
$$;

CREATE TABLE poi_search_next (
    id uuid NOT NULL,
    source_id text NOT NULL,
    kind text NOT NULL,
    geom geography(Point, 4326) NOT NULL,
    words tsvector NOT NULL,
    name_length integer NOT NULL
);

INSERT INTO poi_search_next (id, source_id, kind, geom, words, name_length)
SELECT id, source_id, kind, geom, words || lunaway_poi_cells(geom), name_length
FROM poi_search
ORDER BY ST_GeoHash(geom::geometry, 8);

ALTER TABLE poi_search_next ADD CONSTRAINT poi_search_next_pkey PRIMARY KEY (id);
-- As the table's first index of its words: without the pending list.
CREATE INDEX poi_search_next_words_idx ON poi_search_next USING gin (words)
    WITH (fastupdate = off);
CREATE INDEX poi_search_next_geom_idx ON poi_search_next USING gist (geom);
ANALYZE poi_search_next;

DROP TABLE poi_search;
ALTER TABLE poi_search_next RENAME TO poi_search;
ALTER INDEX poi_search_next_pkey RENAME TO poi_search_pkey;
ALTER INDEX poi_search_next_words_idx RENAME TO poi_search_words_idx;
ALTER INDEX poi_search_next_geom_idx RENAME TO poi_search_geom_idx;

-- The grants of the table it replaces.
GRANT SELECT ON poi_search TO lunaway_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON poi_search TO lunaway_ingest;
