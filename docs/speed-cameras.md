# Speed cameras and speed limits

What Lunaway knows of speed cameras, the only form each country lets an app
carry them in, and the speed limit along a route. The research behind it,
with every legal source: `plan/research/28-radars-limites.md` (maintainer's
copy). The sources and their terms: `docs/data-sources.md`, "Speed cameras".

## The rules by country

`lunaway_domain::enforcement::RULES`, versioned with the code
(`RULES_VERSION`, `RULES_REVIEWED`), each line with the texts it rests on.
A country the table does not name is off, and so is a position no country
boundary covers.

| mode | what the API serves, what the app shows | countries (2026-10-06) |
|---|---|---|
| `off` | nothing at all for a position in the country | Switzerland, Morocco, Monaco, Andorra, every country not named; the French overseas departments for now (their positions read MQ, GP, RE, GF: 102 cameras of the French list), which the routing graph does not cover either |
| `off_while_driving` | camera points, for the map when the vehicle is not moving; no alert, no display while driving | Germany |
| `zones` | danger zones only: a stretch of road with its kind, never a camera's point, not even on the map or before a trip | France, Norway, Finland, Portugal, Italy, Ireland (the last three by the stricter-when-in-doubt rule) |
| `exact` | camera points with their kind, direction and limit when known | Austria, Luxembourg, Belgium, the Netherlands, Spain, the United Kingdom, Sweden, Denmark, Croatia, Slovenia, Greece, Poland, Czechia |

Decisions of the product owner, 2026-10-06: France in zones only;
Switzerland off with no data stored for a Swiss position (the database
refuses one, `country <> 'CH'`); Germany off while driving; Morocco off; the
others as the research concludes, the stricter mode where it leaves a doubt.

Borders. The embedded boundaries are simplified: they strive "to have at
least every settlement and major road on the correct side of the border"
(country-boundaries 1.2.0, README), not every camera. So:

- an official list's cameras take the list's country, wherever a position
  reads near a border;
- nothing within 1 km of Switzerland is stored, from any source
  (`BORDER_MARGIN_M`, `near_country`: the point and 16 points on circles
  of 500 m and 1 km around it, none of the disc more than about 400 m from
  one of them; the 1 km itself is an assumption on how far the simplified
  boundaries stray, not measured);
- a camera takes the rule of its country and of every country within 1 km
  of it, the strictest form of what may leave the server (`served_form`:
  off, then zones, then points): a Spanish camera at Irun becomes a zone, a
  French one by Monaco gets nothing.

The server applies the table twice: when it builds the items, and again when
it serves each one (`enforcement_query::allowed`, off the async threads):
a point where only zones may be shown (its country, or a country within
1 km of the point), an item of a country that is off, a zone running into
a country that is off, or a section's road running into a zone country
(lines read every 20th point there, every fourth with the margin at the
build) never leaves the server, whatever a row says. The app applies the table again by the country it is
in, the stricter rule at once at a border.

## Zone lengths

4 km on a motorway, 2 km outside built-up areas, 500 m inside them
(`FRENCH_ZONES`). These figures come from the press (Le Parisien of
2017-04-27, as Wikipédia "Avertisseur de radar" cites it): the agreement of
2011 between the State and the AFFTAC that sets them is not published.
They stand until a lawyer confirms them. The other zone countries take the
same lengths, which no text of theirs sets.

A camera's length follows its limit when a source gives one (110 km/h and
above: motorway; 50 and below: built-up area); otherwise the road it stands
on (a motorway's length when the engine's route starts on a motorway, the
rural length elsewhere, a longer zone hiding more).

## How a zone is built

`lunaway enforcement build` (`lunaway-ingest/src/enforcement.rs`), with the
routing engine on loopback:

