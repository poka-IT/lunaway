-- The pack builder runs with the import role and writes the feed identity
-- into each pack, which names the copy of the feed (`places::feed_head`,
-- reading `sync_epoch`): without this grant `lunaway packs build` failed
-- with "permission denied for table sync_epoch" on the first production
-- build (2026-10-06), and the grant was applied by hand there. Applied
-- again here, it changes nothing on that server.
GRANT SELECT ON sync_epoch TO lunaway_ingest;
