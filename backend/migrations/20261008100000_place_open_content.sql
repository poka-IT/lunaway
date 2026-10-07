-- Open content of the places: photos, descriptions and reviews read from
-- open sources by the content worker (`lunaway content refresh`), each
-- item with its author, its licence and its link (docs/data-sources.md,
-- "Open content"). Kept apart from the places: the change feed and the
-- offline packs never carry them; the card asks for them by place.

INSERT INTO sources (id, name, licence, licence_url, attribution, url) VALUES
    ('wikimedia-commons', 'Wikimedia Commons',
     'Per file: CC0, public domain, CC BY or CC BY-SA',
     'https://commons.wikimedia.org/wiki/Commons:Licensing',
     'Wikimedia Commons, with each file''s author and licence',
     'https://commons.wikimedia.org/'),
    ('wikipedia', 'Wikipedia', 'CC BY-SA 4.0',
     'https://creativecommons.org/licenses/by-sa/4.0/',
     'Wikipedia contributors, with a link to the article',
     'https://www.wikipedia.org/'),
    ('panoramax', 'Panoramax',
     'Per instance: Licence Ouverte 2.0 or CC BY-SA 4.0',
     'https://panoramax.fr/',
     'Panoramax, with each picture''s author and licence',
     'https://panoramax.fr/'),
    ('mangrove', 'Mangrove Reviews', 'CC BY 4.0',
     'https://creativecommons.org/licenses/by/4.0/',
     'Mangrove Reviews, with each reviewer''s nickname',
     'https://mangrove.reviews/'),
    ('datatourisme', 'DATAtourisme', 'Licence Ouverte 2.0',
     'https://www.etalab.gouv.fr/licence-ouverte-open-licence/',
     'DATAtourisme, with the producing tourist office',
     'https://www.datatourisme.fr/')
ON CONFLICT (id) DO NOTHING;

-- One photo shown on one place. The files are content-addressed under the
-- media root (`external/...`), re-encoded from pixels by lunaway-media: no
-- metadata of the source file survives, and the app never loads the
-- source's own URL.
CREATE TABLE content_photos (
    -- UUID v7, generated in Rust.
    id uuid PRIMARY KEY,
    place_id uuid NOT NULL REFERENCES places (id),
    source_id text NOT NULL REFERENCES sources (id),
    -- `File:<name>` on Commons, the picture's UUID on Panoramax.
    external_id text NOT NULL CHECK (length(external_id) BETWEEN 1 AND 300),
    -- What the source's copy was when the files were made (Commons's
    -- SHA-1 of the file): a new version is downloaded again.
    version text NOT NULL CHECK (length(version) <= 100),
    relation text NOT NULL CHECK (relation IN ('linked', 'facing', 'nearby')),
    -- From the place to where the picture was taken; NULL when unknown.
    distance_m real CHECK (distance_m >= 0),
    -- Where the photo is published, with its author and licence.
    page_url text NOT NULL CHECK (page_url ~ '^https://'),
    title text CHECK (length(title) <= 300),
    author text CHECK (length(author) <= 300),
    -- Who published it at the source when that is not the author (a
    -- tourist office on DATAtourisme, a Panoramax instance).
    publisher text CHECK (length(publisher) <= 300),
    -- The source's own date of its last update, which the Licence
    -- Ouverte asks to show.
    source_updated_on date,
    licence text NOT NULL CHECK (length(licence) BETWEEN 1 AND 100),
    licence_url text NOT NULL CHECK (licence_url ~ '^https://'),
    taken_at timestamptz,
    -- The last day the source lets it be shown (a DATAtourisme photo's
    -- `rightsEndDate`): the card stops showing it after that day, whether
    -- or not a refresh ran since.
    rights_end_on date,
    path text NOT NULL,
    thumb_path text NOT NULL,
    width integer NOT NULL CHECK (width > 0),
    height integer NOT NULL CHECK (height > 0),
    thumbhash bytea NOT NULL,
    -- Order on the card: linked photos first, then facing, then nearby.
    rank smallint NOT NULL,
    fetched_at timestamptz NOT NULL,
    UNIQUE (place_id, source_id, external_id)
);

CREATE INDEX content_photos_place_idx ON content_photos (place_id, rank);
-- A file is downloaded once for every place that shows it.
CREATE INDEX content_photos_external_idx ON content_photos (source_id, external_id, version);
-- Whether any row still points at a file before it is removed.
CREATE INDEX content_photos_path_idx ON content_photos (path);
CREATE INDEX content_photos_thumb_path_idx ON content_photos (thumb_path);

