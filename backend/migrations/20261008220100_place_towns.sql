-- The towns of the map's search, with how many places each holds: one row
-- per French commune (its INSEE code), and one per other town the places'
-- addresses name (a hamlet a source writes as the town, a town abroad),
-- told apart by its country and its department or postcode area. The
-- search lists those whose name starts like the text: Viviers in Ardèche,
-- in Yonne and in Moselle are three rows, and their counts do not depend
-- on where the map looks (audit 8: the web counted the places among the
-- first page of results, 5, 10 or 18 for the same Viviers).
--
-- Rebuilt from `places` by the conflation worker when the places' tiles
-- take a new version (`lunaway_db::towns::refresh`): a new table, read by
-- the API, written by the worker alone, so no lock of `places` is taken.
CREATE TABLE place_towns (
    -- `m:<INSEE code>` for a commune, `c:<country>:<area>:<folded name>`
    -- for another town.
    key text PRIMARY KEY,
    name text NOT NULL CHECK (name <> ''),
    -- The name folded as a search text is (`lunaway_town_fold`), so a
    -- prefix of it finds it through the index.
    folded text NOT NULL,
    -- The postcode most of its places carry.
    postcode text,
    -- The French department ('07', '2A', '974'), from the commune's code or
    -- the postcode; null outside France.
    department text,
    country_code text,
    places integer NOT NULL CHECK (places > 0),
    lat double precision NOT NULL,
    lon double precision NOT NULL
);

-- A text folded for the towns: lower case, accents and ligatures undone,
-- every run of what is neither a letter nor a digit one space, trimmed.
-- "Chamonix-Mont-Blanc" and "chamonix mont" then start alike. STABLE, as
-- `[:alnum:]` follows the database's locale.
CREATE FUNCTION lunaway_town_fold(input text) RETURNS text
    LANGUAGE sql STABLE PARALLEL SAFE STRICT
    RETURN btrim(regexp_replace(lunaway_fold(input), '[^[:alnum:]]+', ' ', 'g'));

-- `folded LIKE $1` through the index: a trigram index takes the pattern of
-- a prepared statement at run time, where a B-tree needs it when planning.
CREATE INDEX place_towns_folded_idx ON place_towns USING gin (folded gin_trgm_ops);

REVOKE ALL ON place_towns FROM lunaway_app, lunaway_ingest;
GRANT SELECT ON place_towns TO lunaway_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON place_towns TO lunaway_ingest;
