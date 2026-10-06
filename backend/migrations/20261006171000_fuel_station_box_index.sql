-- The box of a route's corridor is a box of degrees: compared as geometry,
-- as the other viewport queries do. Compared as geography, its southern
-- edge is a great circle bending north, and a station just above it near
-- longitude 0 falls outside: a station at Tarbes (43.23 N, 0.07 E) in the
-- box from 43.2075 to 43.62 N and -2.96 to 5.40 E is outside as geography,
-- inside as geometry (PostGIS 3.6, 2026-10-06, after the Rust review).
CREATE INDEX poi_join_fuel_box_idx ON poi_join_records USING gist ((geom::geometry))
    WHERE source_id = 'prix-carburants' AND deleted_at IS NULL;
