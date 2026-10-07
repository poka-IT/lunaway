-- Phones receive only the road events in force or starting within the
-- window (`road_events_feed_window`): NDW publishes two weeks of planned
-- works, and a phone's whole set grew elevenfold with events it has no use
-- for yet. Routes still read every event at the vehicle's time of arrival
-- (`lunaway_db::road_events::events_near` does not look at the window).
--
-- `in_window` says whether phones receive an event. The revision trigger
-- sets it from `valid_from` when the event is written with a new start;
-- the poller's lifecycle pass sets it once the start comes within the
-- window (`lunaway_db::road_events::lifecycle`), and that change takes a
-- new revision: the cursor of the change feed then delivers an event that
-- itself did not change. An event outside the window keeps its revision
-- while it changes (a new match, a new version), so phones are not sent
-- the removal of an event they never held; one written outside it from
-- the start gets revision 0, below every cursor, until it enters.

-- One place for the window: the trigger and the lifecycle pass read it.
CREATE FUNCTION road_events_feed_window() RETURNS interval
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$ SELECT interval '48 hours' $$;

-- Under the writers' lock the trigger takes (lunaway_db::road_events::
-- begin_writer), as the previous migration: the revisions moved here
-- commit in the order they are taken. A writer holding it for long fails
-- the migration rather than holding the deploy.
SET LOCAL lock_timeout = '2min';
SELECT pg_advisory_xact_lock(7815274093182148964);
-- ADD COLUMN locks the table against the API's reads too: a long route
-- read ahead of it would hold every request behind the migration.
SET LOCAL lock_timeout = '10s';

ALTER TABLE road_events ADD COLUMN in_window BOOLEAN NOT NULL DEFAULT true;

-- Phones may hold the live events that start later than the window (every
-- French one, and the Dutch and Spanish ones if the previous migration ran
-- in an earlier deploy): each takes a new revision, which reaches phones
-- as a removal. An ended one keeps its revision, its end already reached
-- the phones that held it; it is flagged all the same, because a source
-- that publishes it again revives it without a new start, and it must
-- then wait for the window.
ALTER TABLE road_events DISABLE TRIGGER road_events_revision;
UPDATE road_events SET in_window = false
    WHERE ended_at IS NOT NULL AND valid_from > now() + road_events_feed_window();
UPDATE road_events SET in_window = false, revision = nextval('road_event_revision_seq')
    WHERE ended_at IS NULL AND valid_from > now() + road_events_feed_window();
ALTER TABLE road_events ENABLE TRIGGER road_events_revision;

CREATE OR REPLACE FUNCTION road_events_revision() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM pg_advisory_xact_lock(7815274093182148964);
    -- A new start places the event again; otherwise the flag is the
    -- writer's (the lifecycle pass), so a test can move its clock.
    IF TG_OP = 'INSERT' OR NEW.valid_from IS DISTINCT FROM OLD.valid_from THEN
        NEW.in_window := NEW.valid_from <= now() + road_events_feed_window();
    END IF;
    IF TG_OP = 'INSERT' THEN
        NEW.revision := CASE WHEN NEW.in_window
            THEN nextval('road_event_revision_seq') ELSE 0 END;
    ELSIF (OLD.in_window OR NEW.in_window) AND (
        NEW.content_hash IS DISTINCT FROM OLD.content_hash
        OR NEW.ended_at IS DISTINCT FROM OLD.ended_at
        OR NEW.match_quality IS DISTINCT FROM OLD.match_quality
        OR NEW.matched_graph_id IS DISTINCT FROM OLD.matched_graph_id
        OR NEW.confidence IS DISTINCT FROM OLD.confidence
        OR NEW.in_window IS DISTINCT FROM OLD.in_window)
    THEN
        NEW.revision := nextval('road_event_revision_seq');
    ELSE
        NEW.revision := OLD.revision;
    END IF;
    RETURN NEW;
END
$$;

-- The lifecycle pass's search, every three minutes: a few thousand rows.
CREATE INDEX road_events_waiting_idx ON road_events (valid_from)
    WHERE ended_at IS NULL AND NOT in_window;
