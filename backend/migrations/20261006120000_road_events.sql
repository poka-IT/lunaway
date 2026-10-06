-- Road events: closures, works, lane restrictions, temporary vehicle limits
-- and detours, from the open feeds of docs/data-sources.md ("Road events")
-- and from the community's reports, each bounded in time. Every route is
-- checked against the events active when the vehicle gets there, and the
-- app polls their changes during guidance (docs/architecture.md, "Road
-- events"; plan/research/21-backend-travaux.md).
--
-- The rows live from minutes to months, unlike the weekly restrictions of
-- `route_restrictions`, so they have their own table, written by the
-- importers (`lunaway road-events poll`, role lunaway_ingest) and, for the
-- community's reports only, by the API (role lunaway_app, held to the
-- `community` source by row security).

CREATE TABLE road_event_sources (
    id TEXT PRIMARY KEY CHECK (id ~ '^[a-z0-9-]{2,40}$'),
    name TEXT NOT NULL CHECK (length(name) BETWEEN 1 AND 200),
    licence TEXT NOT NULL CHECK (length(licence) BETWEEN 1 AND 200),
    attribution TEXT NOT NULL CHECK (length(attribution) BETWEEN 1 AND 300),
    url TEXT NOT NULL CHECK (length(url) BETWEEN 1 AND 500),
    -- Once the feed has not been read for this long, none of its events
    -- blocks a route: what the app and the route check call stale.
    stale_after_s INTEGER NOT NULL CHECK (stale_after_s BETWEEN 60 AND 2592000),
    last_attempt_at TIMESTAMPTZ,
    -- The last read that succeeded, in full or in part (an increment).
    last_success_at TIMESTAMPTZ,
    -- The last complete snapshot applied: events missing from it ended.
    last_full_at TIMESTAMPTZ,
    last_error TEXT CHECK (length(last_error) <= 2000),
    -- Where the next read resumes: the last increment applied, the ETag of
    -- the last snapshot.
    state JSONB NOT NULL DEFAULT '{}'
);

-- Terms as read on 2026-10-06 (docs/data-sources.md). Staleness: twice the
-- feed's own period plus a margin.
INSERT INTO road_event_sources (id, name, licence, attribution, url, stale_after_s) VALUES
    ('dir', 'Évènements routiers, réseau routier national non concédé (DIR)',
     'Licence Ouverte 2.0',
     'DIR, Bison Futé (transport.data.gouv.fr)',
     'https://transport.data.gouv.fr/datasets/evenements-routiers-sur-le-reseau-routier-national-non-concede',
     7800),
    ('dialog', 'DiaLog, base nationale de la réglementation de circulation',
     'Licence Ouverte 2.0',
     'DiaLog (DGITM), arrêtés de circulation',
     'https://transport.data.gouv.fr/datasets/base-de-donnees-nationale-de-la-reglementation-de-circulation',
     3600),
    ('paris-fermetures', 'Ville de Paris, fermetures de voirie',
     'ODbL',
     'Ville de Paris (opendata.paris.fr)',
     'https://opendata.paris.fr/explore/dataset/fermetures-voirie/',
     10800),
    ('paris-chantiers', 'Ville de Paris, chantiers perturbants',
     'ODbL',
     'Ville de Paris (opendata.paris.fr)',
     'https://opendata.paris.fr/explore/dataset/chantiers-perturbants/',
     10800),
    ('lyon', 'Métropole de Lyon, chantiers perturbants',
     'Licence Ouverte 2.0',
     'Métropole de Lyon (data.grandlyon.com)',
     'https://www.data.gouv.fr/datasets/chantiers-perturbants-de-la-metropole-de-lyon',
     10800),
    ('toulouse', 'Toulouse Métropole, chantiers en cours',
     'Licence Ouverte 2.0',
     'Toulouse Métropole (data.toulouse-metropole.fr)',
     'https://data.toulouse-metropole.fr/explore/dataset/chantiers-en-cours/',
     10800),
    ('charente-maritime', 'Département de la Charente-Maritime, incidents et routes fermées',
     'Licence Ouverte 2.0',
     'Département de la Charente-Maritime (data.gouv.fr)',
     'https://www.data.gouv.fr/datasets/incidents-et-routes-fermees',
     10800),
    ('community', 'Lunaway community reports',
     'ODbL 1.0',
     'Lunaway contributors',
     'https://lunaway.net',
     43200);

