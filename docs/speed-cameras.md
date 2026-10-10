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

| mode | what the API serves, what the app shows | countries (2026-10-09) |
|---|---|---|
| `off` | nothing at all for a position in the country | Switzerland, Liechtenstein, Morocco, Monaco, San Marino, the Vatican (each named with its reason), every country not named; the French overseas departments for now (their positions read MQ, GP, RE, GF: 102 cameras of the French list), which the routing graph does not cover either |
| `off_while_driving` | camera points, for the map when the vehicle is not moving; no alert, no display while driving | Germany |
| `zones` | danger zones only: a stretch of road, never a camera's point nor its kind (`DANGER_ZONE`), not even on the map or before a trip | France by default, Norway, Finland, Portugal, Ireland, Greece |
| `exact` | camera points with their kind, direction and limit when known | Italy, Andorra, Austria, Luxembourg, Belgium, the Netherlands, Spain, the United Kingdom, Sweden, Denmark, Croatia, Slovenia, Poland, Czechia; France for a user who asked for it ("The choice of positions in France") |

Decisions of the product owner, 2026-10-06: France in zones;
Switzerland off with no data stored for a Swiss position (the database
refuses one, `country <> 'CH'`); Germany off while driving; Morocco off; the
others as the research concludes, the stricter mode where it leaves a doubt.
Decisions of 2026-10-09: in France, a user may ask for the cameras' exact
positions by an explicit setting of the app; without it, zones as before.
After the legal review of that day (maintainer's research, chantier 89,
part 4): Italy in exact positions (the Ministry of the Interior's circular
n. 300/A/1/24236/144/5/20/5 of 2007-07-06 leaves pre-recorded positions
out of art. 45 c. 9-bis of the Codice della strada; Cassazione, ordinanza
3853/2014; nothing in real time); Andorra in exact positions (Llei 12/2021
art. 4.11 excludes position warnings, as Spain's text does); Greece in
zones (loi 5209/2025 art. 24 § 11 punishes driving with equipment that
locates the speed measuring devices, "εξοπλισμό εντοπισμού"); Norway kept
in zones (the draft notified as TRIS 2025/9006/NO, which would exempt
fixed cameras, is not adopted: the stricter in doubt); Portugal, Finland
and Ireland kept in zones; explicit off lines for Liechtenstein (SVG art.
53a), Monaco, San Marino and the Vatican. The table is at version 2,
reviewed on 2026-10-09; a line names the mode a user may choose in place
of its own (`CountryRule::opt_in`, `EnforcementCountryRule.optInMode`),
`exact` for France and none elsewhere.

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
build), or a zone shorter than any zone (400 m for a zone the server
builds, 500 m at the least; 99 m for a zone the Garda publishes in
Ireland, served as it is, 100 m at its import: two points a metre apart
around a camera would mark it), never leaves the server, whatever a row
says. Both readings take the client's choice into account ("The choice of
positions in France"):
France reads `exact` only for a client that asked for it. The app applies
the table again by the country it is in, the stricter rule at once at a
border.

What the embedded boundaries read at enclaves and microstates, checked by
`enclaves_and_microstates_keep_their_country_s_rule`
(`lunaway_domain::enforcement`): Llívia (42.4637, 1.9814) reads Spain,
France within 1 km, so a zone by default and a point with France's
choice; Büsingen (47.6969, 8.6897) reads Germany and Campione d'Italia
(45.9686, 8.9711) Italy, each with Switzerland within 1 km: off; Monaco,
San Marino and the Vatican read their own codes: off; Andorra la Vella
(42.5063, 1.5218) reads Andorra: points. Baarle is split: the point given
for Baarle-Hertog (51.4383, 4.9294) reads Belgium, 500 m north of it the
Netherlands, both `exact`. A French point 300 m from Monaco (Beausoleil,
43.7430, 7.4210) is off for every client; one by the Pas de la Casa
(42.5440, 1.7440) takes France's form, Andorra allowing points.

## The choice of positions in France