-- One description of one place by one source, in one language.
CREATE TABLE content_descriptions (
    place_id uuid NOT NULL REFERENCES places (id),
    source_id text NOT NULL REFERENCES sources (id),
    -- BCP 47, lower-case primary tag.
    lang text NOT NULL CHECK (lang ~ '^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$'),
    text text NOT NULL CHECK (length(text) BETWEEN 1 AND 2000),
    title text CHECK (length(title) <= 300),
    page_url text NOT NULL CHECK (page_url ~ '^https://'),
    author text CHECK (length(author) <= 300),
    publisher text CHECK (length(publisher) <= 300),
    source_updated_on date,
    licence text NOT NULL CHECK (length(licence) BETWEEN 1 AND 100),
    licence_url text NOT NULL CHECK (licence_url ~ '^https://'),
    fetched_at timestamptz NOT NULL,
    PRIMARY KEY (place_id, source_id, lang)
);

-- One review published elsewhere under an open licence, attached to the
-- place it is about.
CREATE TABLE content_reviews (
    -- UUID v7, generated in Rust.
    id uuid PRIMARY KEY,
    place_id uuid NOT NULL REFERENCES places (id),
    source_id text NOT NULL REFERENCES sources (id),
    -- The review's signature on Mangrove.
    external_id text NOT NULL CHECK (length(external_id) BETWEEN 1 AND 300),
    rating smallint CHECK (rating BETWEEN 1 AND 5),
    text text CHECK (length(text) <= 4000),
    lang text CHECK (lang ~ '^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$'),
    -- The pseudonym the reviewer chose; never a key or an address.
    author text CHECK (length(author) <= 300),
    -- The SHA-256 of the key that signed it, so an operator can hide every
    -- review of one author (`content_hides`); never shown.
    author_key text CHECK (author_key ~ '^[0-9a-f]{64}$'),
    written_at timestamptz NOT NULL,
    page_url text NOT NULL CHECK (page_url ~ '^https://'),
    licence text NOT NULL CHECK (length(licence) BETWEEN 1 AND 100),
    licence_url text NOT NULL CHECK (licence_url ~ '^https://'),
    -- From the place to where the review says it is, metres.
    distance_m real CHECK (distance_m >= 0),
    fetched_at timestamptz NOT NULL,
    CHECK (rating IS NOT NULL OR text IS NOT NULL),
    UNIQUE (source_id, external_id)
);

CREATE INDEX content_reviews_place_idx ON content_reviews (place_id, written_at DESC);

-- When each source was last asked about each place, so a weekly pass
-- resumes where it stopped and asks the places least recently checked
-- first.
CREATE TABLE content_checks (
    place_id uuid NOT NULL REFERENCES places (id),
    source_id text NOT NULL REFERENCES sources (id),
    checked_at timestamptz NOT NULL,
    -- Items kept from that check.
    found integer NOT NULL CHECK (found >= 0),
    PRIMARY KEY (place_id, source_id)
);

CREATE INDEX content_checks_due_idx ON content_checks (source_id, checked_at);

-- What an operator hid (`lunaway content hide`), kept apart from the
-- content so that a refresh, which replaces the content, never brings it
-- back: a review edited on its source, or signed again, or a file that
-- left the source and came back, stays hidden. The card reads every
-- content row through these.
CREATE TABLE content_hides (
    source_id text NOT NULL REFERENCES sources (id),
    -- `item`: one photo or review, by its id at the source, on every
    -- place; `author`: every review signed by one key (its SHA-256);
    -- `place`: everything the source shows on one place (its id);
    -- `source`: the whole source.
    scope text NOT NULL CHECK (scope IN ('item', 'author', 'place', 'source')),
    key text NOT NULL CHECK (length(key) BETWEEN 1 AND 300),
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (source_id, scope, key)
);

REVOKE ALL ON content_photos, content_descriptions, content_reviews, content_checks,
    content_hides FROM lunaway_app, lunaway_ingest;

-- The API serves the content; the content worker, run as the import role,
-- writes and replaces it, and the operator's hides go through the same
-- role. Nothing here is a contribution: the API writes none of it.
GRANT SELECT ON content_photos, content_descriptions, content_reviews, content_hides
    TO lunaway_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON content_photos, content_descriptions, content_reviews,
    content_checks TO lunaway_ingest;
GRANT SELECT, INSERT, DELETE ON content_hides TO lunaway_ingest;
