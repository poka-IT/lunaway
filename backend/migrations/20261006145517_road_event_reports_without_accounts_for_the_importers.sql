-- The importers' role (lunaway_ingest), which parses untrusted payloads,
-- weighed the community's road events again at every pass. It needed each
-- active report's account to count two reports of one account once, and
-- with the account its time and, through the event, its position: a link
-- between an account and where it was, readable by the role most exposed.
-- Even without the account, the trust and ban flags of every report,
-- which change with the account's own (`accounts.trust_level`,
-- `banned_at`, readable by that role), would tie the reports back to it.
--
-- The weighing now runs in the API (its role reads the reports anyway):
-- the importers' role loses the read of `road_event_reports.account_id`
-- and gets nothing new. The weighing reads the reports through a view that
-- gives, instead of the account, a key distinct for each account and event
-- (two reports of one account on one event share it), so the rule it
-- applies never needs an account id. The salt behind the key is read by
-- the schema's owner only (the view runs with the owner's rights), and
-- holds one row: two rows would show every report twice under two keys,
-- one account counted as two.
CREATE TABLE road_event_report_salt (
    singleton BOOLEAN PRIMARY KEY DEFAULT true CHECK (singleton),
    salt TEXT NOT NULL CHECK (length(salt) >= 64)
);
INSERT INTO road_event_report_salt (salt)
    SELECT replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
REVOKE ALL ON road_event_report_salt FROM lunaway_app, lunaway_ingest;

CREATE VIEW road_event_report_facts AS
SELECT r.id, r.event_id, r.kind, r.value_m, r.status, r.created_at,
    md5(s.salt || r.account_id::text || r.event_id::text) AS reporter,
    a.trust_level >= 1 AS trusted,
    a.banned_at IS NOT NULL AS banned
FROM road_event_reports r
JOIN accounts a ON a.id = r.account_id
CROSS JOIN road_event_report_salt s;

REVOKE ALL ON road_event_report_facts FROM lunaway_app, lunaway_ingest;
GRANT SELECT ON road_event_report_facts TO lunaway_app;
REVOKE SELECT (account_id) ON road_event_reports FROM lunaway_ingest;
