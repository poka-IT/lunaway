-- The vehicle limits a place states besides its height, for the app's "my
-- vehicle fits" filter (length, width, weight). Nullable: no rewrite of the
-- table. The roles' grants on `places` are table-wide, so they cover the
-- new columns.
ALTER TABLE places
    ADD COLUMN max_length_m double precision CHECK (max_length_m > 0),
    ADD COLUMN max_width_m double precision CHECK (max_width_m > 0),
    ADD COLUMN max_weight_t double precision CHECK (max_weight_t > 0);
