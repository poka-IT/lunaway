-- The search of the points of interest and establishments
-- (`lunaway_db::poi_search`, plan/research/98-recherche-commerces.md).
--
-- A narrow table beside `pois`, one row per live point the search may
-- show: its kind, its position and its words. The rows of `pois` hold the
-- raw payload of each point, about a kilobyte; walking out from a point
-- through these rows of a hundred bytes, or reading the matches of a word,
-- touches ten times fewer pages, which keeps a search among millions of
-- points within milliseconds. Kept by triggers on `pois`, so no writer of
-- the points can leave it stale.
--
-- The words of a point are its folded name and brand, split on what is
-- not a letter or a digit as `lunaway_search_words` splits a query, the
-- name weighted before the brand; and three tokens no word of a name can
-- be, since they hold `_`: `k_<kind>`, `g_<category>` and `c_<cuisine>` for
-- each cuisine it cooks. A search by kind ("coiffeur", "pizzeria") reads
-- the tokens; the planner's statistics of the words
-- (`pg_stats.most_common_elems`) tell how many points hold each, which the
-- search reads to choose how to look.
--
-- Under the POI writers' lock: an import running beside the fill would
-- write points the fill does not see. The API keeps reading `pois`
-- meanwhile.
SET LOCAL lock_timeout = '2min';
SELECT pg_advisory_xact_lock(7815274093148596595);
SET LOCAL lock_timeout = '10s';

CREATE FUNCTION lunaway_poi_words(
    name text, brand text, kind text, category text, cuisine jsonb
) RETURNS tsvector
    LANGUAGE sql STABLE PARALLEL SAFE
    RETURN setweight(to_tsvector('simple'::regconfig, regexp_replace(
               lunaway_fold(coalesce(name, '')), '[^[:alnum:]]+', ' ', 'g')), 'A')
        || setweight(to_tsvector('simple'::regconfig, regexp_replace(
               lunaway_fold(coalesce(brand, '')), '[^[:alnum:]]+', ' ', 'g')), 'B')
        || array_to_tsvector(ARRAY['k_' || kind, 'g_' || category] || ARRAY(
               SELECT 'c_' || c
               FROM jsonb_array_elements_text(
                   CASE WHEN jsonb_typeof(cuisine) = 'array' THEN cuisine ELSE '[]' END) AS c
               WHERE c ~ '^[a-z0-9_]{1,32}$'));

CREATE TABLE poi_search (
    id uuid PRIMARY KEY,
    -- `osm`, `community`, or another source of points: the search keeps an
    -- open source's point before another's that names the same shop.
    source_id text NOT NULL,
    kind text NOT NULL,
    geom geography(Point, 4326) NOT NULL,
    words tsvector NOT NULL,
    -- The name's length: among equal matches the shorter name first.
    name_length integer NOT NULL
);

INSERT INTO poi_search (id, source_id, kind, geom, words, name_length)
SELECT id, source_id, kind, geom,
       lunaway_poi_words(name, brand, kind, category, data -> 'cuisine'),
       char_length(coalesce(name, brand, ''))
FROM pois
WHERE deleted_at IS NULL AND NOT hidden;

-- Without the pending list a GIN index keeps by default: a search would
-- read that list whole before the index, and an import's batches fill it.
CREATE INDEX poi_search_words_idx ON poi_search USING gin (words) WITH (fastupdate = off);
CREATE INDEX poi_search_geom_idx ON poi_search USING gist (geom);

-- The words of the points' names and brands, for the correction of a
-- typed word that starts none of them ("carefour" for "carrefour"), as for
-- the places (`place_search_words`). Kept as the points are written; a
-- word no point holds any more is cleared by `lunaway pois words`.
CREATE TABLE poi_search_words (
    word text COLLATE "C" PRIMARY KEY CHECK (word <> '')
);

INSERT INTO poi_search_words (word)
SELECT DISTINCT w FROM poi_search, unnest(tsvector_to_array(words)) AS w
WHERE strpos(w, '_') = 0;

CREATE INDEX poi_search_words_trgm_idx ON poi_search_words USING gin (word gin_trgm_ops);

-- Once per statement of the writers, for a batch: the rows of the points
-- inserted, and of those whose name, brand, kind, cuisine, position or
-- state changed. Most updates (the hours, the community's answers) change
-- none of them and stop at the first check.
CREATE FUNCTION lunaway_poi_search_insert() RETURNS trigger
    LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO poi_search (id, source_id, kind, geom, words, name_length)
    SELECT id, source_id, kind, geom,
           lunaway_poi_words(name, brand, kind, category, data -> 'cuisine'),
           char_length(coalesce(name, brand, ''))
    FROM new_pois
    WHERE deleted_at IS NULL AND NOT hidden
    ON CONFLICT (id) DO NOTHING;
    INSERT INTO poi_search_words (word)
    SELECT DISTINCT w
    FROM new_pois n
    JOIN poi_search s ON s.id = n.id,
         unnest(tsvector_to_array(s.words)) AS w
    WHERE strpos(w, '_') = 0
    ORDER BY w
    ON CONFLICT DO NOTHING;
    RETURN NULL;
END
$$;

CREATE FUNCTION lunaway_poi_search_update() RETURNS trigger
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
    DELETE FROM poi_search s
    USING new_pois n
    WHERE s.id = n.id AND (n.deleted_at IS NOT NULL OR n.hidden);
    INSERT INTO poi_search (id, source_id, kind, geom, words, name_length)
    SELECT n.id, n.source_id, n.kind, n.geom,
           lunaway_poi_words(n.name, n.brand, n.kind, n.category, n.data -> 'cuisine'),
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
        name_length = EXCLUDED.name_length;
    INSERT INTO poi_search_words (word)
    SELECT DISTINCT w
    FROM new_pois n
    JOIN poi_search s ON s.id = n.id,
         unnest(tsvector_to_array(s.words)) AS w
    WHERE strpos(w, '_') = 0
    ORDER BY w
    ON CONFLICT DO NOTHING;
    RETURN NULL;
END
$$;

CREATE TRIGGER pois_search_insert AFTER INSERT ON pois
    REFERENCING NEW TABLE AS new_pois
    FOR EACH STATEMENT EXECUTE FUNCTION lunaway_poi_search_insert();
CREATE TRIGGER pois_search_update AFTER UPDATE ON pois
    REFERENCING OLD TABLE AS old_pois NEW TABLE AS new_pois
    FOR EACH STATEMENT EXECUTE FUNCTION lunaway_poi_search_update();

REVOKE ALL ON poi_search, poi_search_words FROM lunaway_app, lunaway_ingest;
-- The API searches; the writers of the points keep both tables through
-- the triggers, which run with their role, and clear the words.
GRANT SELECT ON poi_search, poi_search_words TO lunaway_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON poi_search TO lunaway_ingest;
GRANT SELECT, INSERT, DELETE ON poi_search_words TO lunaway_ingest;

-- The search reads how many points hold a word from these statistics
-- before it chooses how to look.
ANALYZE poi_search;
