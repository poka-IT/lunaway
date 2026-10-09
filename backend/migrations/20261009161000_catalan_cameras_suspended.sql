-- Catalonia's speed camera list is suspended (docs/data-sources.md, "Speed
-- cameras"): https://transit.gencat.cat/robots.txt answers "User-agent: * /
-- Disallow: /" (read on 2026-10-09), and a source that refuses robots is not
-- read (.claude/rules/data-sources.md). Its cameras are retired, so the next
-- build retires their items and OpenStreetMap's cameras of Catalonia stand
-- on their own; its read is no longer cited with the items. Its row of
-- `sources` stays, for the history of what was served.
UPDATE enforcement_devices SET deleted_at = now(), changed_at = now()
WHERE source_id = 'cat-sct-radars' AND deleted_at IS NULL;

DELETE FROM enforcement_sources WHERE source_id = 'cat-sct-radars';
