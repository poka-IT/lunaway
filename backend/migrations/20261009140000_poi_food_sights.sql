-- Two categories of points of interest for the stops of a trip rather than
-- its needs: somewhere to eat (`food`: restaurants, cafés, fast food) and
-- something to see (`sights`: viewpoints, attractions, museums, and the
-- tourist offices, which move there from `services`); and camping and
-- outdoor shops among the services (`outdoor_shop`). The codes are those of
-- lunaway_domain::poi, tested against these lists (lunaway-db,
-- tests/pois.rs).
--
-- The POI writers' lock first (lunaway_db::pois::POI_WRITER_LOCK), so a
-- running import delays the migration rather than failing it; then the
-- exclusive lock of `ALTER TABLE`, waited for less than the API role's own
-- 5 s. The new checks are added unchecked: checking them here would read
-- every row under that exclusive lock. The next migration checks them under
-- a lock that lets reads and writes go on.
SET LOCAL lock_timeout = '2min';
SELECT pg_advisory_xact_lock(7815274093148596595);
SET LOCAL lock_timeout = '3s';
ALTER TABLE pois
    DROP CONSTRAINT pois_category_check,
    DROP CONSTRAINT pois_kind_check,
    ADD CONSTRAINT pois_category_check CHECK (category IN (
        'groceries', 'vending', 'water', 'fuel', 'health', 'services', 'food', 'sights'))
        NOT VALID,
    ADD CONSTRAINT pois_kind_check CHECK (kind IN (
        'supermarket', 'convenience', 'bakery', 'butcher', 'greengrocer', 'farm_shop',
        'marketplace', 'vending_pizza', 'vending_bread', 'vending_farm_products',
        'vending_eggs_milk', 'vending_ice', 'vending_other', 'drinking_water', 'water_point',
        'dump_station', 'toilets', 'shower', 'fuel_station', 'ev_charging', 'gas_bottles',
        'pharmacy', 'doctor', 'hospital', 'veterinary', 'laundry', 'atm', 'post_office',
        'tourist_office', 'recycling_centre', 'car_repair', 'car_wash', 'motorhome_shop',
        'outdoor_shop', 'restaurant', 'cafe', 'fast_food', 'viewpoint', 'attraction',
        'museum'))
        NOT VALID;
