-- The keys whose reviews Lunaway has kept, and since when. Anyone signs a
-- Mangrove review with a key made a second earlier, so a key is trusted
-- by its age here, not by what it says of itself: the content worker lets
-- a place gain few new keys per weekly run and ranks older keys first
-- (`docs/data-sources.md`, "Mangrove reviews"). A key enters this table
-- the first time one of its reviews is kept, and stays when the review
-- goes: its history is what it earned.
CREATE TABLE content_review_keys (
    source_id text NOT NULL REFERENCES sources (id),
    -- The SHA-256 of the key, as `content_reviews.author_key`.
    author_key text NOT NULL CHECK (author_key ~ '^[0-9a-f]{64}$'),
    first_kept_at timestamptz NOT NULL,
    PRIMARY KEY (source_id, author_key)
);

-- The reviews already shown were kept before the cap existed: their keys
-- keep their place.
INSERT INTO content_review_keys (source_id, author_key, first_kept_at)
SELECT source_id, author_key, min(fetched_at)
FROM content_reviews
WHERE author_key IS NOT NULL
GROUP BY source_id, author_key;

REVOKE ALL ON content_review_keys FROM lunaway_app, lunaway_ingest;
-- The content worker, run as the import role, reads and extends it; the
-- API never reads it.
GRANT SELECT, INSERT ON content_review_keys TO lunaway_ingest;
