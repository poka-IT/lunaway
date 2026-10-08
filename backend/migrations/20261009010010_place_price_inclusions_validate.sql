-- The check of the codes of the previous migration, read against every row
-- under a lock that lets the API read and the writers write meanwhile.
-- Every row holds an empty list yet: the check passes at once.
SET LOCAL lock_timeout = '10s';

ALTER TABLE places VALIDATE CONSTRAINT places_price_parking_includes_codes;
