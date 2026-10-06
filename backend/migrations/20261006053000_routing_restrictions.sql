-- Routing for motorhomes: the graphs the routing engine serves, and the
-- physical limits every computed route is checked against before the app
-- sees it (docs/deploy.md, "Routing"; plan/research/07-navigation.md, E).
--
-- A graph is built weekly from OpenStreetMap and IGN BD TOPO; its
-- restrictions are loaded with it (`lunaway routing load`), then the graph
-- is activated once the engine serves it (`lunaway routing activate`). The
-- API reads the active graph's restrictions and the community's, never
-- writes either.

CREATE TABLE routing_graphs (
    -- The build's name: its UTC time, then the area (20261006T0300Z-fr).
    id TEXT PRIMARY KEY CHECK (id ~ '^[0-9]{8}T[0-9]{4}Z-[a-z0-9]{2,16}$'),
    -- The OpenStreetMap data's own date: the extract's replication timestamp.
    osm_data_at TIMESTAMPTZ NOT NULL,
    -- When the IGN restrictions were read; null when the build had none.
    ign_fetched_at TIMESTAMPTZ,
    -- The BD TOPO edition they come from, for the attribution.
    ign_edition DATE,
    built_at TIMESTAMPTZ NOT NULL,
    -- Engine name, version and image digest.
    engine TEXT NOT NULL CHECK (length(engine) BETWEEN 1 AND 200),
    -- The build's counts, as `lunaway routing prepare` reported them.
    stats JSONB NOT NULL DEFAULT '{}',
    loaded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    activated_at TIMESTAMPTZ,
    active BOOLEAN NOT NULL DEFAULT false
);

-- One graph serves at a time.
CREATE UNIQUE INDEX routing_graphs_one_active ON routing_graphs (active) WHERE active;

CREATE TABLE route_restrictions (
    id UUID PRIMARY KEY,
    -- The graph whose build produced the row; null for a community report,
    -- which outlives graphs.
    graph_id TEXT REFERENCES routing_graphs (id) ON DELETE CASCADE,
    source TEXT NOT NULL CHECK (source IN ('osm', 'ign', 'community')),
    -- way/<id> and node/<id> for OpenStreetMap, ign/<cleabs> for BD TOPO.
    external_id TEXT NOT NULL CHECK (length(external_id) BETWEEN 1 AND 100),
    kind TEXT NOT NULL CHECK (kind IN ('max_height', 'max_width', 'max_length',
        'max_weight', 'max_axle_load', 'motorhome_ban', 'trailer_ban', 'caravan_ban')),
    -- Metres or tonnes; null for a ban and for an unknown clearance.
    limit_value DOUBLE PRECISION CHECK (limit_value > 0 AND limit_value <= 100),
    certainty TEXT NOT NULL CHECK (certainty IN ('known', 'disputed', 'unknown')),
    feature TEXT NOT NULL CHECK (feature IN ('underpass', 'tunnel', 'building_passage',
        'bridge', 'barrier', 'road')),
    name TEXT CHECK (length(name) <= 200),
    -- The other source's figure when two disagree beyond the tolerance (the
    -- review queue is the disputed rows).
    other_value DOUBLE PRECISION CHECK (other_value > 0 AND other_value <= 100),
    other_source TEXT CHECK (other_source IN ('osm', 'ign', 'community')),
    -- A point for a node or a report, a line for a way or a road section.
    geom geography(Geometry, 4326) NOT NULL
        CHECK (GeometryType(geom::geometry) IN ('POINT', 'LINESTRING')),
    -- The date of the data: the extract's, the section's last change at
    -- IGN, the report's.
    observed_at TIMESTAMPTZ NOT NULL,
    CHECK ((source = 'community') = (graph_id IS NULL)),
    CHECK (CASE
        WHEN kind IN ('motorhome_ban', 'trailer_ban', 'caravan_ban') THEN limit_value IS NULL
        WHEN certainty = 'unknown' THEN kind = 'max_height' AND limit_value IS NULL
        ELSE limit_value IS NOT NULL
    END),
    CHECK ((certainty = 'disputed') = (other_value IS NOT NULL AND other_source IS NOT NULL))
);

-- The corridor query of every route: rows within a few metres of its line.
CREATE INDEX route_restrictions_geom_idx ON route_restrictions USING gist (geom);
CREATE INDEX route_restrictions_graph_idx ON route_restrictions (graph_id);

REVOKE ALL ON routing_graphs, route_restrictions FROM lunaway_app, lunaway_ingest;
-- The API checks routes against them and tells the app the data's date.
GRANT SELECT ON routing_graphs, route_restrictions TO lunaway_app;
-- The publication loads a graph's rows, activates it and drops the rows of
-- graphs older than the one before it.
GRANT SELECT, INSERT, UPDATE, DELETE ON routing_graphs, route_restrictions TO lunaway_ingest;
