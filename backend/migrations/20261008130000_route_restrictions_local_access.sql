-- A limit that spares local access ("sauf desserte", OpenStreetMap's
-- `maxweight:conditional=none @ destination`): a vehicle above it may
-- drive it at the start or the end of a trip, never through it. A
-- clearance or a ban never carries it. A column with a constant default
-- rewrites no row; the check reads the table once, every row false.
ALTER TABLE route_restrictions
    ADD COLUMN except_destination BOOLEAN NOT NULL DEFAULT false,
    ADD CONSTRAINT route_restrictions_except_destination_check CHECK (
        NOT except_destination
        OR (kind IN ('max_width', 'max_length', 'max_weight', 'max_axle_load')
            AND limit_value IS NOT NULL));
