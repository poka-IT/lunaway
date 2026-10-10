-- The checks and keys of the previous migration, read against every row
-- under a lock that lets the API read and the content worker write
-- meanwhile (a foreign key's check holds only a share lock on `pois`).
SET LOCAL lock_timeout = '10s';

ALTER TABLE content_reviews VALIDATE CONSTRAINT content_reviews_one_target;
ALTER TABLE content_reviews VALIDATE CONSTRAINT content_reviews_poi_id_fkey;
ALTER TABLE content_photos VALIDATE CONSTRAINT content_photos_one_target;
ALTER TABLE content_photos VALIDATE CONSTRAINT content_photos_poi_id_fkey;