1. The cameras of every source are merged: an OpenStreetMap camera within
   50 m of an official one of the same kind completes it (direction, limit,
   a section's end) where the official list's licence allows the mix.
2. The camera's road is read through the engine: a route leaving the camera
   in its direction toward a point well beyond, and a route driven
   backwards from it (one-way roads ignored), each kept as long as it stays
   on the camera's road by its reference or name, never by a ramp; where it
   leaves, a new route goes on from there.
3. The zone is cut from that road with the camera at a share of its length
   between 15 % and 85 %, measured along the road's canonical direction
   (read toward the east: the road's own heading at the camera, 50 m
   either side, taken modulo 180 degrees), so the same road driven either
   way gives the same zone, whatever a direction tag says (`zone_sides`).
   The share comes from a keyed hash of the camera's id, the zone's length
   and the half of the compass its canonical direction points to, with a
   server secret (`LUNAWAY_ZONE_SECRET`, 32 characters at least, never
   changed once zones are served). A zone whose length changes (a limit
   mapped or removed on the OpenStreetMap node that completes the camera:
   anyone may edit it) or whose road's heading wavers across due north
   between two graphs takes another share: with one share for both, the two
   versions' ends would solve for the camera (reviews of 2026-10-06). Each
   version narrows the camera down to where the versions overlap, toward
   15 % of the shortest zone on each side of it; a camera has at most six
   (three lengths, two halves), and nothing else may change its share.
4. The zone is drawn with a point every 50 m along its road from its start
   (`ZONE_STEP_M`), none of them a vertex of the road: the engine cuts its
   route where the camera snaps, OpenStreetMap often maps the camera as a
   node of its road, and a gap where vertices were removed around the
   camera would mark it as well. A chord of 50 m strays at most 18 m from
   the road at a right-angled corner. A zone that drives some road twice,
   whose ends come back near the camera, whose road steps sideways at the
   camera (the road behind and the road ahead snapped to two
   carriageways), or that reaches within 1 km of a country that is off
   (every fourth point read), is not served.
5. An average speed section with a known end gives one zone from before its
   start to after its end.

Zones carry no direction: the app counts the vehicle inside a zone while it
drives along its line, either way.

Measured on 2026-10-06 against Valhalla 3.9.0 on the Limousin extract (the
build server's graph), with the French list of that day and the
OpenStreetMap cameras of the extract: 62 cameras stand on the graph's
roads; 57 got a zone. Of those, 50 keep at least 90 % of the stretch before
the camera on the camera's road, 47 the stretch after it (a red light at a
junction turns off, as a driver does), by the engine's own matching of
each zone. The whole build of the 3 204 French cameras stored (2 within
1 km of Switzerland are not) took 27 s and 24 600 engine calls, most of
them failing at once for the cameras outside the extract.

An item is built again only when what it comes from changes; after a new
routing graph, the build runs with `--full`, and an item built again the
same as it is served is not written (phones do not fetch it again). A build that would retire more
than a tenth of the live items retires none and fails, after writing the
new and changed ones (an engine without its graph places nothing);
`--allow-retire` lifts that guard when the cause is known (a country turned
off). Items are written in the order of their ids, which nothing outside
the server ties to a camera: the feed's revisions do not follow the
official lists' ids.

## Operations

- daily, with the import role: `lunaway ingest cameras --refresh`, then
  `lunaway enforcement build` with `LUNAWAY_ZONE_SECRET` in its
  environment;
- weekly, after a new routing graph is active: `lunaway ingest cameras-osm`
  (the same extracts as the places), then `lunaway enforcement build --full`;
- `lunaway enforcement stats`: each list's last read and the items by kind
  and country.

## The API

`Query.enforcement(since, countries, first)`: the items of the countries
asked changed since a cursor (`n2.<identity>.<countries>.<revision>`), the
rules table, and each list with its terms, its last read and the date it
gives of its own last update (`listUpdatedAt`, Catalonia's Last-Modified;
the CRPA asks the French list's source and date to be cited, and the
Generalitat's licence the date of the last update). No position is sent; a
phone keeps the set of the countries it drives in and polls every
`pollIntervalSeconds` (6 h). A cursor issued for another set of countries
gets the whole set again (`full`), so a country added comes whole. Removals
come back as ids, an item no longer allowed where it lies among them. The
API's database role reads every column of the items but `device_key` and
`content_hash`.

`RouteSummary.speedLimits`: the limit for the vehicle along each route, in
spans of the route's geometry (`fromM`, `toM`, `fromIndex`, `toIndex`,
`kmh`, `source`): the posted limit where OpenStreetMap maps one, the road's
default in France otherwise (`DEFAULT`, an estimate the app shows as one),
and the vehicle's ceiling when it is lower (`VEHICLE`): R413-8-1 for a
motorhome of 3.5 to 12 t (110, 100 on separated carriageways, 80, 50),
R413-8 for a train above 3.5 t (90, 90 on separated carriageways up to
12 t, 80, 50). The engine describes the route's edges (`trace_attributes`,
`edge_walk`, 8 ms for the 95 km from Limoges to Brive), only when the
request selects `speedLimits`; a route the engine cannot describe within
3 s comes back without limits (`null`), never refused. Inside a built-up
area the default is 50, separated carriageways or not.

## Police checks

Lunaway takes no report of a police check, in any country, and offers no
such function. In France, L130-11 of the Code de la route lets the
prefect forbid an operator of a navigation service to relay its users'
messages around a check, and L130-12 punishes an operator that does not
comply (two years and 30 000 €), once the ban reaches it through the
Interior Ministry's information system, to which Lunaway is not connected.
Reports of mobile speed cameras are not offered either: the research asks
for a lawyer's reading first (`plan/research/28-radars-limites.md`, 1.3).
