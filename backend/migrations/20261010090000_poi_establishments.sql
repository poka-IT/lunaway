-- The establishments (plan/research/98-recherche-commerces.md): every named
-- shop, service, craftsman, health practice, place to stay and leisure venue
-- of OpenStreetMap, which the map's search finds. They are points of
-- interest, in this table, with the kinds and categories of
-- lunaway_domain::poi (tested against these lists, lunaway-db,
-- tests/pois.rs), and they stay out of the map tiles: `in_tiles` is false
-- for every row the establishments' import writes, true for the points the
-- tiles have always carried. The tiles, their clusters, the evaluation of
-- the hours and "around this place" read only the rows in the tiles, by
-- partial indexes that leave the others out (next migrations), so the
-- millions of establishments cost them nothing.
--
-- The POI writers' lock first (lunaway_db::pois::POI_WRITER_LOCK), so a
-- running import delays the migration rather than failing it; then the
-- exclusive lock of `ALTER TABLE`, waited for less than the API role's own
-- 5 s. The checks are added unchecked: checking them here would read every
-- row under that exclusive lock; the next migration checks them under a
-- lock that lets reads and writes go on. A column with a constant default
-- is added without rewriting the table.
SET LOCAL lock_timeout = '2min';
SELECT pg_advisory_xact_lock(7815274093148596595);
SET LOCAL lock_timeout = '3s';
ALTER TABLE pois
    DROP CONSTRAINT pois_category_check,
    DROP CONSTRAINT pois_kind_check,
    ADD CONSTRAINT pois_category_check CHECK (category IN (
        'groceries', 'vending', 'water', 'fuel', 'health', 'services', 'food', 'sights',
        'shopping', 'lodging', 'leisure'))
        NOT VALID,
    ADD CONSTRAINT pois_kind_check CHECK (kind IN (
        'supermarket', 'convenience', 'bakery', 'butcher', 'greengrocer', 'farm_shop',
        'marketplace', 'vending_pizza', 'vending_bread', 'vending_farm_products',
        'vending_eggs_milk', 'vending_ice', 'vending_other', 'drinking_water', 'water_point',
        'dump_station', 'toilets', 'shower', 'fuel_station', 'ev_charging', 'gas_bottles',
        'pharmacy', 'doctor', 'hospital', 'veterinary', 'laundry', 'atm', 'post_office',
        'tourist_office', 'recycling_centre', 'car_repair', 'car_wash', 'motorhome_shop',
        'outdoor_shop', 'restaurant', 'cafe', 'fast_food', 'viewpoint', 'attraction', 'museum',
        'bar', 'pub', 'ice_cream', 'deli', 'cheese', 'seafood', 'pastry', 'confectionery',
        'wine_shop', 'beverages', 'tea_coffee', 'organic_shop', 'frozen_food', 'winery',
        'brewery', 'distillery', 'beekeeper', 'dentist', 'clinic', 'physiotherapist',
        'laboratory', 'nurse', 'midwife', 'podiatrist', 'psychologist', 'speech_therapist',
        'alternative_medicine', 'optician', 'hearing_aids', 'medical_supply', 'hairdresser',
        'beauty', 'massage', 'tattoo', 'bank', 'money_exchange', 'car_rental', 'bicycle_rental',
        'boat_rental', 'vehicle_inspection', 'driving_school', 'dry_cleaning', 'tailor',
        'shoe_repair', 'locksmith', 'copyshop', 'photographer', 'travel_agency', 'estate_agent',
        'insurance', 'funeral_directors', 'pet_grooming', 'tyres', 'car_parts', 'car_dealer',
        'motorcycle_shop', 'repair_shop', 'internet_cafe', 'coworking', 'townhall', 'police',
        'library', 'rental', 'storage_rental', 'animal_boarding', 'ferry_terminal', 'clothes',
        'shoes', 'accessories', 'jewellery', 'books', 'newsagent', 'tobacco', 'stationery',
        'gift', 'toys', 'sports', 'fishing_hunting', 'bicycle_shop', 'boat_shop', 'florist',
        'garden_centre', 'hardware', 'home', 'electronics', 'cosmetics', 'department_store',
        'variety_store', 'second_hand', 'art_shop', 'music_shop', 'pet_shop', 'baby_goods',
        'fabric', 'craft', 'shop', 'hotel', 'guest_house', 'hostel', 'holiday_rental',
        'mountain_hut', 'cinema', 'theatre', 'events_venue', 'arts_centre', 'nightclub',
        'casino', 'sports_centre', 'fitness_centre', 'swimming_pool', 'water_park',
        'golf_course', 'miniature_golf', 'marina', 'horse_riding', 'bowling_alley',
        'escape_game', 'amusement_arcade', 'ice_rink', 'spa', 'dance', 'park', 'nature_reserve',
        'gallery', 'zoo', 'theme_park'))
        NOT VALID,
    ADD COLUMN in_tiles boolean NOT NULL DEFAULT true;

-- The clusters of the tiles count the points the tiles carry, and no
-- establishment.
CREATE OR REPLACE VIEW poi_cluster_cells_computed AS
WITH m AS MATERIALIZED (
    SELECT p.category,
           CASE WHEN p.category = 'vending' AND p.kind <> 'vending_other' THEN p.kind END AS kind,
           lunaway_grid_x(ST_X(p.geom::geometry)) AS gx,
           lunaway_grid_y(ST_Y(p.geom::geometry)) AS gy
    FROM pois p
    WHERE p.deleted_at IS NULL AND NOT p.hidden AND p.in_tiles
      AND ST_Y(p.geom::geometry) BETWEEN -85.0511287798066 AND 85.0511287798066
),
c9 AS (
    SELECT gx >> 14 AS cx, gy >> 14 AS cy, category, ''::text AS kind,
           count(*) AS n, sum(gx) AS sx, sum(gy) AS sy
    FROM m GROUP BY gx >> 14, gy >> 14, category
    UNION ALL
    SELECT gx >> 14, gy >> 14, category, kind, count(*), sum(gx), sum(gy)
    FROM m WHERE kind IS NOT NULL GROUP BY gx >> 14, gy >> 14, category, kind
),
c8 AS (
    SELECT cx >> 1 AS cx, cy >> 1 AS cy, category, kind,
           sum(n)::bigint AS n, sum(sx)::bigint AS sx, sum(sy)::bigint AS sy
    FROM c9 GROUP BY cx >> 1, cy >> 1, category, kind
),
c7 AS (
    SELECT cx >> 1 AS cx, cy >> 1 AS cy, category, kind,
           sum(n)::bigint AS n, sum(sx)::bigint AS sx, sum(sy)::bigint AS sy
    FROM c8 GROUP BY cx >> 1, cy >> 1, category, kind
),
c6 AS (
    SELECT cx >> 1 AS cx, cy >> 1 AS cy, category, kind,
           sum(n)::bigint AS n, sum(sx)::bigint AS sx, sum(sy)::bigint AS sy
    FROM c7 GROUP BY cx >> 1, cy >> 1, category, kind
),
cells AS (
    SELECT 9 AS z, * FROM c9
    UNION ALL SELECT 8, * FROM c8
    UNION ALL SELECT 7, * FROM c7
    UNION ALL SELECT 6, * FROM c6
)
SELECT z::smallint AS z, (cx >> 5)::integer AS tx, (cy >> 5)::integer AS ty,
       ((cy & 31) * 32 + (cx & 31))::smallint AS cell, category, kind,
       n::integer AS n, sx::bigint AS sx, sy::bigint AS sy
FROM cells;
