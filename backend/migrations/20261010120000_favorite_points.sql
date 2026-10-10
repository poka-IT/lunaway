-- Points saved in a favourite list outside the places of the data: an
-- address the search found, a town, a bare point of the map, or a shop or
-- a service (a point of interest). Each keeps what the device saved: the
-- name the user gave it, a short note, the postal address when known, and
-- its coordinates.
--
-- They are the account's own and private: no query serves them to anyone
-- but the account that owns the list. They go with the account through
-- the cascade accounts -> favorite_lists -> favorite_points.
--
-- The id is chosen by the device that saved the point, so a point saved
-- offline keeps one identity across devices and syncs; unique within a
-- list (the same point may sit in several lists).
CREATE TABLE favorite_points (
    list_id uuid NOT NULL REFERENCES favorite_lists (id) ON DELETE CASCADE,
    id uuid NOT NULL,
    kind text NOT NULL CHECK (kind IN ('address', 'town', 'point', 'poi')),
    name text NOT NULL CHECK (char_length(name) BETWEEN 1 AND 120),
    note text CHECK (char_length(note) BETWEEN 1 AND 280),
    address text CHECK (char_length(address) BETWEEN 1 AND 200),
    lat double precision NOT NULL CHECK (lat BETWEEN -90 AND 90),
    lon double precision NOT NULL CHECK (lon BETWEEN -180 AND 180),
    -- A shop or a service: the point of interest and its kind, to open its
    -- page again; neither for any other kind.
    poi_id uuid,
    poi_kind text,
    added_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (list_id, id),
    CHECK ((kind = 'poi') = (poi_id IS NOT NULL)),
    CHECK ((poi_id IS NULL) = (poi_kind IS NULL))
);

-- The API reads and writes them for their account; the importers and the
-- worker never see them.
REVOKE ALL ON favorite_points FROM lunaway_app, lunaway_ingest;
GRANT SELECT, INSERT, UPDATE, DELETE ON favorite_points TO lunaway_app;
