-- The routing graph covers Europe and Morocco since 20261006T2326Z-eu
-- (lunaway_domain::routing::coverage): the Dutch (NDW) and Spanish (DGT)
-- events lie inside it. They are matched to it like the French ones, their
-- closures and limits block routes, and phones receive them in the feed of
-- changes (`road_event_sources.routed`).
UPDATE road_event_sources SET routed = true WHERE id IN ('ndw', 'dgt');

-- A phone holds the events up to its cursor, and these were left out of
-- the feed until now: each live one takes a new revision, past every
-- cursor, so the next sync brings it. Their lines get one again once
-- matched; their points and the Dutch detours, never matched, only this.
-- The revision trigger moves a revision on a change the app sees only, so
-- it is set aside for this update, under the writers' lock it takes
-- (lunaway_db::road_events::begin_writer): revisions still commit in the
-- order they are taken.
-- A writer holding the lock for long (a large feed) fails the migration
-- rather than holding the deploy; the release then stays on the previous
-- one (infra/server/install-release.sh), and the deploy is run again.
SET LOCAL lock_timeout = '2min';
SELECT pg_advisory_xact_lock(7815274093182148964);
ALTER TABLE road_events DISABLE TRIGGER road_events_revision;
UPDATE road_events SET revision = nextval('road_event_revision_seq')
    WHERE source IN ('ndw', 'dgt') AND ended_at IS NULL;
ALTER TABLE road_events ENABLE TRIGGER road_events_revision;
