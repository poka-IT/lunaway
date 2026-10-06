-- The poller weighs the community's road events again on every pass (an
-- account banned or deleted no longer counts). It reads the reports'
-- accounts, kinds, figures and times, never where or which way each
-- account was: it parses untrusted payloads, so it holds no more personal
-- data than the rule needs. Its purge of old reports filters on
-- created_at, which this grant covers.
REVOKE SELECT ON road_event_reports FROM lunaway_ingest;
GRANT SELECT (id, account_id, kind, value_m, event_id, status, created_at)
    ON road_event_reports TO lunaway_ingest;

-- The API removes a report by its status, never by deleting it; an
-- account's reports go with the account (ON DELETE CASCADE, run as the
-- table's owner).
REVOKE DELETE ON road_event_reports FROM lunaway_app;
