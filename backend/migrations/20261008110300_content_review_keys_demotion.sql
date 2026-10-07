-- A key whose review the reports, a moderator or the operator hid loses
-- the rank its age gave it, for good: a hide names one review by its
-- signature, and the key's author can sign the same text again under a
-- new one, which no hide matches. The content worker sets `demoted_at`
-- while the hidden review is still stored, and from then on ranks the
-- key with the new ones.
ALTER TABLE content_review_keys ADD COLUMN demoted_at timestamptz;

GRANT UPDATE (demoted_at) ON content_review_keys TO lunaway_ingest;
