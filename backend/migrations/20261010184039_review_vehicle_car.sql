-- A reviewer may travel in a car without a caravan ('car',
-- `lunaway_domain::community::VehicleKind::Car`): a member picks it, and
-- the partner feed's own code for it, stored as 'other' until now, maps to
-- it. The vehicle checks of both review tables take the new code.
--
-- The importer of the feed writes `external_reviews` under the writers'
-- lock (lunaway_db::WRITER_LOCK): taken first, so a running import delays
-- the migration rather than failing it. Then the exclusive lock of each
-- `ALTER`, waited for less than the API role's own 5 s, since every read of
-- the reviews queues behind a waiting `ALTER`
-- (20261008140000_place_search_vector.sql). Each check is replaced without
-- reading the table and validated by the next migration.
SET LOCAL lock_timeout = '2min';
SELECT pg_advisory_xact_lock(7815274093265123683);
SET LOCAL lock_timeout = '3s';

ALTER TABLE reviews
    DROP CONSTRAINT reviews_vehicle_check,
    ADD CONSTRAINT reviews_vehicle_check
        CHECK (vehicle IN ('van', 'campervan', 'motorhome', 'caravan', 'car', 'other')) NOT VALID;

ALTER TABLE external_reviews
    DROP CONSTRAINT external_reviews_vehicle_check,
    ADD CONSTRAINT external_reviews_vehicle_check
        CHECK (vehicle IN ('van', 'campervan', 'motorhome', 'caravan', 'car', 'other')) NOT VALID;
