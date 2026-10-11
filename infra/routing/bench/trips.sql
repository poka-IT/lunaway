-- The route battery's trips: between motorhome areas without a height
-- limit, five bands of straight-line distance, 12 starts in France and 12
-- elsewhere in the graph's countries per band. Every endpoint is the
-- position of an OpenStreetMap record (ODbL) of a live place: no other
-- source's position leaves the API. Deterministic: rows are ordered by an
-- md5 of their id and a fixed salt, never by random(). Read-only; run as
-- postgres on the backend:
--   sudo -u postgres psql -X -q -d lunaway -f trips.sql > trips.csv
\pset format unaligned
\pset fieldsep ','
\pset tuples_only on
with covered(cc) as (
  select unnest(array['AD','AT','BE','CH','CZ','DE','DK','ES','FI','FR','GB','GR','HR','IE','IT','LI','LU','MA','NL','NO','PL','PT','SE','SI'])
),
areas as (
  select distinct on (p.id) p.id, r.geom, p.country_code,
         st_y(r.geom::geometry) as lat, st_x(r.geom::geometry) as lon
  from places p
  join place_sources s on s.place_id = p.id
  join source_records r on r.id = s.record_id
  where p.kind = 'motorhome_area' and p.deleted_at is null and p.merged_into is null
    and p.taken_down_at is null and p.max_height_m is null
    and p.country_code in (select cc from covered)
    and r.source_id = 'osm' and r.deleted_at is null
    -- the Canaries and other islands off the mainland
    and st_y(r.geom::geometry) > 30 and st_x(r.geom::geometry) > -10
  order by p.id, r.external_id
),
bands(band, lo_km, hi_km) as (
  values (1, 3, 15), (2, 15, 80), (3, 80, 400), (4, 400, 800), (5, 800, 2300)
),
groups(fr) as (values (true), (false)),
origins as (
  select b.band, b.lo_km, b.hi_km, g.fr, o.*
  from bands b cross join groups g
  cross join lateral (
    select a.* from areas a
    where (a.country_code = 'FR') = g.fr
    order by md5(a.id::text || 'p130-' || b.band || g.fr::text)
    limit 12
  ) o
)
select o.band, o.fr, o.country_code, d.country_code,
       round(o.lat::numeric, 6), round(o.lon::numeric, 6),
       round(d.lat::numeric, 6), round(d.lon::numeric, 6),
       round((st_distance(o.geom, d.geom) / 1000)::numeric, 1)
from origins o
cross join lateral (
  select a.* from areas a
  where st_dwithin(a.geom, o.geom, o.hi_km * 1000)
    and not st_dwithin(a.geom, o.geom, o.lo_km * 1000)
  order by md5(o.id::text || a.id::text || 'p130')
  limit 1
) d
order by o.band, o.fr desc, o.id;
