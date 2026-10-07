-- A demotion set once (`content_review_keys.demoted_at`, previous
-- migration) outlived the hide that caused it: three reports on an honest
-- review, a run before the moderator keeps it, and the key lost its rank
-- for good. A key now ranks with the new keys only while a hide of one of
-- its reviews stands: a hide names one review by its signature, and the
-- key's author can sign the same text again under a new one, which no hide
-- matches. The content worker records the strike while the hidden review is
-- still stored; a moderator who keeps the review, or an operator who shows
-- it again, lifts the hide and with it the strike's effect.
ALTER TABLE content_review_keys DROP COLUMN demoted_at;

CREATE TABLE content_review_strikes (
    source_id text NOT NULL REFERENCES sources (id),
    author_key text NOT NULL CHECK (author_key ~ '^[0-9a-f]{64}$'),
    -- The hidden review's signature, as `content_hides.key`.
    external_id text NOT NULL CHECK (length(external_id) BETWEEN 1 AND 300),
    PRIMARY KEY (source_id, author_key, external_id)
);

-- When Lunaway first read each review it matched to a place: the reviews
-- that wait for room wait in that order, which no author sets, rather than
-- by the date a review claims.
CREATE TABLE content_review_sightings (
    source_id text NOT NULL REFERENCES sources (id),
    external_id text NOT NULL CHECK (length(external_id) BETWEEN 1 AND 300),
    first_seen_at timestamptz NOT NULL,
    PRIMARY KEY (source_id, external_id)
);

REVOKE ALL ON content_review_strikes, content_review_sightings FROM lunaway_app, lunaway_ingest;
-- The content worker, run as the import role, keeps both; the API never
-- reads them.
GRANT SELECT, INSERT ON content_review_strikes TO lunaway_ingest;
GRANT SELECT, INSERT, DELETE ON content_review_sightings TO lunaway_ingest;
