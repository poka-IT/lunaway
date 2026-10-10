-- The reverse geocoding of the places no source gives a street, or a town
-- (`lunaway_domain::place_address`): what Lunaway's own Photon answered
-- for the position asked, kept so that it is asked once, and asked again
-- when the place moves by more than `place_address::MOVED_M` from it
-- (`lunaway addresses`). The address a place shows (`places.street`,
-- `postcode`, `city`) is written from it by that command and by the
-- conflation, whichever writes the place.
--
-- A new table. Its reference to `places` takes a lock that holds the
-- writers of `places` back for an instant (not its readers): the writers'
-- lock first (lunaway_db::WRITER_LOCK), so a running conflation delays the
-- migration rather than failing it, then less than the API role's own 5 s
-- for the table's lock (20261008140000_place_search_vector.sql).
SET LOCAL lock_timeout = '2min';
SELECT pg_advisory_xact_lock(7815274093265123683);
SET LOCAL lock_timeout = '3s';
CREATE TABLE place_geocodes (
    place_id uuid PRIMARY KEY REFERENCES places (id) ON DELETE CASCADE,
    -- The position asked, WGS 84 degrees.
    lat double precision NOT NULL,
    lon double precision NOT NULL,
    house_number text,
    street text,
    postcode text,
    city text,
    country_code text,
    asked_at timestamptz NOT NULL DEFAULT now()
);

-- The import role asks and writes, and empties a place taken down; the
-- API reads the address from `places` and never this table.
GRANT SELECT, INSERT, UPDATE, DELETE ON place_geocodes TO lunaway_ingest;
