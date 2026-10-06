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
| `off` | nothing at all for a position in the country | Switzerland, Morocco, every country not named; the French overseas departments (MQ, GP, RE, GF: 102 cameras of the French list) for now, which the routing graph does not cover either |
| `off_while_driving` | camera points, for the map when the vehicle is not moving; no alert, no display while driving | Germany |
| `zones` | danger zones only: a stretch of road with its kind, never a camera's point, not even on the map or before a trip | France, Norway, Finland, Portugal, Italy, Ireland (the last three by the stricter-when-in-doubt rule) |
| `exact` | camera points with their kind, direction and limit when known | Austria, Luxembourg, Belgium, the Netherlands, Spain, the United Kingdom, Sweden, Denmark, Croatia, Slovenia, Greece, Poland, Czechia |

Decisions of the product owner, 2026-10-06: France in zones only;
Switzerland off with no data stored for a Swiss position (the database
refuses one, `country <> 'CH'`); Germany off while driving; Morocco off; the
others as the research concludes, the stricter mode where it leaves a doubt.

The server applies the table twice: when it builds the items, and again when
it serves each one (`enforcement_query::allowed`): a point in a zone
country, an item of a country that is off, or a point whose own position
lies in a country without points never leaves the server, whatever a row
says. The app applies the table again by the country it is in, the stricter
rule at once at a border.

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
   between 15 % and 85 %, drawn from a keyed hash of the camera's id with a
   server secret (`LUNAWAY_ZONE_SECRET`, 32 characters at least, never
   changed once zones are served): stable from one build to the next, so two
   builds compared do not reveal the camera.
4. No vertex of the zone lies within 15 m of the camera or of its place on
   the road (the engine cuts its route there; OpenStreetMap often maps the
   camera as a node of the road). A zone that doubles back on itself, whose
   ends come back near the camera, or that reaches into a country that is
   off, is not served.
5. An average speed section with a known end gives one zone from before its
   start to after its end.

Zones carry no direction: the app counts the vehicle inside a zone while it
drives along its line, either way.

Measured on 2026-10-06 against Valhalla 3.9.0 on the Limousin extract (the
build server's graph), with the French list of that day and the
OpenStreetMap cameras of the extract: 62 cameras stand on the graph's
roads; 58 got a zone. Of those, 50 keep at least 90 % of the stretch before
the camera on the camera's road, 44 the stretch after it (a red light at a
junction turns off, as a driver does). The whole build of the 3 206 French
cameras took 25 s and 24 600 engine calls, most of them failing at once
for the cameras outside the extract.

An item is built again only when what it comes from changes; after a new
routing graph, the build runs with `--full`. A build that would retire more
than a tenth of the live items retires none and fails, after writing the
new and changed ones (an engine without its graph places nothing).

## Operations

- daily, with the import role: `lunaway ingest cameras --refresh`, then
  `LUNAWAY_ZONE_SECRET=… lunaway enforcement build`;
- weekly, after a new routing graph is active: `lunaway ingest cameras-osm`
  (the same extracts as the places), then `lunaway enforcement build --full`;
- `lunaway enforcement stats`: each list's last read and the items by kind
  and country.

## The API

`Query.enforcement(since, countries, first)`: the items of the countries
asked changed since a cursor (`n1.<identity>.<revision>`), the rules table,
and each list with its terms and its last read (the CRPA asks the French
list's source and date to be cited). No position is sent; a phone keeps the
set of the countries it drives in and polls every `pollIntervalSeconds`
(6 h). Removals come back as ids, an item no longer allowed where it lies
among them.

`RouteSummary.speedLimits`: the limit for the vehicle along each route, in
spans of the route's geometry (`fromM`, `toM`, `fromIndex`, `toIndex`,
`kmh`, `source`): the posted limit where OpenStreetMap maps one, the road's
default in France otherwise (`DEFAULT`, an estimate the app shows as one),
and the vehicle's ceiling when it is lower (`VEHICLE`): R413-8-1 for a
motorhome of 3.5 to 12 t (110, 100 on separated carriageways, 80, 50),
R413-8 for a train above 3.5 t (90, 90 on separated carriageways up to
12 t, 80, 50). The engine describes the route's edges (`trace_attributes`,
`edge_walk`, 8 ms for the 95 km from Limoges to Brive); a route the engine
cannot describe within 3 s comes back without limits (`null`), never
refused.

## Police checks

Lunaway takes no report of a police check, in any country, and offers no
such function. In France, L130-11 of the Code de la route lets the
prefect forbid an operator of a navigation service to relay its users'
messages around a check, and L130-12 punishes an operator that does not
comply (two years and 30 000 €), once the ban reaches it through the
Interior Ministry's information system, to which Lunaway is not connected.
Reports of mobile speed cameras are not offered either: the research asks
for a lawyer's reading first (`plan/research/28-radars-limites.md`, 1.3).
