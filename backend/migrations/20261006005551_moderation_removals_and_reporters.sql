-- Removals by moderation are counted on the account, where the author
-- cannot erase them by deleting the removed review or photo: the "nothing
-- removed" condition of level 2 rests on this count.
ALTER TABLE accounts
    ADD COLUMN moderation_removals integer NOT NULL DEFAULT 0 CHECK (moderation_removals >= 0);

-- The worker counts toward a place's verification only the confirmations of
-- accounts past level 0, so it reads their level too.
GRANT SELECT (trust_level) ON accounts TO lunaway_ingest;

-- The worker queues for its own summary step the places a conflation step
-- changed (absorbed places, community places), so a failure between the
-- two steps loses nothing.
GRANT INSERT ON place_refresh_queue TO lunaway_ingest;

-- Each run of the worker looks for places showing an issue whose window
-- passed; most places show none.
CREATE INDEX places_reported_issues_idx ON places (id)
    WHERE deleted_at IS NULL AND reported_issues <> '[]';

-- An author who deletes a review or a photo that moderation holds, or that
-- has reports pending, withdraws it: its text or files go as asked, the row
-- stays with its status, reports and queue entry, so deleting and posting
-- again does not escape a moderator, and an approval never publishes what
-- the author withdrew.
ALTER TABLE reviews ADD COLUMN withdrawn_at timestamptz;
ALTER TABLE photos ADD COLUMN withdrawn_at timestamptz;

-- A report a moderator dismissed stays, so the same reporters cannot file
-- it again, and no longer counts toward hiding.
ALTER TABLE content_reports ADD COLUMN dismissed_at timestamptz;