A user may ask, by an explicit setting of the app ("Position exacte des
radars en France", off by default), for France's cameras as points: the
point, its kind, the speed it controls, its direction and a section's road
when the sources give them, as in a country of `exact` positions. Without
the setting, nothing changes: zones in France. No other country offers a
choice; Germany stays `off_while_driving`, Switzerland, Monaco and Morocco
`off`, the zone countries in zones.

The legal reading behind the sentence under the setting (research of
2026-10-09, `plan/research/89-radars-alertes.md`, part 3): R413-15 V of the
Code de la route applies the penalties of its I (holding, carrying, using)
to "dispositifs ou produits visant à avertir ou informer de la
localisation" of the devices that record offences, so a phone holding
France's camera positions falls under it while in France, its screen on or
off; the Interior Minister's answer to written question 124381 (JO of
2012-05-22) reads the decree the same way, and the Cour de cassation's
decision of 2016-09-06 (n° 15-86.412) rules on I only. The penalty is a
fine of up to 1 500 € (Code pénal 131-13 5°, no repeat offence provided),
six points (IV), up to three years' suspension of the licence and the
confiscation of the device (II, III). The setting thus exposes a user who
turns it on, once in France with the positions; by decision of the product
owner (2026-10-09) the app says so in one sentence under the switch, with
no dialog and no reminder, and the positions leave the device as soon as
the setting is turned off. A lawyer's written opinion before a release is
recommended by the research.

The rule is read with the user's choices (`OptIns`): France's line reads
`exact` for a user who chose it, `zones` otherwise, and every other line
reads as before. The served form at a camera is still the strictest of its
country and of every country within 1 km (`served_form`), so:

- a French camera: a zone by default, a point with the choice;
- a camera of another country within 1 km of France: a zone by default;
  with the choice, its own country's form (a point at Irun or in Llívia,
  in Belgium or Luxembourg; a point off while driving in Germany);
- a French camera within 1 km of a country that is off (Switzerland,
  Monaco): nothing, with or without the choice;
- a camera within 1 km of a zone country that offers no choice: a zone for
  everyone;
- any other camera: unchanged, the same item for every client.

