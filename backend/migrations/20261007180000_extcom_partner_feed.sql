-- The external community source (`extcom`): a partner's places, reviews and
-- photos, received as a feed under a written agreement (docs/feeds.md).
-- Nothing of it is crawled: the feed is handed over, and every row keeps
-- the reference of the agreement it came under.
--
-- Who writes what:
--   - the importer (`lunaway_ingest`) writes the records, the agreements,
--     the reviews, the rating summaries and the photo rows, and the
--     switch that hides or purges a source;
--   - the API (`lunaway_app`) reads them, and fills in a photo's files the
--     first time a device asks for it (the photo proxy), then deletes the
--     rows of retired photos once their files are gone
--     (`lunaway extcom purge-media`).

INSERT INTO sources (id, name, licence, licence_url, attribution, url) VALUES
    ('extcom', 'Source communautaire externe', 'Written agreement',
     'https://lunaway.net',
     'Source communautaire externe',
     'https://lunaway.net');

-- The agreements a source's feeds came under: who granted what, when, and
-- until when. A feed names its agreement, which must be the one the
-- server is configured with; the importer refuses a feed without one, or
-- under one out of date. The latest one seen gives the source its licence
-- and attribution (`source_terms`). The photo hosts come from the
-- server's configuration, never from the feed.
CREATE TABLE source_agreements (
    source_id text NOT NULL REFERENCES sources (id),
    reference text NOT NULL CHECK (reference ~ '^[A-Za-z0-9][A-Za-z0-9._/-]{0,63}$'),
    grantor text NOT NULL CHECK (char_length(grantor) BETWEEN 1 AND 200),
    grantee text NOT NULL CHECK (char_length(grantee) BETWEEN 1 AND 200),
    signed_on date NOT NULL,
    valid_until date CHECK (valid_until IS NULL OR valid_until >= signed_on),
    -- What the agreement covers.
    scope text[] NOT NULL CHECK (
        cardinality(scope) > 0 AND scope <@ ARRAY['places', 'reviews', 'photos']::text[]),
    -- The text to show with the data, as the agreement words it.
    attribution text NOT NULL CHECK (char_length(attribution) BETWEEN 1 AND 300),
    licence_url text CHECK (licence_url ~ '^https://' AND char_length(licence_url) <= 500),
    -- The hosts the photos of this agreement may be fetched from.
    photo_hosts text[] NOT NULL DEFAULT '{}' CHECK (cardinality(photo_hosts) <= 16),
    first_seen_at timestamptz NOT NULL DEFAULT now(),
    last_seen_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (source_id, reference)
);

-- The switch of a source: hidden, its records count as retired for the
-- conflation and the API serves none of its reviews, ratings or photos;
-- purged, its content is gone as well. One row per source ever switched.
CREATE TABLE source_switches (
    source_id text PRIMARY KEY REFERENCES sources (id),
    hidden_at timestamptz,
    purged_at timestamptz,
    -- Why, for the operators: never a requester's personal data.
    note text CHECK (char_length(note) <= 500),
    changed_at timestamptz NOT NULL DEFAULT now(),
    CHECK (purged_at IS NULL OR hidden_at IS NOT NULL)
);

-- The terms each source is shown with: its own row, with the licence and
-- attribution of its latest agreement when it has one, and its switch.
CREATE VIEW source_terms AS
SELECT s.id, s.name,
       coalesce(a.reference, s.licence) AS licence,
       coalesce(a.licence_url, s.licence_url) AS licence_url,
       coalesce(a.attribution, s.attribution) AS attribution,
       s.url,
       w.hidden_at
FROM sources s
LEFT JOIN LATERAL (
    SELECT reference, licence_url, attribution FROM source_agreements g
    WHERE g.source_id = s.id
    ORDER BY g.last_seen_at DESC, g.reference
    LIMIT 1
) a ON true
LEFT JOIN source_switches w ON w.source_id = s.id;

-- The licence a record came under when it is not its source's own: the
-- reference of the agreement of the feed that delivered it. Nullable
-- without a default: no rewrite of the table.
ALTER TABLE source_records ADD COLUMN licence text
    CHECK (licence IS NULL OR char_length(licence) BETWEEN 1 AND 64);

-- Reviews of a partner's users, attached to the record that carried them:
-- the place they show on is whichever place that record belongs to.
CREATE TABLE external_reviews (
    -- UUID v7 stamped with the review's own date, so the newest come first
    -- in id order, as the community's reviews do.
    id uuid PRIMARY KEY,
    source_id text NOT NULL REFERENCES sources (id),
    record_id uuid NOT NULL REFERENCES source_records (id),
    external_id text NOT NULL CHECK (char_length(external_id) BETWEEN 1 AND 128),
    -- The partner's id of the author: never served, kept to honour an
    -- erasure request the partner forwards (`lunaway extcom erase-author`).
    author_id text CHECK (char_length(author_id) BETWEEN 1 AND 128),
    author text CHECK (char_length(author) BETWEEN 1 AND 64),
    written_at timestamptz NOT NULL,
    lang text CHECK (lang ~ '^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$'),
    rating smallint CHECK (rating BETWEEN 1 AND 5),
    body text CHECK (char_length(body) BETWEEN 1 AND 4000),
    vehicle text CHECK (vehicle IN ('van', 'campervan', 'motorhome', 'caravan', 'other')),
    -- The agreement it came under.
    licence text NOT NULL CHECK (char_length(licence) BETWEEN 1 AND 64),
    fetched_at timestamptz NOT NULL,
    changed_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (source_id, external_id),
    CHECK (rating IS NOT NULL OR body IS NOT NULL)
);

