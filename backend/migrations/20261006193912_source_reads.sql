-- An import writes a record or a point only when what its source says of it
-- changed. Rewriting every row at each import doubled `pois` on an
-- unchanged France import (405 to 795 MB on the dev database, 2026-10-06)
-- until a vacuum, gigabytes a day at the scale of Europe.
--
-- The date a client sees for a row stays the date Lunaway last read it. A
-- run that read a slice of a source whole (a country of an extract, an
-- Overpass region, the whole source) and retired what the slice no longer
-- holds writes the date of that read here, once: every live row of the
-- slice was in it. A row's own `fetched_at` is now the read that last
-- changed it.
CREATE TABLE source_reads (
    -- The table the run fed.
    target text NOT NULL CHECK (target IN ('records', 'pois')),
    source_id text NOT NULL REFERENCES sources (id),
    -- The rows' `scope` the read covered: '' for the rows stored without
    -- one (an extract run files those under their country the first time
    -- it reads them), '*' for a read of the whole source.
    scope text NOT NULL,
    read_at timestamptz NOT NULL,
    PRIMARY KEY (target, source_id, scope)
);

-- When a row was last read: for a live row, the later of its own date and
-- its slice's; a retired row keeps the date it was last seen.
CREATE FUNCTION lunaway_read_at(
    of_target text, of_source text, of_scope text, fetched timestamptz, deleted timestamptz
) RETURNS timestamptz
    LANGUAGE sql STABLE PARALLEL SAFE
    RETURN CASE WHEN deleted IS NOT NULL THEN fetched ELSE greatest(fetched, (
        SELECT max(r.read_at) FROM public.source_reads r
        WHERE r.target = of_target AND r.source_id = of_source
          AND r.scope IN (coalesce(of_scope, ''), '*'))) END;

REVOKE ALL ON source_reads FROM lunaway_app, lunaway_ingest;
-- The API reads the dates; the importers write them, and the pack builder
-- (their role) reads them.
GRANT SELECT ON source_reads TO lunaway_app;
GRANT SELECT, INSERT, UPDATE ON source_reads TO lunaway_ingest;
