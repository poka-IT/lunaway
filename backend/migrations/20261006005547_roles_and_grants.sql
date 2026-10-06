-- What each service may do, stated by the schema itself rather than left to
-- the server's default privileges. Migrations run as the owner of the tables
-- (`lunaway_owner` in production); the API connects as `lunaway_app`, the
-- importers and the conflation as `lunaway_ingest`.
--
-- Roles are created only when missing, as NOLOGIN: production creates them
-- beforehand with their passwords (infra/server/postgres.sh), and the owner
-- needs no CREATEROLE to run this file there. A new table gets its grants in
-- the migration that creates it.

DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'lunaway_app') THEN
        CREATE ROLE lunaway_app NOLOGIN;
    END IF;
EXCEPTION
    -- Roles belong to the cluster: another database migrating at the same
    -- moment (the sqlx tests migrate one database per test) created it
    -- between the check and the creation.
    WHEN duplicate_object OR unique_violation THEN NULL;
END
$$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'lunaway_ingest') THEN
        CREATE ROLE lunaway_ingest NOLOGIN;
    END IF;
EXCEPTION
    WHEN duplicate_object OR unique_violation THEN NULL;
END
$$;

-- Start from nothing, whatever default privileges granted earlier: the
-- migrations table included, which no service may write.
REVOKE ALL ON sources, source_records, places, place_sources, match_pairs,
    conflation_constraints, sync_epoch, _sqlx_migrations
    FROM lunaway_app, lunaway_ingest;
REVOKE ALL ON SEQUENCE place_change_seq FROM lunaway_app, lunaway_ingest;

-- The API reads what it serves, and writes nothing.
GRANT SELECT ON sources, source_records, places, place_sources, sync_epoch TO lunaway_app;

-- The importers write the records, the conflation the places, their links
-- and the pairs. Nothing deletes a record or a place: a gone record or place
-- becomes a tombstone the change feed reports, so DELETE is not granted on
-- them. The sources come from migrations; human constraints come from
-- moderation; both are only read.
GRANT SELECT ON sources, conflation_constraints TO lunaway_ingest;
GRANT SELECT, INSERT, UPDATE ON source_records, places TO lunaway_ingest;
GRANT SELECT, INSERT, UPDATE, DELETE ON place_sources, match_pairs TO lunaway_ingest;
-- `updated_seq` takes its value from the sequence on every place write
-- (nextval only, which USAGE allows).
GRANT USAGE ON SEQUENCE place_change_seq TO lunaway_ingest;
