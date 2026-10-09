-- The tourist offices already stored take their new category, `sights`, at
-- once: an import rewrites them too, but each country's points are read
-- once a week, and until then the map's clusters and "around this place"
-- would count them among the services. Under the POI writers' lock, like
-- every write of `pois`, and the layer marked as changed so the worker
-- publishes a new version of the tiles (lunaway_db::pois::mark_layer).
--
-- Then the checks of the codes of the previous migration, read against
-- every row under a lock that lets the API read and the writers write
-- meanwhile.
SET LOCAL lock_timeout = '2min';
SELECT pg_advisory_xact_lock(7815274093148596595);
SET LOCAL lock_timeout = '10s';

UPDATE pois SET category = 'sights', changed_at = now()
WHERE kind = 'tourist_office' AND category <> 'sights';
UPDATE poi_layer SET pending_since = coalesce(pending_since, now());

ALTER TABLE pois VALIDATE CONSTRAINT pois_category_check;
ALTER TABLE pois VALIDATE CONSTRAINT pois_kind_check;
