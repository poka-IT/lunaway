-- The check of the previous migration, read against every row under a
-- lock that lets the route checks read and the imports write meanwhile.
SET LOCAL lock_timeout = '10s';

ALTER TABLE route_restrictions
    VALIDATE CONSTRAINT route_restrictions_enclosed_check;
