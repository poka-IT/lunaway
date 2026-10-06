-- When a source's data was last known current: the time of a complete
-- snapshot read, or for the DIR the newer of its aggregate's publication
-- and the last increment applied. A read that brings nothing new (an
-- unchanged aggregate, no increment) moves last_success_at only, so a
-- publisher that stopped makes its events stale instead of looking fresh
-- for ever.
ALTER TABLE road_event_sources ADD COLUMN data_at TIMESTAMPTZ;
UPDATE road_event_sources SET data_at = last_success_at;
