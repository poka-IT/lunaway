-- The checks of the codes of the previous migration, read against every
-- row under a lock that lets the API read and the writers write meanwhile.
SET LOCAL lock_timeout = '2min';
SELECT pg_advisory_xact_lock(7815274093148596595);
SET LOCAL lock_timeout = '10s';

ALTER TABLE pois VALIDATE CONSTRAINT pois_category_check;
ALTER TABLE pois VALIDATE CONSTRAINT pois_kind_check;
