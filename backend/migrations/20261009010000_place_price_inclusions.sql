-- What a place's prices include, as its sources say: whether the services
-- come with the night (nothing more to pay for them; `price_services_eur`
-- is then null), and what the price of a night includes besides the pitch
-- (`lunaway_domain::PriceInclusion` codes). The conflation writes both with
-- the prices they belong to.
--
-- Columns with a constant default: added without rewriting the table. The
-- writers' lock first (lunaway_db::WRITER_LOCK), so a running conflation
-- delays the migration rather than failing it; then the exclusive lock of
-- `ADD COLUMN`, waited for less than the API role's own 5 s, since every
-- read of `places` queues behind a waiting `ALTER`
-- (20261008140000_place_search_vector.sql). The check of the codes is added
-- unchecked: checking it here would read every row under that exclusive
-- lock. The next migration checks it under a lock that lets reads and
-- writes go on.
SET LOCAL lock_timeout = '2min';
SELECT pg_advisory_xact_lock(7815274093265123683);
SET LOCAL lock_timeout = '3s';
ALTER TABLE places
    ADD COLUMN price_services_included boolean NOT NULL DEFAULT false,
    ADD COLUMN price_parking_includes text[] NOT NULL DEFAULT '{}',
    ADD CONSTRAINT places_price_parking_includes_codes CHECK (
        price_parking_includes <@ ARRAY['services', 'tourist_tax', 'electricity']::text[]
    ) NOT VALID;

-- The grants of `places` are on the whole table (roles_and_grants): the API
-- reads the columns, the conflation (lunaway_ingest) writes them.
