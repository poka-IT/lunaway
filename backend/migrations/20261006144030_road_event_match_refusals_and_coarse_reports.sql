-- Two fixes after the road events went into production (2026-10-06).
--
-- 1. A line the routing engine refused ("Insufficient number of locations
--    provided", "leg_shape_index not set") stopped every matching pass,
--    and was asked first again at the next one: 879 events waited behind
--    it. A refused line is now left unplaced (it warns at its source
--    position) with the engine's reason, asked again after 30 minutes and
--    2 hours, then not before the next graph.
ALTER TABLE road_events
    ADD COLUMN match_error TEXT CHECK (length(match_error) <= 300),
    ADD COLUMN match_attempts SMALLINT NOT NULL DEFAULT 0
        CHECK (match_attempts BETWEEN 0 AND 100),
    ADD COLUMN match_retry_at TIMESTAMPTZ;

-- 2. A community event kept the exact position and heading of its first
--    report. The importers' role reads the reports' accounts and times
--    (to weigh the events again) and every event row: joining the two
--    gave where an account was, to the metre, undoing the column grant
--    that keeps report positions from that role. An event now keeps the
--    position the feed publishes (four decimals of a degree, about ten
--    metres) and no heading; the exact report stays in road_event_reports.
--    A new digest moves these events in the phones' feed, so the heading
--    they received goes too.
UPDATE road_events SET
    geom_source = ST_SetSRID(ST_MakePoint(
        round(ST_X(geom_source::geometry)::numeric, 4)::double precision,
        round(ST_Y(geom_source::geometry)::numeric, 4)::double precision), 4326)::geography,
    heading_deg = NULL,
    content_hash = md5('coarse:' || content_hash)
WHERE source = 'community';
