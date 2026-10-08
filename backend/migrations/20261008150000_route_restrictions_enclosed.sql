-- A road enclosed behind a "sauf desserte" zone: one without a limit that
-- only the zone leads to, given the zone's limit and plate by the graph
-- build so that the engine grants a trip ending there the right. No sign
-- stands there: the check joins it to the zone's run of local access and
-- never warns of it. It always carries the zone's exception.
--
-- ADD COLUMN locks the table against the route checks' reads: a graph
-- load or a DiaLog import holding it would hold every route behind the
-- migration, so the migration fails instead after 10 s. A column with a
-- constant default rewrites no row, and the check is added without reading
-- the table; the next migration validates it under a lock reads pass.
SET LOCAL lock_timeout = '10s';

ALTER TABLE route_restrictions
    ADD COLUMN enclosed BOOLEAN NOT NULL DEFAULT false,
    ADD CONSTRAINT route_restrictions_enclosed_check CHECK (
        NOT enclosed OR except_destination) NOT VALID;
