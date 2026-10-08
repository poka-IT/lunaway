-- The words of a place's name, address city and municipality, for the
-- search (`lunaway_db::search`). A trigram match rechecks every candidate
-- row with a regular expression or a similarity, 2 to 20 microseconds each,
-- and a generic text ("aire de camping car") has thousands of candidates:
-- 1.1 s on production on 2026-10-07. A stored `tsvector` is matched in a
-- fraction of a microsecond, a GIN index finds its words exactly, and the
-- planner's statistics of its words (pg_stats.most_common_elems) tell how
-- many places hold one.
--
-- Folded as `search_text` is, then split on what is not a letter or a
-- digit, as `lunaway_search_words` splits a query: "camping-car" gives the
-- two words at consecutive positions, so a phrase query matches it. The
-- 'simple' configuration keeps every word as it is: no stemming, no stop
-- word. STABLE, for `[:alnum:]` follows the database's locale.
CREATE FUNCTION lunaway_search_vector(name text, city text, municipality text) RETURNS tsvector
    LANGUAGE sql STABLE PARALLEL SAFE
    RETURN to_tsvector('simple'::regconfig, regexp_replace(
        lunaway_fold(coalesce(name, '') || ' ' || coalesce(city, '') || ' ' || coalesce(municipality, '')),
        '[^[:alnum:]]+', ' ', 'g'));

-- A plain column kept by a trigger rather than a generated one: adding a
-- stored generated column rewrites `places` under an exclusive lock held to
-- the end of the migration, about 5 s for the 89,000 places of 2026-10-07,
-- past the API role's `lock_timeout` of 5 s. This one is added at once, and
-- the next migration fills it under row locks, which readers do not wait
-- for. Every write of the words it is made of recomputes it, so no writer
-- can leave it stale.
--
-- The writers' lock first (lunaway_db::WRITER_LOCK), so a running
-- conflation delays the migration rather than failing it. Then the
-- exclusive lock of `ADD COLUMN`, waited for less than the API role's own
-- 5 s: every read of `places` queues behind a waiting `ALTER`, and the
-- daily pack build reads it for minutes in one snapshot. Past the wait the
-- migration fails, the release stays on the previous one
-- (infra/server/install-release.sh), and the deploy is run again.
SET LOCAL lock_timeout = '2min';
SELECT pg_advisory_xact_lock(7815274093265123683);
SET LOCAL lock_timeout = '3s';
ALTER TABLE places ADD COLUMN search_vector tsvector;

CREATE FUNCTION lunaway_place_search_vector() RETURNS trigger
    LANGUAGE plpgsql AS $$
BEGIN
    NEW.search_vector := lunaway_search_vector(NEW.name, NEW.city, NEW.municipality);
    RETURN NEW;
END
$$;

-- `search_vector` in the list too: a write of the column itself is
-- recomputed, and the next migration fills it by setting it.
CREATE TRIGGER places_search_vector
    BEFORE INSERT OR UPDATE OF name, city, municipality, search_vector ON places
    FOR EACH ROW EXECUTE FUNCTION lunaway_place_search_vector();
