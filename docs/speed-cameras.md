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
build) never leaves the server, whatever a row says. The app applies the
table again by the country it is in, the stricter rule at once at a border.

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
   anyone may edit it) or whose road's heading wavers across due north or
   due east between two graphs takes another share: with one share for
   both, the two versions' ends would solve for the camera (reviews of
   2026-10-06). Each
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
roads; 57 got a zone. Of those, 48 keep at least 90 % of the stretch before
the camera on the camera's road, 46 the stretch after it (a red light at a
junction turns off, as a driver does), by the engine's own matching of
each zone. The whole build of the 3 204 French cameras stored (2 within
1 km of Switzerland are not) took 26 s and 24 600 engine calls, most of
them failing at once for the cameras outside the extract.

An item is built again only when what it comes from changes; after a new
routing graph, the build runs with `--full`, and an item built again the
same as it is served is not written (phones do not fetch it again). A
build that would retire more than a tenth of the live items retires none
and fails, after writing the
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

## In the app

During guidance (`DrivingAidsEngine`,
`app/lib/features/navigation/application/driving_aids.dart`, run by the
guidance controller at each fix, screen off as well), and on the maps of the
route. The main map shows no camera and no zone: no layer of it holds them.

- **The rules in force.** The table the API last sent, else the one compiled
  into the library (`embedded_rules`), with the user's choices applied
  (`EnforcementRules.withChoices`): each country chosen takes its
  `optInMode`. A table without the field (an API older than the choice, the
  library's) takes `optInFallback`, which copies the server's only line:
  France, `EXACT`. These rules, never the table alone, decide what is kept
  on the device (`keptUnder`), what is alerted (`shownUnder`, the rule
  tracker) and what the maps draw. A country the table does not name stays
  off whatever was chosen.
- **France's positions.** A setting in the profile's guidance group,
  "Position exacte des radars en France", off by default, turned on in one
  gesture; under it a single sentence, the law: "En France, détenir un
  appareil qui signale la position des radars est puni de 1 500 € d'amende
  et 6 points (Code de la route, art. R413-15)." No box, no confirmation, no
  reminder afterwards. On, France reads as `exact`: its cameras show as
  everywhere points may (marks, banner, words). Off, France is zones only,
  as before. The choice (`DrivingAidsSettings.exactIn`) is never logged.
- **What leaves the device.** `Query.enforcement` for the countries the
  route crosses (worked out on the device every 5 km of the route and at
  its ends), at the start of a guidance, after a new route, when the choice
  changes and at the server's rhythm. `exactIn` names a chosen country only
  when the route crosses it (a trip in Spain says nothing of France), always
  as a variable. The cursor is kept with the countries and the `exactIn` it
  was asked with: another set of either starts from the whole set. An API
  that refuses the argument or the field gets the request without them
  (the client's older form): France's zones then, nothing lost.
- **What stays on the device.** The place cache (`enforcement_items`), so a
  guidance started offline has the data of its earlier trips. Only what the
  rules in force let the device keep is written. Withdrawing the choice
  removes France's points at once from every trip, offline too
  (`EnforcementFeed.purge`, `EnforcementStore.dropRefused`), queued behind
  any poll in flight so its pages cannot write them back; until the next
  answer, France has no data at all on the device. A read never hands out
  what the choices no longer allow, even if the purge did not run.
- **The country.** The guidance library reads the countries at the
  vehicle's position and within 1 km of it (`countries_around`, the same
  boundaries and margin as the server). The strictest rule among them
  applies at once; a looser one only once it has held 30 s. A fix less
  precise than 100 m changes nothing, and does not end an alert either.
  Without the library (desktop, web), no country is known and everything is
  off. A change of rule into another country, past the first fix, shows for
  8 s, on screen only: "Suisse : pas d'alerte radar", "France : zones de
  danger", "Espagne : radars". A choice changed during a trip is no border:
  nothing shows, and a looser rule waits its 30 s.
- **Germany.** Nothing anywhere, at rest as while driving. §23 Abs. 1c StVO
  binds the driver while driving, and a stop at a light or in a jam with the
  engine running counts as driving (OLG Karlsruhe, 2023); the app cannot
  tell such a stop from a parked vehicle (decision of 2026-10-09). The
  same for a device within 1 km of Germany.
- **On the route.** A zone counts where four of its points (or half of a
  shorter one) lie within 25 m of the route, either way; a camera within
  30 m, its bearing within 60 degrees of the route's; an average speed
  section with its road counts along it, as a zone does. An item shows only
  where the vehicle's rule and its own country's rule both allow its kind:
  a zone under `zones` or `exact`, a camera under `exact` only.
- **The alert.** One at a time, in the banner of the guidance's notices
  (`EnforcementNotice`): from about 20 s ahead (800 m at a limit of 110 or
  more, 400 m from 70, 200 m below), until the vehicle has passed its end by
  30 m (a camera's point) or 50 m (a zone, a section), whatever the reach
  does meanwhile. A stretch is entered only at its real start, and stays
  entered while the position wavers back across it. Zones less than 300 m
  apart along the route are one stretch: one alert, one word, no end
  between. A camera's point ahead takes the banner from the stretch the
  vehicle is in. The banner shows a pictogram (the camera's badge for a
  camera, a danger sign for a zone, never a camera for a zone), the kind
  ("Radar fixe", "Radar feu rouge", "Radar de passage à niveau", "Radar
  tronçon", "Zone de danger"), the distance in large ("800 m", then "encore
  1,2 km" inside a stretch), the sign of the limit that matters (the
  camera's own; else the road's where the vehicle is, grey when it is the
  default, none when the user hid it; "moyenne" above a section's), inside
  a section the vehicle's average from its start once it has driven 200 m
  of it ("votre moyenne 104 km/h", none when the guidance started inside
  it), and the lists with their date. Over that limit plus 3 km/h for 2 s
  (a section's average, once known), the banner turns to the error colours
  and says "au-dessus de la limite". At the end of a zone or a section,
  "Fin de la zone de danger" or "Fin du contrôle de vitesse moyenne" for
  4 s, unless another alert takes the screen. A screen reader hears one
  sentence, told again only when the alert comes, is entered, goes over its
  limit or back, or its average shows.
- **The words.** Each zone, camera and section once for the whole guidance,
  a new route included: "Radar fixe dans 800 mètres, limité à 90.",
  "Radar tronçon dans 800 mètres, moyenne limitée à 110.", "Zone de danger
  dans 400 mètres." ("Zone de danger." when the guidance starts inside).
  Over its limit, once per item: "Ralentissez, radar limité à 90.", in a
  zone with the road's limit known "Ralentissez, vitesse limitée à 90.";
  nothing without a limit known, nor for a red light or a level crossing.
  The road's own reminder stays quiet meanwhile. The guidance says them as
  its voice mode decides; the ends and the rules are never said.
- **On the maps of the route.** A danger zone is drawn as a translucent
  coral band under the chosen route, the stretch it covers and nothing
  more (`zoneSpans`). A camera, where both the rule at the device and the
  camera's own country's rule are `exact`, is a mark of the route
  (`RouteMarkKind.camera`, `RouteBadge.camera`: a camera on its mast, cream
  on navy in a lantern rim) with its limit written beside it
  (`camerasOnRoute`, `cameraMarker`): the same marks on the native maps and
  on the web page (browser, macOS, Windows). The legend has a row "Zone de
  danger" and a row "3 radars"; a tap on a camera opens its card: kind and
  limit, where on the route, "Contrôle votre sens de circulation" when its
  direction is known, its section's length, its lists with their date
  (the preview's callout, the guidance's sheet). The guidance's map follows
  the vehicle's rule. The preview's is read where the device is
  (`previewEnforcement`,
  `app/lib/features/navigation/application/preview_enforcement.dart`): the
  strictest rule of the countries around it, the same at rest as while
  driving, and while a guidance runs the vehicle's; no country known at the
  device (no position, no boundary library): nothing. The foot of the
  preview's panel cites each list with its date ("Zones de danger : ...",
  "Radars : ...", or both).
- **The limit.** `RouteSummary.speedLimits` at the vehicle's distance along
  the route; `DEFAULT` spans show in grey and never warn. Without spans,
  the sign the map gives, and only for a vehicle of 3.5 t or less with its
  trailer. Over the limit plus 3 km/h for 2 s, the speed shows on the
  error colour.
- **Settings** (profile, guidance): the limit shown (on by default); the
  road's limit said when the vehicle drives over it, with the voice's full
  mode (off by default: a word after 5 s, every 2 min while it lasts, again
  after 30 s under the limit); France's positions (off by default, above).
- **The credits** (profile, "Sources et crédits") name every list the
  server reads; a list the API describes that the sentence does not name
  yet is cited in its own words (`EnforcementSource.attribution`).

## Police checks

Lunaway takes no report of a police check, in any country, and offers no
such function. In France, L130-11 of the Code de la route lets the
prefect forbid an operator of a navigation service to relay its users'
messages around a check, and L130-12 punishes an operator that does not
comply (two years and 30 000 €), once the ban reaches it through the
Interior Ministry's information system, to which Lunaway is not connected.
Reports of mobile speed cameras are not offered either: the research asks
for a lawyer's reading first (`plan/research/28-radars-limites.md`, 1.3).