CREATE INDEX external_reviews_record_idx ON external_reviews (record_id, id DESC);

-- What a partner says of the ratings of a spot as a whole: more ratings
-- than the reviews it hands over.
CREATE TABLE external_ratings (
    record_id uuid PRIMARY KEY REFERENCES source_records (id),
    source_id text NOT NULL REFERENCES sources (id),
    average double precision NOT NULL CHECK (average BETWEEN 1 AND 5),
    count integer NOT NULL CHECK (count > 0),
    licence text NOT NULL CHECK (char_length(licence) BETWEEN 1 AND 64),
    fetched_at timestamptz NOT NULL
);

-- Photos of a partner's users. The feed gives a URL; the API's photo proxy
-- downloads it the first time a device asks for the photo, through the
-- same pipeline as an upload (decoded within bounds, re-encoded without
-- metadata, resized), and stores the files under the media root. A photo
-- is never shown from the partner's host.
CREATE TABLE external_photos (
    id uuid PRIMARY KEY,
    source_id text NOT NULL REFERENCES sources (id),
    record_id uuid NOT NULL REFERENCES source_records (id),
    external_id text NOT NULL CHECK (char_length(external_id) BETWEEN 1 AND 128),
    -- Emptied with the author when the photo is retired.
    url text CHECK (url ~ '^https://' AND char_length(url) <= 2048),
    author_id text CHECK (char_length(author_id) BETWEEN 1 AND 128),
    author text CHECK (char_length(author) BETWEEN 1 AND 64),
    -- The photo's own licence when the feed names one, else the agreement.
    licence text NOT NULL CHECK (char_length(licence) BETWEEN 1 AND 64),
    taken_at timestamptz,
    fetched_at timestamptz NOT NULL,
    -- Filled by the proxy.
    path text CHECK (path ~ '^photos/[0-9a-f]{2}/[0-9a-f]{2}/[0-9a-f]{64}\.(webp|jpg)$'),
    thumb_path text
        CHECK (thumb_path ~ '^photos/[0-9a-f]{2}/[0-9a-f]{2}/[0-9a-f]{64}\.(webp|jpg)$'),
    width integer CHECK (width > 0),
    height integer CHECK (height > 0),
    thumb_width integer CHECK (thumb_width > 0),
    thumb_height integer CHECK (thumb_height > 0),
    thumbhash bytea CHECK (octet_length(thumbhash) BETWEEN 1 AND 64),
    processed_at timestamptz,
    -- Failed downloads, and when the next one may be tried: a partner's
    -- host that refuses is not asked again at every view.
    attempts smallint NOT NULL DEFAULT 0 CHECK (attempts >= 0),
    retry_after timestamptz,
    -- No longer in the feed, its URL changed, or its source purged: never
    -- served again; `lunaway extcom purge-media` removes its files, then
    -- the row.
    retired_at timestamptz,
    CHECK ((path IS NULL) = (processed_at IS NULL)),
    CHECK (url IS NOT NULL OR retired_at IS NOT NULL)
);

-- One live photo per external id; a retired one stays until its files go.
CREATE UNIQUE INDEX external_photos_live_idx ON external_photos (source_id, external_id)
    WHERE retired_at IS NULL;
CREATE INDEX external_photos_record_idx ON external_photos (record_id, id DESC)
    WHERE retired_at IS NULL;
CREATE INDEX external_photos_retired_idx ON external_photos (id) WHERE retired_at IS NOT NULL;
CREATE INDEX external_photos_path_idx ON external_photos (path) WHERE path IS NOT NULL;
CREATE INDEX external_photos_thumb_path_idx ON external_photos (thumb_path)
    WHERE thumb_path IS NOT NULL;

CREATE INDEX external_reviews_author_idx ON external_reviews (source_id, author_id)
    WHERE author_id IS NOT NULL;
CREATE INDEX external_photos_author_idx ON external_photos (source_id, author_id)
    WHERE author_id IS NOT NULL;

-- Authors erased at the partner's request: the SHA-256 of the partner's
-- author id, never the id itself. An import skips their reviews and photos
-- while the partner's later feeds still carry them.
CREATE TABLE source_erasures (
    source_id text NOT NULL REFERENCES sources (id),
    author_hash text NOT NULL CHECK (author_hash ~ '^[0-9a-f]{64}$'),
    erased_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (source_id, author_hash)
);

REVOKE ALL ON source_agreements, source_switches, source_terms, external_reviews,
    external_ratings, external_photos, source_erasures FROM lunaway_app, lunaway_ingest;
GRANT SELECT, INSERT ON source_erasures TO lunaway_ingest;

GRANT SELECT, INSERT, UPDATE ON source_agreements, source_switches TO lunaway_ingest;
GRANT SELECT ON source_terms TO lunaway_ingest, lunaway_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON external_reviews, external_ratings TO lunaway_ingest;
-- No DELETE: a photo row names files the API wrote; the API's role
-- deletes it once the files are gone.
GRANT SELECT, INSERT, UPDATE ON external_photos TO lunaway_ingest;

GRANT SELECT ON source_agreements, source_switches, external_reviews, external_ratings
    TO lunaway_app;
GRANT SELECT, DELETE ON external_photos TO lunaway_app;
GRANT UPDATE (path, thumb_path, width, height, thumb_width, thumb_height, thumbhash,
              processed_at, attempts, retry_after) ON external_photos TO lunaway_app;
