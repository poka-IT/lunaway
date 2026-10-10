-- The checks of the previous migration, read against every row under a
-- lock that lets the API and the importer read and write meanwhile. Every
-- stored code is among the old ones, which the new checks keep.
SET LOCAL lock_timeout = '10s';

ALTER TABLE reviews VALIDATE CONSTRAINT reviews_vehicle_check;
ALTER TABLE external_reviews VALIDATE CONSTRAINT external_reviews_vehicle_check;
