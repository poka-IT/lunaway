-- A limit that spares local access ("sauf desserte", OpenStreetMap's
-- `maxweight:conditional=none @ destination`): a vehicle above it may
-- drive it at the start or the end of a trip, never through it. A
-- clearance or a ban never carries it.
--
-- ADD COLUMN locks the table against the route checks' reads: a graph
-- load or a DiaLog import holding it would hold every route behind the
-- migration, so the migration fails instead after 10 s. A column with a
-- constant default rewrites no row, and the check is added without reading
-- the table; the next migration validates it under a lock reads pass.
SET LOCAL lock_timeout = '10s';

ALTER TABLE route_restrictions
    ADD COLUMN except_destination BOOLEAN NOT NULL DEFAULT false,
    ADD CONSTRAINT route_restrictions_except_destination_check CHECK (
        NOT except_destination
        OR (kind IN ('max_width', 'max_length', 'max_weight', 'max_axle_load')
            AND limit_value IS NOT NULL)) NOT VALID;
