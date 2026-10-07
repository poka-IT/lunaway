# Architecture

Lunaway is a free map of places to stop with a motorhome or a van: motorhome
areas, campsites, car parks that tolerate a night, service points, farms,
spots in nature. France first, designed for the world, French and English
first. This page describes the target architecture; the code grows into it
phase by phase.

## Overview

```
 Flutter app (Android, iOS, macOS, Windows, web)
   local SQLite (drift): places, favourites, pending contributions  <- offline first
        |  GraphQL over HTTPS (delta sync, contributions)
        v
 lunaway-api (Rust, axum + async-graphql)
        |
 PostgreSQL 18 + PostGIS  <-  lunaway-ingest workers (OpenStreetMap, French open data, ...)
        |                          |
 object storage (Garage, S3)       conflation: one place per real spot, every source kept
 static tiles (PMTiles basemap, offline packs)
```

## Backend

A Cargo workspace in `backend/`. Dependencies point inward.

| crate | role |
|---|---|
| `lunaway-domain` | taxonomy (kinds, services, activities, overnight status), validation, conflation scoring; pure, no I/O |
| `lunaway-db` | embedded migrations, sqlx repositories |
| `lunaway-ingest` | one adapter per source (OpenStreetMap places and points of interest, Atout France, DATAtourisme, the fuel price feed, La Poste, FINESS, the road event feeds, the open content of the places), paced HTTP client, raw payload cache |
| `lunaway-conflate` | incremental conflation into places, opening hours windows; the worker's part of the points of interest (their hours, the vending machines users add, "still there?") |
| `lunaway-api` | HTTP and GraphQL; thin resolvers over the repositories |
| `lunaway-cli` | the `lunaway` command: migrate, ingest, conflate (and its `--watch` worker), stats, moderation, accounts |
| `lunaway-auth` | device keys (ES256 over P-256), session tokens, recovery codes (argon2id), generated pseudonyms; passkeys later |
| `lunaway-media` | photo pipeline: bounded decoding, re-encoding from pixels (no metadata survives), 2048 px and 512 px WebP, thumbhash, content-addressed files |

