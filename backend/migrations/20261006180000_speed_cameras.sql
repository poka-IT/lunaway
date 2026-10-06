-- Speed cameras: what the sources say (enforcement_devices), and what the
-- API serves under each country's rule (enforcement_items): danger zones,
-- stretches of road without a camera's point, where positions may not be
-- shown, and cameras elsewhere (lunaway_domain::enforcement, docs/speed-cameras.md).

INSERT INTO sources (id, name, licence, licence_url, attribution, url) VALUES
    -- No licence is written on the site; the Code des relations entre le
    -- public et l'administration (L321-1, L322-1) allows the reuse of
    -- published public information, unaltered, its source and the date of
    -- its last update cited (decision recorded in docs/data-sources.md).
    ('securite-routiere', 'Sécurité routière, radars', 'CRPA L321-1, L322-1',
     'https://codes.droit.org/PDF/Code%20des%20relations%20entre%20le%20public%20et%20l''administration.pdf',
     'Sécurité routière, radars.securite-routiere.gouv.fr',
     'https://radars.securite-routiere.gouv.fr/'),
    ('pl-canard', 'GITD CANARD, urządzenia rejestrujące', 'CC0 1.0',
     'https://creativecommons.org/publicdomain/zero/1.0/',
     'Główny Inspektorat Transportu Drogowego (CANARD), dane.gov.pl',
     'https://dane.gov.pl/pl/dataset/4364'),
    ('lu-pch-radars', 'Ponts et Chaussées, radars fixes', 'CC0 1.0',
     'https://creativecommons.org/publicdomain/zero/1.0/',
     'Administration des ponts et chaussées, data.public.lu',
     'https://data.public.lu/fr/datasets/pch-emplacement-des-radars-fixes/'),
    ('cat-sct-radars', 'Servei Català de Trànsit, radars', 'Llicència oberta d''ús d''informació de la Generalitat',
     'https://web.gencat.cat/ca/generalitat/dades-indicadors/dades-obertes/llicencies',
     'Servei Català de Trànsit, Generalitat de Catalunya',
     'https://analisi.transparenciacatalunya.cat/d/re3y-fftf'),
    ('no-nvdb-atk', 'Statens vegvesen, NVDB, automatisk trafikkontroll', 'NLOD 1.0',
     'https://data.norge.no/nlod/no/1.0',
     'Inneholder data under norsk lisens for offentlige data (NLOD) tilgjengeliggjort av Statens vegvesen.',
     'https://nvdbapiles.atlas.vegvesen.no/');

-- A camera as one source describes it.
CREATE TABLE enforcement_devices (
    source_id text NOT NULL REFERENCES sources (id),
    external_id text NOT NULL CHECK (char_length(external_id) BETWEEN 1 AND 64),
    -- ISO 3166-1 of its position; a Swiss camera is never stored.
    country text NOT NULL CHECK (country ~ '^[A-Z]{2}$' AND country <> 'CH'),
    kind text NOT NULL CHECK (kind IN ('fixed', 'red_light', 'section', 'level_crossing')),
    geom geography(Point, 4326) NOT NULL,
    -- lunaway_domain::enforcement::Device as JSON.
    data jsonb NOT NULL,
    raw jsonb NOT NULL,
    fetched_at timestamptz NOT NULL,
    changed_at timestamptz NOT NULL DEFAULT now(),
    -- The source no longer lists it.
    deleted_at timestamptz,
    PRIMARY KEY (source_id, external_id)
);

CREATE INDEX enforcement_devices_geom_idx ON enforcement_devices USING gist (geom)
    WHERE deleted_at IS NULL;

-- What the API serves, built from the devices under each country's rule:
-- a zone is a line along the road with no camera's point in it; a camera
-- is a point. `device_key` (source and id of the device it comes from)
-- stays on the server: a zone's camera could be looked up by it.
CREATE TABLE enforcement_items (
    id uuid PRIMARY KEY,
    device_key text NOT NULL UNIQUE,
    kind text NOT NULL CHECK (kind IN ('zone', 'camera')),
    category text NOT NULL
        CHECK (category IN ('fixed', 'red_light', 'section_control', 'section', 'level_crossing')),
    country text NOT NULL CHECK (country ~ '^[A-Z]{2}$' AND country <> 'CH'),
    line geography(LineString, 4326),
    point geography(Point, 4326),
    bearing_deg real,
    limit_kmh smallint,
    source_ids text[] NOT NULL,
    -- A digest of what the item was built from (its devices, its country's
    -- rule): an unchanged one is not built again.
    content_hash text NOT NULL,
    revision bigint NOT NULL,
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    CHECK ((kind = 'zone' AND point IS NULL AND line IS NOT NULL AND bearing_deg IS NULL
            AND limit_kmh IS NULL)
        OR (kind = 'camera' AND point IS NOT NULL))
);

CREATE SEQUENCE enforcement_revision_seq;

-- When each list was last read, and what it held: the date the CRPA asks to
-- cite with the French list, and the freshness the app shows.
CREATE TABLE enforcement_sources (
    source_id text PRIMARY KEY REFERENCES sources (id),
    fetched_at timestamptz NOT NULL,
    devices integer NOT NULL CHECK (devices >= 0),
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX enforcement_items_revision_idx ON enforcement_items (revision);

REVOKE ALL ON enforcement_devices, enforcement_items, enforcement_sources
    FROM lunaway_app, lunaway_ingest;
REVOKE ALL ON SEQUENCE enforcement_revision_seq FROM lunaway_app, lunaway_ingest;
-- The API reads only what it serves.
GRANT SELECT ON enforcement_items, enforcement_sources TO lunaway_app;
GRANT SELECT, INSERT, UPDATE ON enforcement_devices, enforcement_items, enforcement_sources
    TO lunaway_ingest;
GRANT USAGE ON SEQUENCE enforcement_revision_seq TO lunaway_ingest;