The server builds both forms of a camera whose form depends on a choice
(`lunaway enforcement build`): an item for the clients without the choice
(`variant` `default`, the zone) and one for those with it (`opt_in`, the
point), each naming the choices it depends on (`opt_in_countries`); every
other camera has one item for everyone (`all`). The item for the clients
without the choice keeps its row and its id whether it serves everyone or
only them, so a camera whose form starts to depend on the choice is an
update for them and a removal for the others. The point's id comes from
the same keyed hash with another input than the zone's, so neither id is
computed from the other; the two still meet elsewhere (the point lies on
the zone's line, both are written in the same build), which hides nothing
since both forms are served to anyone who asks. Digests and retirements
count each item of a camera on its own, and the guard on a tenth of the
items holds for the items of the clients without the choice and for those
of the clients with it, each side on its own (the points of the choice are
about a tenth of all the items, and could all go under a guard on the
whole).

`Query.enforcement(exactIn)` carries the choice: the countries where the
user asked for positions (France only; a country that offers no choice is
ignored; at most 8 codes). The app sends it as a variable, never written
in the document, so the persisted document is the same for every client. A
client gets the items for everyone, the `default` items of the choices it
did not make, and the `opt_in` items of those it made; a changed item it
no longer gets comes back as a removal. The cursor names the set of
countries and of choices (`n3.`): a cursor of another set, or of the
format before the choices (`n2.`), gets the whole set again (`full`), so a
user who turns the setting on or off gets the other form of every camera
concerned at the next poll.

The server neither logs nor keeps the choice: it is a parameter of the
request, which the request span does not carry (method and path only), no
log line, metric or error message of `enforcement_query` repeats it (an
invalid `exactIn` is refused as `INVALID_INPUT` without its value), and
nothing is written to the database. A test captures every log line at
every level during requests with and without the choice and finds none
(`the_build_and_the_api_under_their_roles_serve_each_client_its_form`).

## Zone lengths

4 km on a motorway, 2 km outside built-up areas, 500 m inside them
(`FRENCH_ZONES`). The protocol of 2011-07-28 between the State and the
AFFTAC that sets them is not published; the Senate's report n° 644 of
2017-07-18 ("Sur la politique d'implantation des radars", V. Delahaye)
gives them: "de quatre kilomètres sur autoroute, deux kilomètres sur route
et 500 mètres en ville". The other zone countries take the same lengths,
which no text of theirs sets, except where a source publishes its own
zones (Ireland's Garda zones, served as published).

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

A zone a source publishes (Ireland's Garda zones, `DeviceKind::MobileZone`)
is served as it is: its line, with no engine, no share and no length of
ours, in any form but off, checked like any zone (never near a country
that is off). A zone published in pieces is served by its roads: the
longest trail through its pieces, then the longest through those left,
each of 100 m or more, with a point every 50 m at most along it (the
border checks read every fourth point); a zone of more than 64 pieces is
left out.

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
build that would retire more than a tenth of the live items, of the
clients without France's choice or of those with it, retires none and
fails, after writing the new and changed ones (an engine without its
graph places nothing);
`--allow-retire` lifts that guard when the cause is known (a country turned
off). Items are written in the order of their ids, which nothing outside
the server ties to a camera: the feed's revisions do not follow the
official lists' ids.

## Operations

- daily, with the import role: `lunaway ingest cameras --refresh` (each
  list downloaded at its own pace, `CameraList::period`: France's map,
  Luxembourg and Norway daily; France's yearly file, Poland and Brussels
  weekly; the Garda's zones monthly; the cached copy read in between), then
  `lunaway enforcement build` with `LUNAWAY_ZONE_SECRET` in its
  environment;
- weekly, after a new routing graph is active: `lunaway ingest cameras-osm`
  (the same extracts as the places), then `lunaway enforcement build --full`;
- `lunaway enforcement stats`: each list's last read and the items by kind,
  variant and country.

## The API

`Query.enforcement(since, countries, exactIn, first)`: the items of the
countries asked changed since a cursor
(`n3.<identity>.<set>.<revision>`, the set a digest of the countries and of
the choices), in the form of the user's choices (`exactIn`, "The choice of
positions in France"), the rules table with each line's `optInMode`, and
each list with its terms, its last read and the date it gives of its own
last update (`listUpdatedAt`, Catalonia's Last-Modified; the CRPA asks the
French list's source and date to be cited, and the Generalitat's licence
the date of the last update). No position is sent; a phone keeps the set
of the countries it drives in and polls every `pollIntervalSeconds` (6 h).
A cursor issued for another set of countries or choices, or of the format
before the choices (`n2.`), gets the whole set again (`full`), so a country
added comes whole. Every zone's category is `DANGER_ZONE`, whatever its
camera controls: a zone never carries the kind of its camera (French
practice: "ni leur type", the French Waze editors' wiki, read on
2026-10-09). The build writes it, the table refuses a typed zone
(migration `20261009160000`), and the API serves a zone as `DANGER_ZONE`
whatever its row says. Removals come back as ids, an item no longer allowed
where it lies, or no longer for the client's choices, among them. The
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
  (`EnforcementRules.withChoices`): each country chosen whose line is
  `ZONES` and whose `optInMode` is `EXACT` takes the points, as on the
  server; a choice never loosens anything else, so a country the table
  turns off or does not name stays off. A table without the field (an API
  older than the choice, the library's) takes `optInFallback`, which copies
  the server's only line: France, `EXACT`. These rules, never the table
  alone, decide what is kept on the device (`keptUnder`), what is alerted
  (`shownUnder`, the rule tracker) and what the maps draw.
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
  rules in force let the device keep is written. Under a choice the server
  also sends a neighbour's cameras within a kilometre of the country chosen
  as points (a Spanish camera at Irun under France's choice), which their
  own country's rule cannot tell apart: the store keeps, by country and
  across trips, the choice its cameras were served under
  (`EnforcementState.servedUnder`). Withdrawing the choice removes at once,
  offline too, every camera of the countries served under it, the
  neighbours' included (`EnforcementFeed.purge`,
  `EnforcementStore.dropRefused`), queued behind any poll in flight; those
  countries start over from their whole set at the next poll that asks
  for them (a poll asks for the countries of the route in use only), and
  until then they have no camera on the device: France, and the
  neighbours polled with it under the choice (Spain by Irun), their own
  cameras included. A page that lands after the choice changed is not
  written. A read never hands out what the choices no longer allow, even
  if the purge did not run.
- **The country.** The guidance library reads the countries at the
  vehicle's position and within 1 km of it (`countries_around`, the same
  boundaries and margin as the server). The strictest rule among them
  applies at once; a looser one only once it has held 30 s. A fix less
  precise than 100 m changes nothing, and does not end an alert either.
  The library ships on every platform, the web included (WebAssembly);
  where it does not load, no country is known and everything is off. A
  change of rule into another country, past the first fix, is a passing
  notice of the guidance (`ruleChangeNotice`, the app's rule of notices,
  `app/lib/shared/notices.dart`), on screen only: "Suisse : pas d'alerte
  radar", "France : zones de danger", "Espagne : radars". A choice changed
  during a trip, or a new table, is no border: nothing shows, near a
  border either, and a looser
  rule waits its 30 s. The data of the trip's countries is asked again as
  soon as the choice changes.
- **Germany.** Nothing anywhere, at rest as while driving. §23 Abs. 1c StVO
  binds the driver while driving, and a stop at a light or in a jam with the
  engine running counts as driving (OLG Karlsruhe, 2023); the app cannot
  tell such a stop from a parked vehicle (decision of 2026-10-09). The
  same for a device within 1 km of Germany.
- **On the route.** A zone counts where four of its points (or half of a
  shorter one) lie within 25 m of the route, either way; a camera within
  30 m, its bearing within 60 degrees of the route's; an average speed
  section with its road counts along it like a zone, but only the way it
  controls: its road, drawn from its start to its end, runs the route's
  way (the other carriageway of a motorway lies within the tolerance), and
  its bearing, when given, matches the route's. A camera 8 m or more off
  the route's line whose own limit is 40 km/h or more under the route's
  there (a sign's or the vehicle's limit, never an estimate) controls a
  road beside it, a slip road along a motorway, and does not count
  (`withoutBeside`): the tour of 2026-10-09 heard "Ralentissez, radar
  limité à 30" on the AP-7 at 120 for two cameras of a slip road 12 and
  22 m away. Cameras of one kind less than 50 m apart along the route
  (`sameCameraM`, the radius the server merges within) are one camera: one
  alert, one mark, one in the legend's count, with the lowest limit known;
  OpenStreetMap maps one camera per lane on the gantries of the A2 in the
  Netherlands, which made six alerts and "45 radars" for 7 gantries. An
  item shows only where the vehicle's rule and its own country's rule both
  allow its kind: a zone under `zones` or `exact`, a camera under `exact`
  only.
- **The alert.** One at a time, a standing notice of the guidance
  (`GuidanceNotices`, its look `EnforcementNotice`): from about 20 s ahead
  (800 m at a limit of 110 or more, 400 m from 70, 200 m below), until the
  vehicle has passed its end by
  30 m (a camera's point) or 50 m (a zone, a section), whatever the reach
  does meanwhile. A stretch is entered only at its real start, and stays
  entered while the position wavers back across it. Zones less than 300 m
  apart along the route are one stretch: one alert, one word, no end
  between. Cameras of one kind less than 50 m apart (one per lane on a
  gantry, the same camera mapped twice) are one camera: one alert, one
  word, the lowest limit any of them gives, held until the last one is
  passed. A camera's point ahead takes the banner from the stretch the
  vehicle is in. The banner shows a pictogram (the camera's badge for a
  camera, a danger sign for a zone, never a camera for a zone), the kind
  ("Radar fixe", "Radar feu rouge", "Radar de passage à niveau", "Radar
  tronçon", "Zone de danger"), the distance in large ("800 m", then "encore
  1,2 km" inside a stretch), the sign of the limit that matters (the
  camera's own when it measures speed; else the road's where the vehicle
  is, grey when it is the
  default, none when the user hid it; "moyenne" above a section's), inside
  a section the vehicle's average from its start once it has driven 200 m
  of it ("votre moyenne 104 km/h", none when the guidance started inside
  it), and the lists with their date in one run of small text (the year
  too when it is not this year's: "liste du 30 déc. 2025"). Over that
  limit plus 3 km/h for 2 s
  (a section's average, once known), the banner turns to the error colours
  and says "au-dessus de la limite". At the end of a zone or a section,
  "Fin de la zone de danger" or "Fin du contrôle de vitesse moyenne", a
  quiet passing notice (`alertExitNotice`). A screen reader hears one
  sentence (`enforcementText`) on the notice's node, told again only when
  the alert grows graver: ahead, entered, over its limit
  (`enforcementLevel`, the notice's level); a notice folded by a tap opens
  again then.
- **The words.** Each zone, camera and section once for the whole guidance,
  a new route included: "Radar fixe dans 800 mètres, limité à 90.",
  "Radar tronçon dans 800 mètres, moyenne limitée à 110.", "Zone de danger
  dans 400 mètres." ("Zone de danger." when the guidance starts inside).
  A word that waits behind another is written again when it is said: the
  distance left then, and nothing once the vehicle is past what it spoke
  of (`VoiceQueue.say`, `fresh`).
  Over its limit, once per item: "Ralentissez, radar limité à 90.", in a
  zone with the road's limit known "Ralentissez, vitesse limitée à 90.";
  nothing without a limit known. A red light or a level crossing camera
  does not measure speed: its own limit, when a list gives one, is never
  shown, said nor compared; the road's stands.
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
  limit, where on the route ("à 12 km du départ" on the preview, "dans
  800 m" from the vehicle during a guidance), "Contrôle votre sens de
  circulation" when its
  direction is known, its section's length, its lists with their date
  (the preview's callout, the guidance's sheet). The guidance's map follows
  the vehicle's rule. The preview's is read where the device is
  (`previewEnforcement`,
  `app/lib/features/navigation/application/preview_enforcement.dart`): the
  strictest rule of the countries around it, the same at rest as while
  driving, and while a guidance runs the vehicle's; no country known at the
  device (no position, no boundary library): nothing. The foot of the
  preview's panel cites each list with its date ("Zones de danger : ...",
  "Radars : ...", or both), and so do the guidance's banner and a camera's
  sheet, each by its licensor: the list's `attribution`
  (`EnforcementSource.credit`), its name only when the attribution is
  empty. The Licence Ouverte of the French list asks for the licensor
  ("a minima le nom du Concédant") and the date of the last update.
- **The limit.** `RouteSummary.speedLimits` at the vehicle's distance along
  the route; `DEFAULT` spans show in grey and never warn. Without spans,
  the sign the map gives, and only for a vehicle of 3.5 t or less with its
  trailer. Over the limit plus 3 km/h for 2 s, the speed shows on the
  error colour; a word after 5 s, every 2 min while it lasts, again after
  30 s under the limit.
- **What is said.** A zone or a camera coming is an alert of the
  guidance's voice: a short chime, then "Zone de danger dans 400 mètres",
  in the full voice and in alerts only, nothing when the voice is muted
  (the voice modes: `docs/architecture.md`, "The voice of the guidance").
  The word over the road's limit is a reminder, said in the full voice
  only and only when its setting is on.
- **Settings** (profile, guidance): the limit shown (on by default); the
  spoken reminder of the road's limit (off by default); the voice mode
  (full by default); France's positions (off by default, above).
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