The GraphQL schema is exported to `schema/lunaway.graphql` and is the contract
the app is generated from. Every query is bounded in depth, complexity, page
size and viewport area. A client may name a document by its SHA-256 once
the server knows it (Apollo's persisted queries, `docs/region-packs.md`).

## Data model

- `sources`: one row per source, with its licence and attribution text.
- `source_records`: what a source said about a spot, normalised, with the raw
  payload and the date of the read that last changed it. An import writes
  only the records whose content changed; `source_reads` keeps the date of
  each complete read of a slice of a source (a country, a region). Every
  query that serves a record's or a point's date reads it through the SQL
  function `lunaway_read_at`, which gives a live row the later of its own
  date and its slice's: the date Lunaway last read it. The points of
  interest work the same way.
- `places`: the canonical spot, typed and filterable columns (kind, services,
  activities, prices, maximum height and length, capacity, opening periods,
  overnight status), plus freshness (`last_confirmed_at`).
- `place_sources`: the link from a place to each record that describes it,
  with the match score.
- Community tables: reviews, photos, confirmations ("still open?"), reports
  (occupancy, service status), lists of favourites, accounts and their
  credentials, the moderation queue. The API writes them; it never writes a
  record or a place.
- `place_takedowns`: places taken down (a private home, a request under
  the GDPR, a court order). The import role empties the place, the places
  merged into it and their records, which keep a `taken_down_at` that
  every later import and conflation respects; the API's role then deletes
  the community's content (`docs/deploy.md`, "Taking a place down").
  The row keeps the kind of request as a code (`private-home`, `gdpr`,
  `court-order`, `other`), never a text that could name the requester.
  `takedown_cells` keeps no position: the keyed hashes
  (`LUNAWAY_TAKEDOWN_SECRET`, held by the import role only) of the H3
  cells around where the place stood (`lunaway_domain::takedown`). The
  conflation holds in `place_holds`, for a moderator, any group that would
  become a new place or move a live one into those cells; a release is
  journaled in `place_hold_releases`. Each takedown is also written to a
  journal outside the database, which `lunaway takedowns replay` applies
  again after a restore.
- `place_submissions`: new places and edits, kept as revisions. The
  conflation worker (`lunaway conflate --watch`, woken by the API through
  `NOTIFY`) writes each accepted one into a record of the `community` source
  and conflates it like any other.
- Retention: `lunaway retention`, daily with the API's role, deletes
  issue reports after 90 days, content reports and decided moderation
  entries a year after their decision, confirmations after two years
  (what they gave a place stays in `confirmation_tallies`, what they gave
  an account's level in `accounts.archived_confirmations`), and empties
  the content of a refused or withdrawn submission 30 days after the
  decision; the durations are `lunaway_db::retention`'s, and the privacy
  page states them.
- The community summary of a place (ratings, counts, cover photos, recent
  issues, verification) lives on `places`, recomputed by the same worker,
  so the change feed carries it. Every write that can change it queues the
  place in `place_refresh_queue`: a contribution, its deletion, a
  moderation decision, a deleted or banned account, and also what changes
  whose answers count (a trust level, which decides whether an account's
  confirmations and issue reports count; a new place detached from its
  author, whose own confirmations then count). The points of interest
  follow the same rule with `poi_refresh_queue`. A summary left
  unrefreshed never reaches the devices that synced before.
- The external community source (`extcom`, `docs/feeds.md`): a partner's
  places arrive as records like any source's, their licence column the
  agreement's reference; its reviews, rating summaries and photos have
  tables of their own (`external_reviews`, `external_ratings`,
  `external_photos`), hung on the record that carried them and read per
  place when its card opens, never in the change feed or a pack.
  `source_agreements` keeps who granted what and when; `source_switches`
  hides or purges a source at once (the conflation then counts its
  records as retired); `source_erasures` keeps the hashes of the authors
  erased at the partner's request. A photo is downloaded the first time a
  device asks for it, by the API's photo proxy, through the upload's
  pipeline.
- `municipalities`: the French communes; each place takes the name of the
  one that covers it, for the search and the offline copy.
- `changes`: a monotonic cursor the app syncs from, by box or by sync
  region (`places.region`: a French region, or a country elsewhere).
- `region_packs`: the first-sync pack of each sync region, an SQLite file
  the app downloads once before it follows the feed
  (`docs/region-packs.md`).
- `place_layer`: the version of the places' map tiles and the change
  feed's position it covers; `places.services_mask`, the services as the
  bits the tiles carry.
- `pois`: the points of interest around the places (shops, food vending
  machines, water and sanitation, fuel and energy, health, services), one
  source each, never conflated with the places; `poi_join_records`: what
  the fuel price feed, La Poste's calendar and FINESS say of a point,
  joined by an identifier its record carries, written only when it changed
  and dated through `lunaway_read_at` (target `joins`) like the records; `poi_layer`: the version of
  the map tiles; `poi_confirmations` and `poi_refresh_queue`: the
  community's "still there?" answers and the points the worker recomputes.

## Points of interest

The "around me" layer (`plan/research/05-poi-sources.md`): what a
traveller looks for near a place to stop, in six categories (groceries,
vending machines, water, fuel, health, services).

- **Sources.** OpenStreetMap, read from the same daily extracts as the
  places, France and the European countries one at a time
  (`lunaway ingest pois`, about 314 000 points in France). Values of other
  open sources are joined only by an identifier the OpenStreetMap element
  carries, never by distance or name: fuel prices, LPG and shortages every
  15 minutes (`ref:FR:prix-carburants`), La Poste's day-by-day opening
  calendar daily (`ref:FR:LaPoste`), FINESS closures monthly
  (`ref:FR:FINESS`). Each value is credited per field
  (`Poi.provenance`).
- **Hours.** As for places: the worker evaluates `opening_hours` (or La
  Poste's calendar) into UTC intervals over 14 days, every day; the app
  compares the time offline (`Poi.openNow` gives the same reading).
- **Map.** Vector tiles built by PostGIS (`ST_AsMVT`) at
  `GET /poi/{version}/{z}/{x}/{y}.mvt`, described by `GET /poi/tiles.json`:
  every point from zoom 13 (id, category, kind, name, hours in a compact
  form, LPG, "maybe closed"), clusters per category and grid cell from
  zoom 6 to 12. A change a tile would show marks the layer, and the worker
  publishes a new version at most every six hours: the version in the URL
  lets a tile be cached for good, and devices fetch the tiles they look at
  again at most that often; the API keeps recent tiles in memory and
  builds a few at a time.
- **Details and offline.** GraphQL: `poi(id)`, `nearbyPois` (the nearest
  per category around a place or a point), `searchPois`, and `pois(bbox)`
  pages for a device to keep a region offline. A point a client sends
  (`nearbyPois.at`, `searchPois.near`, `fuelNearby.at`) is rounded by the
  API to the 0.05 degree grid the app uses before any use, and
  `fuelAlongRoute` drops what leads out of 2 km around the ends of the
  line it is sent (`lunaway_domain::geo`); no request position is
  logged.
- **Community.** `confirmPoi` ("still there?"; three accounts of level 1
  and up saying "gone" hide a point and send it to the moderators) and
  `addVendingMachine` (level 1, a `place_submissions` row of kind `poi`
  the worker writes as a point of the `community` source, ODbL).

## Open content

Photos, descriptions and reviews published elsewhere under an open
licence, shown on a place's card (`docs/data-sources.md`, "Open
content").

- **Sources.** Wikimedia Commons (the files a place's data names, and
  those taken around it), Panoramax (street-level pictures looking at
  it), Wikipedia (its article's introduction), DATAtourisme (the tourist
  offices' texts and photos, through the records the conflation linked to
  the place) and Mangrove (open reviews, matched by their `geo:` URI).
- **Worker.** `lunaway content refresh`, weekly, with the import role:
  each source is asked about the places it has not been asked about for a
  week, least recently asked first (`content_checks`), so a stopped run
  resumes. Only what a licence lets anyone reuse and redistribute with
  attribution is kept, each item with its author, licence and link.
- **Storage.** `content_photos`, `content_descriptions`,
  `content_reviews`, kept apart from `places`: the change feed and the
  offline packs never carry them. A photo is downloaded once, re-encoded
  from its pixels (`lunaway-media`) and stored under `external/` in the
  media directory, which the API's host serves; the app never loads a
  source's own URL. A place gone (deleted, merged, taken down) loses its
  content at the next run. An operator hides an item, a review author's
  key, a source on a place or a whole source (`lunaway content hide`,
  `content_hides`); the card reads every row through the hides, so no
  refresh brings back what was hidden.
- **API.** `Place.externalPhotos`, `Place.externalDescriptions` and
  `Place.externalReviews`, read per place for the card (each costs a
  database query in the request's budget).
## Places on the map

How a place reaches the screen, by platform (`docs/deploy.md`, "Places
layer"):

- **Map, every platform.** Vector tiles of the places built by PostGIS at
  `GET /places/{version}/{z}/{x}/{y}.mvt`, described by
  `GET /places/tiles.json`: from zoom 10 every place with its id, kind,
  overnight status, services mask, free or paid, height limit (and its
  name from zoom 12); from zoom 2 to 9, dots that keep a place per pixel
  and set of those properties. The app filters them with a map expression
  on the device, with the same meaning as the `places` query's filter, so
  a change of filter costs no request. The worker publishes a new version
  at most every 15 minutes, and at once after a takedown; the version in
  the URL lets a tile be cached for good.
- **Details.** A tap on a pin reads `place(id)` (a persisted query, by its
  hash).
- **List.** `places(bbox, filter, near:)`: the places nearest to the map's
  centre first, page by page, the centre rounded by the server to 0.01
  degree; the device's own position is never sent.
- **Offline, native apps.** The regions a user keeps come as packs, then
  the change feed (`docs/region-packs.md`), into the local SQLite (drift),
  for the screens and the search without network. The web app keeps no
  copy of the places: it reads the tiles, `place(id)` and the list.

## Routing

`Query.route` asks the Valhalla engine on loopback for routes and checks
each one against every restriction we know (`lunaway-api/src/routing`).

- **Area.** The graph is built from the Geofabrik extracts of
  `infra/routing/europe-extracts.txt` (23 European extracts with the
  microstates inside them, the Canary Islands, Morocco). Their cuts
  (Geofabrik's, drawn from OpenStreetMap boundaries, ODbL) are embedded
  (`lunaway-domain/data/routing-coverage.poly`, read by
  `lunaway_domain::routing::coverage`, whose tests hold the two lists
  together): a stop outside every cut is answered `NO_ROUTE`
  (`OUTSIDE_COVERAGE`) without asking the engine. `Query.routing` gives the
  countries (`coveredCountries`) and a box around them.
- **Length.** 3 000 km at most in a straight line from stop to stop, the
  engine's `auto` limit set to match (`infra/routing/valhalla.json`, tied by a
  test): 8 of 10 trips between 2 645 and 4 166 km took 7 to 15 s on the
  production server on 2026-10-07. One alternative at most beyond 2 000 km,
  so that the engine's answer stays within 16 MB and the route sent within
  11 MB.
- **Stops.** A stop is snapped to the nearest road the vehicle may drive,
  never onto a ferry line (`search_filter.exclude_ferry`), except the
  vehicle's own position during a recalculation (it may be on board).
- **No route.** When the engine finds none, `routing::diagnose` asks it a
  few short questions, each stop against reference points on main roads at
  least 30 km away, for the real vehicle, the smallest one, and each limit
  lifted: `noRouteReasons` names the stop the vehicle cannot reach and the
  limit (height, width, length, weight, unpaved roads), with the blocking
  restriction from our data when we have it; or a stop far from any road,
  or stops no road joins. One diagnosis at a time on the server, inside the
  route's engine slot, within six seconds and the route's own deadline;
  unexplained otherwise. A route the engine answered is charged to the
  client's quota even when a later step fails.
- **Check.** Each route is checked against the restrictions and road
  events of its corridor; a recalculation or an alternative queries only
  the stretches no earlier query of the request covered, and a long
  stretch is read in two halves at once (two pool connections at most per
  route). The query takes the route as short encoded pieces and filters
  by a planar distance that only widens the corridor; the matcher then
  applies each source's tolerance.
- **Restrictions excluded ahead.** Barriers and road limits the engine
  lets routes through, found by routes between the capitals of the
  graph's countries for three classes of vehicles, are excluded from the
  first call of a trip that may meet them. Computed from public data only
  (the graph, the restriction table, the list of capitals) when the graph
  or the rows outside it change, never from a request
  (`routing::public`, `docs/deploy.md`).
- **Ferries.** Avoiding ferries is a preference of the engine; a route
  that still takes one carries a `ROUTE_USES_FERRY` notice per crossing
  (`routing::ferries`: the line's name and ports, where it is boarded and
  left).

## Road events

Closures, works, lane restrictions, temporary vehicle limits and detours,
so that a motorhome is never sent into a closed road or under a works
zone's limit (`plan/research/20-travaux-temps-reel.md`,
`plan/research/21-backend-travaux.md`).

- **Sources.** The DIR's DATEX II feed of the national roads (an hourly
  aggregate and increments a few minutes apart), DiaLog's traffic orders,
  city and département datasets, the Dutch (NDW) and Spanish (DGT)
  national feeds, and the users' reports
  (`docs/data-sources.md`, "Road events"). `lunaway road-events poll`
  reads each feed when it is due, every three minutes, resumed from its
  cursor (`road_event_sources.state`, stored in the transaction of each
  publication applied). A feed is asked at its own pace whether its last
  read failed or not, and a record the table cannot hold is refused alone,
  never its batch.
- **Storage.** `road_events`, one row per source record, bounded in time
  (validity, weekly windows, lifted periods), with the source's geometry
  and the lines of the routing graph it covers, in driving order. An event
  ends when its source says so, when a complete snapshot no longer carries
  it, past its end date, or, open-ended, when unseen for six hours; ended
  rows stay a week. A feed whose data has not been current for longer
  than its staleness (`road_event_sources.data_at` and `stale_after_s`)
  blocks no route: a read that brings nothing new does not count.
- **Placement on the graph.** Lines are matched by the routing engine on
  loopback (`lunaway_ingest::road_events::matching`): a route from the
  section's start to its end leaving in its direction, kept when it stays
  on the section's road number and length. A slip road closure is located
  on the main road by the DIR; it closes only the slip roads a route takes
  near it, never the main carriageway (`lunaway_domain::road_events::along`):
  each route step is placed at its maneuver point, and a slip road that
  runs too close to the carriageway it leaves for a ring to spare it
  warns instead.
- **Routes.** Every route is checked against the events near it at the
  time the vehicle reaches each (`Query.route`, `departAt`): a closure or a
  limit the vehicle exceeds is a blocker, computed around with 3 m rings
  on the road the route used; the rest warns with the age of its data.
- **Phones in guidance.** `Query.roadEvents(since)` hands out the changes
  of the events that can block, in every country with a feed, without the
  phone's position (only the sources on the routing graph,
  `road_event_sources.routed`, all of them since the graph covers Europe),
  only those in force or starting within 48 hours
  (`road_events.in_window`, `road_events_feed_window()`): NDW publishes
  two weeks of planned works. The poller's lifecycle pass, every three
  minutes, lets an event into the window when its start comes within it
  and gives it a new revision, so the cursor a phone holds delivers it
  then; an event outside the window keeps its revision while it changes,
  and one postponed past it comes back as a removal. Routes read every
  event, whatever the window;
  the phone checks its remaining route itself and asks for a new route
  when a blocker appears ahead (the contract is in
  `plan/research/21-backend-travaux.md`, part 5).
- **Community.** `reportRoadEvent`, in France, the Netherlands and Spain
  (`road_events::community::REPORT_AREA`: where an official feed runs
  beside the reports): one account warns the others; two
  accounts of level 1 or more at the same spot within two hours, agreeing
  on a measured figure within 0.2 m, block; a moderator is told. A
  confirmed event lives from its last confirming pair, so one account
  cannot keep it blocking or lower its figure. `clearRoadEvent`: the only
  reporter ends its event; one trusted account makes a blocker a warning,
  two end it. The API weighs the community's events again every three
  minutes (`road_events::reweigh_community`), so a banned or deleted
  account stops counting within minutes. It reads the reports through a
  view that gives a key per account and event instead of the account
  (`road_event_report_facts`); the importers' role, which parses untrusted
  payloads, reads neither that view nor any report's account, so it never
  links an account to a time and a place. What it still reads, each
  account's level and ban (the merge rules use them) and each event's
  confidence, ties an account to an event only coarsely: a change of the
  account followed by a confidence crossing a threshold at the next
  weighing, at the published position. A community event keeps, and
  the feed publishes, its position to about ten metres and no heading;
  the exact report stays with the report, for the API only. The feed
  publishes its times to the hour.

## Conflation

Several sources describe the same spot; the app shows one place with every
source credited. Four steps, incremental (only new or changed records run):

1. **Normalise** each record: taxonomy codes, a normalised name (lower case,
   no accents, generic words such as "aire de camping-car" removed),
   coordinates, phone, website, external identifiers (OSM id, Wikidata, refs).
2. **Find candidates** with PostGIS `ST_DWithin`, with a radius that depends on
   the kind: 60 m for a car park, 150 m for a motorhome area, 300 m for a
   campsite (its point may be the reception or the middle of the ground).
3. **Score** each pair, keeping every component so a decision can be
   explained:
   - distance, decaying by kind;
   - name similarity (trigrams and shared tokens);
   - kind compatibility from a matrix (a motorhome area and a car park can be
     the same spot, a campsite and a car park cannot);
   - shared identifiers (the same OSM id, Wikidata item, phone or website is a
     near-certain match);
   - same municipality.

   The score decides what happens:
   - **above 0.85**, the records are merged automatically;
   - **0.6 to 0.85**, the pair goes to a "same place?" review queue for trusted
     contributors;
   - **below 0.6**, the places stay distinct.

   Groups form by union-find. Two records of the same source never merge
   automatically: that is a duplicate to report.
4. **Resolve each field** from the best-ranked source for that field. The
   ranking combines a trust prior per source and field, freshness and
   community votes. For example, the overnight status and the state of the
   services come first from the community, a campsite's classification from
   Atout France, the geometry and height limits from OpenStreetMap.
   Conflicting values stay visible, and a notable conflict (price, a ban)
   opens a verification task.

Every place exposes its sources: name, licence, attribution, external id and
link, fetch date, match score. It also exposes, per field, which source
supplied the value and which values competed (`Place.sources`,
`Place.provenance(field)`). Identifiers are stable UUID v7. A merge leaves a
`merged_into` redirect, and a human merge or split becomes a constraint every
later import respects.

Shared test vectors (`schema/conflation-vectors.json`) pin the scoring and
the decisions; any change to the rules updates them in the same commit. The
exact algorithm, constants included, is specified in `docs/conflation.md`.

## App

`app/`, Flutter, Riverpod 3 with code generation, go_router, slang, drift.

- **Online, nothing waits for a download**: while the network answers, the
  map draws the places from the API's vector tiles (`/places/`, "Places
  layer" in `docs/deploy.md`), and the filters are MapLibre expressions on
  their properties (`placeTileFilter`, the same rule as
  `PlaceFilter.matches`), applied without a request. A tap opens the page
  at once with what the tile said (name, kind, night) while `place(id)`
  reads the rest (a persisted query; the copy is kept in `place_cache` for
  a later opening offline). The list beside the map is `places(bbox,
  filter, near)` a page at a time, nearest to the map's centre (the device's
  position is never sent); the search is `search` when the device holds no
  place.
- **Offline kept on phones and computers**: the regions' packs and their
  change feed fill a local SQLite database (R*Tree for the viewport, FTS5
  for search) in the background, a few seconds after the map's first view
  (`docs/region-packs.md`). When the network does not answer, the map, the
  list and the search read it, the map through a clustered GeoJSON source.
  Contributions queue locally and replay when the network returns.
- **The web keeps no places**: no pack, no feed; a copy of what an earlier
  version synced into the browser is dropped. Favourites, the vehicle and
  the user's contributions stay in the browser.
- **Map**: MapLibre (`maplibre_gl` on Android, iOS and the web; MapLibre GL
  JS in a WebView on macOS and Windows), behind one interface; never one
  widget per spot. The camera is read when the map rests, never at each
  frame. A change of theme turns the colours in place: on Android and iOS
  the paint properties that differ between Aube and Minuit and the
  basemap's icons (`StyleDiff`, `BasemapIcons`); in the browser and the
  WebView, MapLibre GL JS diffs the new style with the app's layers kept
  (`web/lunaway_maplibre.js`, `assets/map/lunaway_map.js`). Basemap:
  self-hosted Protomaps PMTiles. Linux users use the web app.
- **Web start**: the page loads MapLibre GL JS with itself and draws a first
  map (`web/premap.js`) from the view, theme and filters the app kept in
  `localStorage`, its places before its basemap, while the Flutter engine
  downloads; the app's map takes its camera and replaces it once it has
  drawn the same view. Pin images load when a layer first draws them. A
  service worker written for each build (`app/tool/web/service_worker.py`)
  serves a second visit from the browser's cache.
- **Layouts**: compact (bottom bar, details in a sheet over the map), medium
  (rail), expanded (map, list and details side by side).
- **Coordinates in one gesture**: every place shows its coordinates with a
  copy button (decimal degrees, latitude first, six decimals, the format map
  apps accept when pasted), and other formats on demand (DMS, `geo:` link,
  map links).

## Accounts without e-mail

1. A device key is created silently at first launch; it is an account with a
   generated pseudonym, and it signs every contribution.
2. A passkey protects the account (offered after the first contribution).
3. A paper recovery card, a QR code and a short code, is kept in the
   glovebox.
4. A computer is linked by scanning a QR code with the phone.
5. Fediverse and Bluesky accounts can be linked later.

Trust levels (from 0 to 4) unlock reviews, new places, edits and moderation.

Deleting an account (`deleteAccount`, the recovery-code page, or `lunaway
accounts delete`) writes the account's id to a journal outside the
database first (`lunaway_db::deletions`, one file per day on the data
volume, copied off-site every hour, encrypted, with the backups); after a
restore, `lunaway accounts replay-deletions` deletes again every account
the journal names, so a restored dump never brings a deleted account back
(`docs/deploy.md`, "Backups and restore"). The deletion empties the
content of the submissions never applied (an applied one is ODbL data and
stays, without author). A banned account may delete itself; the SHA-256 of
each of its device keys then stays two years in `banned_keys`, without the
account, its pseudonym or the ban's reason, so the same key cannot open a
new account (`signIn` answers `FORBIDDEN`). A ban deletes the texts of the
account's reviews at once: each stays a rating without text, which the
summary leaves out. A contribution the app may send
twice (a new place, an edit, a confirmation, an issue, a road report)
carries the outbox entry's id as an idempotency key: the same request
again returns what the first made (`lunaway_db::idempotency`, 30 days).
Anti-abuse measures:

- rate limits per account, device and network;
- proof of work on the web;
- presence checks scored on the server;
- a moderation queue.

## Hosting

- `https://lunaway.net`: the web app (Flutter web build) and the project
  pages (privacy policy, account deletion request).
- `https://api.lunaway.net`: the GraphQL API (`/graphql`), `/health`, and
  the map tiles of the points of interest (`/poi/...`).
- One Hetzner Cloud server in the EU, Debian 13, hardened (cloud firewall and
  nftables, key-only SSH, fail2ban, automatic security updates), Caddy for
  TLS, PostgreSQL + PostGIS on a separate data volume. Provisioning and
  deployment are code in `infra/`, described in `docs/deploy.md`.
- DNS on Cloudflare, records not proxied: TLS terminates on our server, so no
  third party reads the traffic. Proxying can be switched on per record if an
  attack requires it.

## Licences

- Code: AGPL-3.0-or-later.
- The places database: ODbL 1.0 (it merges OpenStreetMap).
- Reviews and photos: CC BY 4.0, under a source of their own
  (`community-cc-by`); the community's places, edits and reports stay
  under the ODbL (`community`).
- The external community source: the terms of its written agreement,
  whose reference every row carries (`docs/feeds.md`).

The sources and their terms are listed in `docs/data-sources.md`.