CREATE SEQUENCE road_event_revision_seq;

CREATE TABLE road_events (
    id UUID PRIMARY KEY,
    source TEXT NOT NULL REFERENCES road_event_sources (id),
    -- The source's identifier: a DIR situation record, a DiaLog regulation
    -- and its index, a city's record, a community event.
    external_id TEXT NOT NULL CHECK (length(external_id) BETWEEN 1 AND 200),
    -- The source's version, or a digest of the content when it has none.
    external_version TEXT NOT NULL CHECK (length(external_version) BETWEEN 1 AND 100),
    -- The DIR situation the record belongs to: a new version of a
    -- situation ends the records it no longer carries.
    situation_id TEXT CHECK (length(situation_id) <= 200),
    class TEXT NOT NULL CHECK (class IN ('closure', 'works', 'lane_restriction',
        'vehicle_limit', 'detour')),
    -- The source's own term (roadClosed, laneClosures, noEntry, Rue barrée).
    detail TEXT NOT NULL CHECK (length(detail) BETWEEN 1 AND 100),
    -- Which part of the road: the main carriageway, an entry or exit slip
    -- road, or unknown. A slip road event never blocks the main carriageway.
    carriageway TEXT NOT NULL CHECK (carriageway IN ('main', 'entry', 'exit', 'ramps',
        'unknown')),
    -- The direction concerned, relative to the order of `geom_source`'s
    -- points (a DIR section from its `from` to its `to`): both, forward
    -- only, or a compass label the source gives (`north` ...) for a point.
    direction TEXT NOT NULL CHECK (direction IN ('both', 'forward', 'north', 'south', 'east',
        'west', 'unknown')),
    -- The course of the users who reported it, degrees from north: a
    -- report concerns the direction it was made in.
    heading_deg SMALLINT CHECK (heading_deg BETWEEN 0 AND 359),
    -- Normalised road number (N165, A75, D949) and name, when given.
    road_number TEXT CHECK (road_number ~ '^[A-Z]{1,3}[0-9]{1,4}[A-Z]?$'),
    road_name TEXT CHECK (length(road_name) <= 200),
    -- The limits of a vehicle_limit event, and whom they concern.
    max_height_m DOUBLE PRECISION CHECK (max_height_m > 0 AND max_height_m <= 10),
    max_width_m DOUBLE PRECISION CHECK (max_width_m > 0 AND max_width_m <= 10),
    max_length_m DOUBLE PRECISION CHECK (max_length_m > 0 AND max_length_m <= 50),
    max_weight_t DOUBLE PRECISION CHECK (max_weight_t > 0 AND max_weight_t <= 100),
    applies_to TEXT NOT NULL DEFAULT 'all' CHECK (applies_to IN ('all', 'goods_vehicles')),
    valid_from TIMESTAMPTZ NOT NULL,
    -- Null when the source gives no end.
    valid_to TIMESTAMPTZ CHECK (valid_to IS NULL OR valid_to >= valid_from),
    -- When, within the validity, the event applies (`lunaway_domain::
    -- road_events::Schedule`, JSON). `schedule_assumed` marks hours this
    -- code chose for a period the source names without hours ("de nuit").
    schedule JSONB NOT NULL DEFAULT '{}',
    schedule_assumed BOOLEAN NOT NULL DEFAULT false,
    -- The geometry as the source gives it: a point, a line, a polygon.
    geom_source geography(Geometry, 4326) NOT NULL,
    -- The roads of the routing graph it covers: lines in driving order,
    -- one per direction concerned.
    geom_matched geography(MultiLineString, 4326),
    match_quality TEXT NOT NULL CHECK (match_quality IN ('pending', 'matched', 'ramp',
        'point', 'unmatched')),
    -- The graph the match was made on; no foreign key, graphs come and go.
    matched_graph_id TEXT,
    -- official (a source's own record), reported (one account), confirmed
    -- (two accounts or more).
    confidence TEXT NOT NULL CHECK (confidence IN ('official', 'reported', 'confirmed')),
    description TEXT CHECK (length(description) <= 2000),
    detour TEXT CHECK (length(detour) <= 1000),
    url TEXT CHECK (length(url) <= 500),
    source_updated_at TIMESTAMPTZ,
    first_seen_at TIMESTAMPTZ NOT NULL,
    last_seen_at TIMESTAMPTZ NOT NULL,
    ended_at TIMESTAMPTZ,
    end_reason TEXT CHECK (end_reason IN ('source_end', 'disappeared', 'expired', 'past_end',
        'cleared', 'moderated')),
    -- A digest of what the app receives of the event: a change moves the
    -- revision (trigger below).
    content_hash TEXT NOT NULL CHECK (length(content_hash) BETWEEN 1 AND 64),
    -- The source's record, as it came (XML or JSON text), at most 64 KiB.
    raw TEXT NOT NULL CHECK (length(raw) <= 65536),
    -- The position of the last change in the feed the app polls.
    revision BIGINT NOT NULL,
    UNIQUE (source, external_id),
    CHECK ((ended_at IS NULL) = (end_reason IS NULL)),
    CHECK (match_quality <> 'matched' OR geom_matched IS NOT NULL)
);

-- The corridor queries of every route, on either geometry.
CREATE INDEX road_events_matched_idx ON road_events USING gist (geom_matched)
    WHERE ended_at IS NULL;
CREATE INDEX road_events_source_geom_idx ON road_events USING gist (geom_source)
    WHERE ended_at IS NULL;
-- The feed of changes the app polls.
CREATE INDEX road_events_revision_idx ON road_events (revision);
-- The live events of a source, for its reconciliation and expiry.
CREATE INDEX road_events_live_idx ON road_events (source, last_seen_at) WHERE ended_at IS NULL;
CREATE INDEX road_events_situation_idx ON road_events (source, situation_id)
    WHERE situation_id IS NOT NULL;

-- Every change the app must see takes a new revision: what it shows (the
-- digest), its end, its match. `last_seen_at` alone does not: it moves at
-- every read of a feed, and freshness is a property of the feed
-- (`road_event_sources.last_success_at`).
--
-- The app reads the changes past its cursor, so revisions must commit in
-- the order they are taken: every writer of road_events holds one
-- advisory lock until it commits ("lunaroad", lunaway_db::road_events::
-- begin_writer). The writers take it before anything else; the trigger
-- takes it too, so a writer that forgot (a moderator's command, a psql
-- session) still cannot commit a revision past one still in flight.
CREATE FUNCTION road_events_revision() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM pg_advisory_xact_lock(7815274093182148964);
    IF TG_OP = 'INSERT'
        OR NEW.content_hash IS DISTINCT FROM OLD.content_hash
        OR NEW.ended_at IS DISTINCT FROM OLD.ended_at
        OR NEW.match_quality IS DISTINCT FROM OLD.match_quality
        OR NEW.matched_graph_id IS DISTINCT FROM OLD.matched_graph_id
        OR NEW.confidence IS DISTINCT FROM OLD.confidence
    THEN
        NEW.revision := nextval('road_event_revision_seq');
    ELSE
        NEW.revision := OLD.revision;
    END IF;
    RETURN NEW;
END
$$;

CREATE TRIGGER road_events_revision BEFORE INSERT OR UPDATE ON road_events
    FOR EACH ROW EXECUTE FUNCTION road_events_revision();

-- Rows purged after their audit week: a client whose cursor is older than
-- the newest purged revision cannot learn of their end, and gets the whole
-- set again.
CREATE TABLE road_event_purges (
    singleton BOOLEAN PRIMARY KEY DEFAULT true CHECK (singleton),
    purged_through BIGINT NOT NULL DEFAULT 0
);
INSERT INTO road_event_purges DEFAULT VALUES;

-- A report by a user on the road: what they saw, where, heading which way.
-- The community event it supports is computed from the reports of
-- distinct accounts (`lunaway_domain::road_events::community`).
CREATE TABLE road_event_reports (
    id UUID PRIMARY KEY,
    account_id UUID NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
    kind TEXT NOT NULL CHECK (kind IN ('closure', 'works', 'narrow_passage', 'low_clearance',
        'cleared')),
    geom geography(Point, 4326) NOT NULL,
    heading_deg SMALLINT CHECK (heading_deg BETWEEN 0 AND 359),
    -- The measured height (low_clearance) or width (narrow_passage), metres.
    value_m DOUBLE PRECISION CHECK (value_m > 0 AND value_m <= 10),
    -- The community event the report supports or ends.
    event_id UUID REFERENCES road_events (id) ON DELETE SET NULL,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'removed')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX road_event_reports_geom_idx ON road_event_reports USING gist (geom);
CREATE INDEX road_event_reports_account_idx ON road_event_reports (account_id, created_at);
CREATE INDEX road_event_reports_event_idx ON road_event_reports (event_id);

-- A report a moderator looks at: the queue takes a new target type.
ALTER TABLE moderation_queue
    DROP CONSTRAINT moderation_queue_kind_check,
    ADD CONSTRAINT moderation_queue_kind_check CHECK (kind IN (
        'held_review', 'reported_content', 'place_proposal', 'place_check', 'poi_check',
        'road_report')),
    DROP CONSTRAINT moderation_queue_target_type_check,
    ADD CONSTRAINT moderation_queue_target_type_check CHECK (target_type IN (
        'review', 'photo', 'place', 'submission', 'poi', 'road_event'));

-- DiaLog's permanent orders join the static restrictions every route is
-- checked against, outside any graph, like the community's. A weight limit
-- DiaLog sets for heavy goods vehicles is its own kind: a motorhome is not
-- a goods vehicle, so it warns and never blocks.
ALTER TABLE route_restrictions
    DROP CONSTRAINT route_restrictions_kind_check,
    ADD CONSTRAINT route_restrictions_kind_check CHECK (kind IN ('max_height', 'max_width',
        'max_length', 'max_weight', 'max_axle_load', 'motorhome_ban', 'trailer_ban',
        'caravan_ban', 'max_weight_goods')),
    DROP CONSTRAINT route_restrictions_source_check,
    ADD CONSTRAINT route_restrictions_source_check CHECK (source IN ('osm', 'ign', 'community',
        'dialog')),
    DROP CONSTRAINT route_restrictions_check,
    ADD CONSTRAINT route_restrictions_check CHECK (
        (source IN ('community', 'dialog')) = (graph_id IS NULL)),
    DROP CONSTRAINT route_restrictions_other_source_check,
    ADD CONSTRAINT route_restrictions_other_source_check CHECK (other_source IN ('osm', 'ign',
        'community', 'dialog'));

REVOKE ALL ON road_event_sources, road_events, road_event_purges, road_event_reports
    FROM lunaway_app, lunaway_ingest;
REVOKE ALL ON SEQUENCE road_event_revision_seq FROM lunaway_app, lunaway_ingest;

-- The importers write the events of every source, end and purge them, and
-- keep each feed's cursor; they read the reports for nothing.
GRANT SELECT, UPDATE ON road_event_sources TO lunaway_ingest;
GRANT SELECT, INSERT, UPDATE, DELETE ON road_events TO lunaway_ingest;
GRANT SELECT, UPDATE ON road_event_purges TO lunaway_ingest;
GRANT SELECT, DELETE ON road_event_reports TO lunaway_ingest;
GRANT USAGE ON SEQUENCE road_event_revision_seq TO lunaway_ingest;

-- The API serves the events and the feeds' freshness, and writes the
-- community's reports and the community's events only.
GRANT SELECT ON road_event_sources, road_event_purges TO lunaway_app;
GRANT SELECT, INSERT, UPDATE ON road_events TO lunaway_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON road_event_reports TO lunaway_app;
GRANT USAGE ON SEQUENCE road_event_revision_seq TO lunaway_app;

-- The DiaLog weekly load replaces its own rows of the static restrictions.
-- (lunaway_ingest already holds SELECT, INSERT, UPDATE, DELETE on them.)

ALTER TABLE road_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY road_events_read ON road_events FOR SELECT USING (true);
CREATE POLICY road_events_ingest ON road_events TO lunaway_ingest USING (true) WITH CHECK (true);
CREATE POLICY road_events_app_insert ON road_events FOR INSERT TO lunaway_app
    WITH CHECK (source = 'community');
CREATE POLICY road_events_app_update ON road_events FOR UPDATE TO lunaway_app
    USING (source = 'community') WITH CHECK (source = 'community');
