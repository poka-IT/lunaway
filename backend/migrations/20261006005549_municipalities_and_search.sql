-- The municipality of every place, so a search for a town finds the places
-- inside it whatever their sources wrote in the address (most OpenStreetMap
-- records have no `addr:city`).
--
-- `municipalities` holds the French communes (contours administratifs,
-- data.gouv.fr, ODbL, see docs/data-sources.md), loaded by
-- `lunaway ingest municipalities`. A place takes the name of the commune
-- that covers its point when the conflation writes it, and the import
-- refreshes every place after a new load.

CREATE TABLE municipalities (
    -- INSEE code (`74010`, `2A004`).
    code text PRIMARY KEY CHECK (code ~ '^[0-9][0-9AB][0-9]{3}$'),
    name text NOT NULL CHECK (name <> ''),
    geom geometry(MultiPolygon, 4326) NOT NULL,
    fetched_at timestamptz NOT NULL
);

-- Point in polygon: `ST_Covers(geom, point)`.
CREATE INDEX municipalities_geom_idx ON municipalities USING gist (geom);

ALTER TABLE places
    ADD COLUMN municipality text,
    ADD COLUMN municipality_code text;

-- The search text gains the municipality. PostgreSQL recomputes the column
-- and rebuilds its index (a rewrite of `places`, a few seconds for France).
ALTER TABLE places ALTER COLUMN search_text SET EXPRESSION AS (
    lunaway_fold(coalesce(name, '') || ' ' || coalesce(city, '') || ' '
                 || coalesce(municipality, '')));

REVOKE ALL ON municipalities FROM lunaway_app, lunaway_ingest;
-- The importer replaces the communes in one transaction; the conflation
-- reads them. The API serves the name copied on each place, not this table.
GRANT SELECT, INSERT, UPDATE, DELETE ON municipalities TO lunaway_ingest;

-- The folded words of a search text, and a regular expression matching them
-- in order with the last one as a prefix (`\mlac[^[:alnum:]]+anne`), NULL
-- without words: the search ranks whole-word and prefix matches above
-- typo-tolerant ones, so "annecy" lists the places of Annecy before a
-- "Sainte-Anne" that only shares four letters. STABLE: `[:alnum:]` follows
-- the database's locale.
CREATE FUNCTION lunaway_search_words(input text) RETURNS text[]
    LANGUAGE sql STABLE PARALLEL SAFE STRICT
    RETURN array_remove(regexp_split_to_array(lunaway_fold(input), '[^[:alnum:]]+'), '');

CREATE FUNCTION lunaway_search_phrase(input text) RETURNS text
    LANGUAGE sql STABLE PARALLEL SAFE STRICT
    RETURN CASE WHEN cardinality(lunaway_search_words(input)) > 0
                THEN '\m' || array_to_string(lunaway_search_words(input), '[^[:alnum:]]+')
           END;
