-- Ratings and reviews of the points of interest and the establishments
-- (a bakery, a garage, a restaurant), by Lunaway users: the same rules as
-- the reviews of places (`reviews`), one per account and point, published
-- under CC BY 4.0 (`community-cc-by`). A point is never merged into
-- another, so a row names its point and nothing follows it elsewhere. The
-- point's rating is read from these rows when it is served: the points of
-- interest carry no community summary, and the API, which writes these
-- rows, never writes a point.
CREATE TABLE poi_reviews (
    -- UUID v7, generated in Rust.
    id uuid PRIMARY KEY,
    poi_id uuid NOT NULL REFERENCES pois (id),
    -- Null once the account is deleted: a published review with text
    -- stays without author, as a review of a place does.
    account_id uuid REFERENCES accounts (id),
    source_id text NOT NULL DEFAULT 'community-cc-by' REFERENCES sources (id),
    stars smallint NOT NULL CHECK (stars BETWEEN 1 AND 5),
    -- Null for a rating alone, which is published at once; a text goes
    -- through the automatic rules first.
    body text CHECK (body IS NULL OR char_length(body) BETWEEN 10 AND 2000),
    -- The language the author wrote in, as the app says it (BCP 47).
    lang text CHECK (lang ~ '^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$'),
    visited_on date,
    status text NOT NULL CHECK (status IN ('published', 'pending', 'hidden', 'removed')),
    -- Deleted by its author while held or reported: the text goes, the row
    -- stays with its status for the moderators (`reviews.withdrawn_at`).
    withdrawn_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX poi_reviews_account_poi_idx ON poi_reviews (account_id, poi_id)
    WHERE account_id IS NOT NULL;
-- A point's reviews newest first, and its rating.
CREATE INDEX poi_reviews_poi_idx ON poi_reviews (poi_id, id DESC);

-- A user reports a review of a point as a review of a place, and a held or
-- reported one waits in the same queue.
ALTER TABLE content_reports
    DROP CONSTRAINT content_reports_target_type_check,
    ADD CONSTRAINT content_reports_target_type_check CHECK (target_type IN (
        'review', 'photo', 'place', 'external_review', 'external_photo', 'poi_review'));

ALTER TABLE moderation_queue
    DROP CONSTRAINT moderation_queue_target_type_check,
    ADD CONSTRAINT moderation_queue_target_type_check CHECK (target_type IN (
        'review', 'photo', 'place', 'submission', 'poi', 'road_event', 'place_hold',
        'external_review', 'external_photo', 'poi_review'));

-- The API writes them, and the moderation and retention commands run with
-- its role. The importers and the worker never read them: a point's
-- visibility does not depend on its reviews.
REVOKE ALL ON poi_reviews FROM lunaway_app, lunaway_ingest;
GRANT SELECT, INSERT, UPDATE, DELETE ON poi_reviews TO lunaway_app;
