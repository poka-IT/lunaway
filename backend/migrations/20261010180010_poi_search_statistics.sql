-- The table written again by 20261010180000: its grants alone, whatever
-- default privileges a server holds, and statistics of its words wide
-- enough to keep the words beside the cells. With the default target, 514
-- of the 1,000 most common elements PostgreSQL kept for `words` were cells
-- on the local copy of France (2026-10-10), and a word held by fewer than
-- about 2,900 points of production would have read as held by none, which
-- decides how the search looks (`lunaway_db::poi_search`).
REVOKE ALL ON poi_search FROM lunaway_app, lunaway_ingest;
GRANT SELECT ON poi_search TO lunaway_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON poi_search TO lunaway_ingest;

ALTER TABLE poi_search ALTER COLUMN words SET STATISTICS 1000;
ANALYZE poi_search;
