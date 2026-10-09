-- The check of the previous migration, read against every row under a lock
-- that lets the API read and the writers write meanwhile. Every row holds
-- NULL yet: the check passes at once.
SET LOCAL lock_timeout = '10s';

ALTER TABLE places VALIDATE CONSTRAINT places_opening_season_days;
