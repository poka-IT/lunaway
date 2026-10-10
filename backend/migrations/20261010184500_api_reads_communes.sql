-- The API names the town and the department of a point of interest whose
-- address names none, from the French commune whose outline covers it
-- (`Poi.locality`, `lunaway_db::pois::communes_of`): a restaurant found by
-- the map's search reads "Restaurant · Annecy (74)". The communes are open
-- data (contours administratifs, ODbL, docs/data-sources.md); the API reads
-- them, and still writes none (infra/server/test-grants.sh).
SET LOCAL lock_timeout = '10s';
GRANT SELECT ON municipalities TO lunaway_app;
