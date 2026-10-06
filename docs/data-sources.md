# Data sources

Every source, its terms as read, and how Lunaway uses it. A source enters this
table before any code reads it (`.claude/skills/data-source/SKILL.md`).

## Ingested by the server

| source | content | licence | attribution | status |
|---|---|---|---|---|
| OpenStreetMap | places: motorhome areas (`tourism=caravan_site`), campsites (`tourism=camp_site`, their pitches folded into them), dump stations, car parks open to motorhomes or caravans (`motorhome=yes\|designated`, `caravan=yes\|designated`), rest and service areas (`highway=rest_area\|services`), with their services, height, length, width and weight limits (mapping table in `lunaway-ingest/src/osm.rs`); points of interest around them: shops, food vending machines, water and sanitation, fuel and energy, health, services (mapping table in `lunaway-ingest/src/poi_osm.rs`, `lunaway ingest pois`); for routing, the height, width, length, weight and axle limits and the motorhome, caravan and trailer bans of roads and barriers (`lunaway routing prepare`); read from Geofabrik's daily extracts of France and of the European countries motorhomes visit most (`osm_extract::EUROPE`, read country by country), or region by region through Overpass; each element belongs to the country its position lies in, from the boundaries the `country-boundaries` crate embeds (derived from OpenStreetMap, ODbL), which gives its time zone, its public holidays and its sync region | ODbL 1.0, https://www.openstreetmap.org/copyright | "© OpenStreetMap contributors" | ingested |
| DATAtourisme | `CamperVanArea`, `RVServiceArea` | Licence Ouverte 2.0 (credit the producer and the update date) | the producing territory, via DATAtourisme | planned, phase 1 (needs a free API key) |
| Atout France, classified accommodation (data.gouv.fr) | classified campsites; external key `<postcode>:<municipality>:<name>` | Licence Ouverte | "Atout France" | ingested |
| Base Adresse Nationale (Géoplateforme geocoder, `data.geopf.fr/geocodage`) | coordinates of the Atout France campsites, geocoded from their address; for the campsites that fails on, a second pass with the address stripped of what the BAN cannot read (a "lieu-dit" marker, a road number, a post box), then the campsite's name among the Géoplateforme's points of interest (`index=poi`, IGN BD TOPO toponyms of category `camping`), then the municipality alone, the record then flagged approximate: such a record enriches the place it merges with, and makes no place of its own (195 of the 225 that would have stood alone had a campsite of a close name mapped in OSM in the same commune on 2026-10-06, `docs/conflation.md` section 3) | Licence Ouverte 2.0 (BAN and BD TOPO alike, the BD TOPO row below) | "Base Adresse Nationale, IGN BD TOPO" (part of the `atout-france` attribution) | used by the Atout France adapter |
| Contours administratifs (data.gouv.fr dataset `683424e996857155175d4f68`, published by data.gouv.fr) | the outlines of the French communes, 2025, simplified to 100 m (`communes-100m.geojson.gz`, about 8 MB); each place takes the name of the commune that covers it, for the search and the offline copy. Built "à partir du produit Admin Express de l'IGN" and, for the overseas collectivities, OpenStreetMap (dataset page, read 2026-10-06) | ODbL (licence `odc-odbl` in the dataset's metadata, read 2026-10-06), the same as the places database | "Contours administratifs, data.gouv.fr (IGN Admin Express, OpenStreetMap)" | ingested (`lunaway ingest municipalities`), not a `sources` row: it gives no place, only the commune of each |
| Lunaway community (`community` source) | new places and place edits by Lunaway users, as records conflated with the others | ODbL 1.0 (joins the places database); reviews and photos are CC BY 4.0, outside the database | "Lunaway contributors" | written by the conflation worker from the users' submissions |
| IGN BD TOPO, road sections (`BDTOPO_V3:troncon_de_route`, Géoplateforme WFS) | the sections with a height, total weight, width or length restriction (134 321 in France on 2026-10-06), for motorhome routing: merged into the routing graph where they match an OpenStreetMap way (the most restrictive value wins, a gap over 10 cm or 0.5 t is queued for review), and kept with their own geometry for the check of every route (`docs/deploy.md`, "Routing"). The axle load is not read: almost all of its values are the national 13 t on classified roads. Not stored as places | Licence Ouverte 2.0 (`lov2` in the data.gouv.fr dataset `bd-topo-r`; the IGN metadata record reads "Licence Ouverte / Open License (compatible ODC-BY, CC-BY 2.0)", read 2026-10-06). The licence asks for "an acknowledgement of the authorship of the 'Information': its source (at least, the name of the 'Grantor') and the date of the most recent update of the reused 'Information'" | "IGN, BD TOPO" with the edition date the WFS states (2026-06-15 on 2026-10-06: the WFS serves the edition before the downloadable one); IGN publishes no wording of its own, this one is ours | read weekly by the routing graph build (`lunaway routing fetch-ign`) |
| Fuel prices, live feed v2 (data.gouv.fr dataset `prix-des-carburants-en-france-flux-instantane-v2-amelioree`, served by data.economie.gouv.fr) | for every fuel station of the feed, joined to the OpenStreetMap station that carries its id (`ref:FR:prix-carburants`, 84 % of them): prices and their dates, temporary and definitive shortages (LPG included; a "temporary" shortage older than 90 days reads as stopped: 346 of the 513 stations "temporarily" out of LPG on 2026-10-06 had been so for over a year), services (gas bottles, laundry, showers, cash machine), 24 h card machine, motorway. The dataset description says "Le flux de données instantané est mis à jour toutes les 10 minutes" and "22/05/2026 : la planification du moissonnage des jeux de données est réglée à 15 min" (read 2026-10-06), so the poller runs every 15 minutes | Licence Ouverte 2.0 (`lov2`, publisher "Ministères économiques et financiers", read 2026-10-06) | "Ministère de l'Économie, prix des carburants (data.economie.gouv.fr)" | ingested (`lunaway ingest fuel --refresh`), joined to the points of interest |
| La Poste, opening calendar (data.laposte.fr dataset `laposte-ouvertur`) | the opening ranges of every post office, postal agency and relay, day by day, holidays included, joined to the OpenStreetMap post office that carries its id (`ref:FR:LaPoste`, 95 % of them): the next 14 days replace the evaluation of the `opening_hours` tag | ODbL ("Open Database License (ODbL)" in the dataset's metadata, read 2026-10-06), the same licence as the places database | "La Poste, calendrier d'ouverture des bureaux de poste (data.laposte.fr)" | ingested daily (`lunaway ingest laposte --refresh`), joined to the points of interest |
| FINESS, structures (data.gouv.fr dataset `finess-structures-1`, Agence du numérique en santé) | for the health establishments the points carry a number of (`ref:FR:FINESS`, 92 % of the pharmacies), whether FINESS lists them as open (`etatObjet` `A`) or closed, with the closure date; a closed one shows as "maybe closed" (a pharmacy that changes owner may get a new number). The dataset says "les structures FINESS fermées sont également présentes dans ce jeu de données" and "Un snapshot mensuel est publié le premier de chaque mois" (read 2026-10-06); the fields are those of the schema `flux/out/data.gouv/structure/schema/schema-structures-v1.json` of github.com/ansforge/finess | Licence Ouverte 2.0 (`lov2`, read 2026-10-06) | "FINESS, Agence du numérique en santé (data.gouv.fr)" | ingested monthly (`lunaway ingest finess`), joined to the points of interest |
| SIRENE, stock of establishments (data.gouv.fr) | would flag a shop whose `ref:FR:SIRET` (53 621 points, 26 560 of them groceries, on 2026-10-06) is closed | Licence Ouverte 2.0 | "Insee, base Sirene" | not ingested yet: the monthly file weighs 2.88 GB zipped (2.22 GB as Parquet, data.gouv.fr metadata read 2026-10-06), for a signal that only sends a shop to review (`plan/research/18-backend-poi.md`) |
| Low-emission zones, charging points, Géorisques, ARCEP coverage, Météo-France | practical layers | Licence Ouverte 2.0 | per dataset | planned, phases 2 and 3 |

Merging OpenStreetMap makes the places database a derivative database under
the ODbL: it is published under the ODbL with the attribution above.

## Hosts the importers call

The importers speak HTTPS only (redirects included), follow a redirect only
within the host first asked or to a host of this table, read at most a
bounded number of bytes from each answer, retry only on load shedding (429,
408, 500, 502, 503, 504), and never sooner than a `Retry-After`; one asking
for more than an hour stops the import.

| host | for | terms as read |
|---|---|---|
| `download.geofabrik.de` (default) or `download.openstreetmap.fr` | the extracts of France and the European countries, once a day (24 files, 27.8 GB on 2026-10-06), each resumed with `If-Range`; a run started again within 20 hours reads the files it already downloaded. Each mirror has its own place in the cache: OpenStreetMap France's France file reaches further across the borders than Geofabrik's | ODbL data (the OpenStreetMap row above) |
| `overpass-api.de` | OSM by region, when the extract is not used | "users are expected to send a maximum of about 10000 requests per day and keep their download volume below about 1 GB per day" (Overpass API documentation, "Commons", read 2026-10-06); 13 queries a day is far below. The same page asks applications serving non-mappers not to use the public instances as a live backend: Lunaway queries it from the server at import time only, never from the app |
| `www.data.gouv.fr` | the Atout France dataset's metadata | Etalab platform, open API |
| `data.classement.atout-france.fr` (also accepted: `static.data.gouv.fr`, `object.files.data.gouv.fr`, `www.data.gouv.fr`) | the Atout France CSV, at the location the metadata gives; any other host is refused | Licence Ouverte |
| `data.geopf.fr` | BAN geocoding, CSV endpoint; and, for the Atout France campsites the BAN cannot place, one search of the `poi` index per campsite (`/geocodage/search?index=poi`, a few hundred a month), cached under `geopf-poi/` | Licence Ouverte 2.0; the CSV endpoint announces one request per second, the adapter waits 2 s between chunks and 1 s between two searches |
| `data.economie.gouv.fr` | the fuel price export (`exports/json` with only the fields read), every 15 minutes, asked gzip-compressed (1.9 MB instead of 11.5 MB), the last answer kept under `fuel/` | the export answers `x-ratelimit-limit: 50000` per day; 96 polls a day |
| `data.laposte.fr` | La Poste's calendar through the data-fair `lines` API, the next 15 days (`date_calendrier_gte`/`_lte`), pages of 10 000 lines following the `next` links on that host only, 1 s apart: about 29 pages and 43 MB a day, cached for the day under `laposte/` | open data-fair API of La Poste |
| `www.data.gouv.fr`, `static.data.gouv.fr` | FINESS: the dataset's metadata, then its newest monthly snapshot (`finess-structures-mensuel-AAAAMM.json.gz`, about 50 MB, 751 MB inflated, read as a stream), cached under `finess/` | Etalab platform |
| `object.data.gouv.fr` | the communes file, when an operator runs `lunaway ingest municipalities` (once a year, when a new year's file is published), cached under `municipalities/` | the data.gouv.fr object storage of the "Contours administratifs" dataset above |
| `data.geopf.fr` (WFS, `/wfs/ows`) | BD TOPO's restricted road sections, by the routing graph build once a week: about 27 pages of 5 000 sections (the server's cap), one at a time, a second apart, sorted by `cleabs` (the server's paging is not transaction-safe), cached gzip-compressed under `ign-bdtopo/` | Licence Ouverte 2.0 (the BD TOPO row above). The Géoplateforme's terms set a fair-use limit of "30 requêtes/s" per address for the WFS, answered with a 429 for 5 seconds beyond it (https://cartes.gouv.fr/cgu/, version of 2024-10-15, article 3.2, read 2026-10-06); a page takes 7 to 17 s to answer |

## Road events

Closures, works, lane restrictions, temporary vehicle limits and detours,
each bounded in time, read by the server only (`lunaway road-events poll`,
every three minutes, `docs/architecture.md`, "Road events"). Every event
keeps its source, its identifier and version, its record as it came, and
the time it was read; the app shows the source's attribution with it. Read
2026-10-06; the research behind the choice of feeds is
`plan/research/20-travaux-temps-reel.md`.

| source | content | licence, as read | attribution | status |
|---|---|---|---|---|
| DIR, "Évènements routiers - Réseau routier non concédé" (transport.data.gouv.fr dataset `evenements-routiers-sur-le-reseau-routier-national-non-concede`, published by the Point d'Accès National) | the situations of the national roads the State runs (not the toll motorways): closures (slip roads included), lane closures, alternating traffic, contraflows, detours, works, weight limits for lorries; DATEX II 2.2 in a SOAP envelope, an hourly aggregate `content.xml` and numbered increments "mis à jour en temps réel" (2 645 in 24 hours, research M3); each record with its version and its end marker (`lifeCycleManagement/end`) | Licence Ouverte 2.0 (`lov2` in the access point's catalogue, read 2026-10-06). The licence asks the reuser to "mentionner la paternité de l’ « Information » : sa source (au moins le nom du « Concédant ») et la date de dernière mise à jour de l’ « Information » réutilisée" (ETALAB-Licence-Ouverte-v2.0.pdf, read 2026-10-06) | "DIR, Bison Futé (transport.data.gouv.fr)" with the time the feed was read | ingested (`road-events poll`): increments every run, the aggregate hourly |
| DiaLog, "Base de données nationale de la réglementation de circulation" (DGITM; transport.data.gouv.fr and data.gouv.fr dataset `base-de-donnees-nationale-de-la-reglementation-de-circulation`) | traffic orders: temporary ones (no entry, alternating traffic, height, width, length and weight limits) as road events every 15 minutes; permanent ones with a height, width, length or weight limit as restrictions every route is checked against (`route_restrictions`, source `dialog`), weekly. DATEX II 3 with DiaLog's GeoJSON extension. Its maxima are written `lessThanOrEqualTo` and read as maxima, the evidence in `plan/research/21-backend-travaux.md`; its weights name heavy goods vehicles and only warn a motorhome | Licence Ouverte 2.0 (`lov2` on data.gouv.fr and on the access point, read 2026-10-06); the code of DiaLog is AGPL-3.0 | "DiaLog (DGITM), arrêtés de circulation" | ingested (`road-events poll`, `road-events dialog-permanent`) |
| Ville de Paris, `fermetures-voirie` (opendata.paris.fr, Direction de la Voirie et des Déplacements) | closures of the ring road, its slip roads, tunnels and riverside roads, drawn as lines, with their period | "Open Database License (ODbL)" (dataset metadata, read 2026-10-06): the road events database that merges it is shared under the ODbL, as the places database is | "Ville de Paris (opendata.paris.fr)" | ingested hourly |
| Ville de Paris, `chantiers-perturbants` | disruptive works drawn as areas: total closures (`BARRAGE_TOTAL`) and restrictions; an area cannot be placed on a road, so these only warn | "Open Database License (ODbL)" (dataset metadata, read 2026-10-06) | "Ville de Paris (opendata.paris.fr)" | ingested hourly |
| Métropole de Lyon, "Chantiers perturbants" (data.gouv.fr dataset `chantiers-perturbants-de-la-metropole-de-lyon`, WFS of data.grandlyon.com) | works drawn as areas, "Circulation interdite", "réduite", "alternée", by day or by night; only warn. Every record reads "Chantier en cours", future ones included: the dates decide | Licence Ouverte 2.0 (`lov2` on data.gouv.fr, read 2026-10-06) | "Métropole de Lyon (data.grandlyon.com)" | ingested hourly |
| Toulouse Métropole, `chantiers-en-cours` (data.toulouse-metropole.fr) | works in progress, lines and areas: "Rue barrée" as closures, alternating traffic and lanes taken as lane restrictions | "Licence Ouverte v2.0 (Etalab)" (dataset metadata, read 2026-10-06) | "Toulouse Métropole (data.toulouse-metropole.fr)" | ingested hourly |
| Département de la Charente-Maritime, "Incidents et routes fermées" (data.gouv.fr dataset `incidents-et-routes-fermees`) | closed roads in the Waze CIFS format, polylines of "lat lon" pairs; the file is named by the dataset's description and changes name at each update | Licence Ouverte 2.0 (`lov2` on data.gouv.fr, read 2026-10-06) | "Département de la Charente-Maritime (data.gouv.fr)" | ingested hourly |
| Lunaway community (`community` source) | closed roads, works, narrow passages and low clearances the users report on the road (`reportRoadEvent`) | ODbL 1.0, as the community's other contributions to the database | "Lunaway contributors" | written by the API |

Not ingested: the toll motorways publish no open feed of their closures
(none in the access point's catalogue on 2026-10-06); Waze's data is not
open and its partner agreement forbids turn-by-turn navigation; TomTom,
HERE and Google are paid or forbid use with another map and engine
(research, part 4). The other city feeds the research listed carry no
closure field (Lille) or no data (Strasbourg, Grenoble).

### Hosts the road events poller calls

HTTPS only, each feed on its own hosts (a redirect elsewhere is refused),
asked gzip-compressed and inflated within a bound, conditional on the
ETag where the feed gives one, retried on load shedding only and never
sooner than a `Retry-After`, with the User-Agent
`Lunaway/<version> (+https://lunaway.net)`. The latest payload of each
feed is kept under `road-events/` of the cache.

| host | for | pace |
|---|---|---|
| `tipi.bison-fute.gouv.fr` | the DIR's `content.xml` (4.3 MB, 200 kB compressed) once an hour, conditional on its ETag; the numbered increments (4 to 17 kB) from the next number on, a quarter of a second apart; when the next one has been missing for a quarter of an hour, up to three numbers past it | about 110 increments an hour, so a run every three minutes reads about five |
| `dialog.beta.gouv.fr` | `/api/regulations/datex.xml` with `includeTemporary=true` (7.9 MB, 0.6 MB compressed) every 15 minutes; with `includePermanent=true` (70 MB) weekly | |
| `opendata.paris.fr` | the GeoJSON exports of `fermetures-voirie` and `chantiers-perturbants`, hourly | |
| `data.grandlyon.com` | the WFS GeoJSON of `pvo_patrimoine_voirie.pvochantierperturbant`, hourly | |
| `data.toulouse-metropole.fr` | the GeoJSON export of `chantiers-en-cours`, hourly | |
| `www.data.gouv.fr`, `static.data.gouv.fr` | the description of `incidents-et-routes-fermees`, then its CIFS file, hourly | |

## The basemap

The map's background is not ingested into the database: the backend
downloads a ready-made archive once a month and serves it from its own host
(`docs/deploy.md`, "Basemap"). The app reads it from `tiles.lunaway.net` only.

| host | for | terms as read |
|---|---|---|
| `build-metadata.protomaps.dev`, `build.protomaps.com` | the list of Protomaps' daily planet builds (size, BLAKE3 hash), then one build a month, about 139 GB | the basemap is "distributed as an Open Database License Produced Work (OpenStreetMap attribution required)"; "Please note that URLs may change and hotlinking to these downloads are discouraged. Instead, you should copy the tileset to your own Cloud Storage." (https://docs.protomaps.com/basemaps/downloads, read 2026-10-06). "Tilesets are ODbL, attribute OSM"; "Web maps and native apps that use this Produced Work must visibly attribute © OpenStreetMap"; "If you distribute a modified “fork” of these basemap styles or tilesets, or provide a tiles API based on them, you must name your product or service something different from Protomaps. Free and unmodified redistributions of tiles and styles are permitted to use the name." (README of github.com/protomaps/basemaps, read 2026-10-06). The tiles are served unmodified, under our own host name |
| `codeload.github.com` (`protomaps/basemaps-assets`, one pinned commit) | the Noto Sans glyphs and the Protomaps sprites, at install only | glyphs: SIL Open Font License 1.1 (`fonts/OFL.txt`, "Copyright 2022 The Noto Project Authors"); sprites: derived from the MIT-licensed tangrams/icons (README of the repository) |

The map style must show "© OpenStreetMap" in a corner of the map. The
Protomaps styles are CC0 for their design and BSD-3-Clause for their code;
Protomaps asks for, without requiring, a credit when its styles are used.

Other Overpass instances are used only when an operator names one
(`lunaway ingest osm --overpass-url`) after reading its terms; the two
community mirrors the first adapter tried in turn are no longer defaults.

## The routing graph

The motorhome routing graph is derived from OpenStreetMap (ODbL) and IGN
BD TOPO (Licence Ouverte 2.0): it is built weekly on a GitHub-hosted runner
(`.github/workflows/routing-graph.yml`), which downloads the France extract
from `download.geofabrik.de` and the restricted sections from
`data.geopf.fr` as above, then published as the assets of the release
`routing-graph` of the public repository. The backend downloads it from
`github.com` (redirected to GitHub's asset host) and checks it against the
signed sums before serving it (`docs/deploy.md`, "Routing"). The app shows,
with every route, "© OpenStreetMap contributors", "IGN, BD TOPO" and the
date of the data (`Query.routing.graph`).

## Never ingested

Proprietary databases of spots, reviews and photos are not ingested, whoever
publishes them: their terms forbid reuse, and their reviews and photos belong
to the people who wrote and took them. Campercontact, iOverlander, WikiCamps,
Freecampsites, Searchforsites, France Passion and Camping-Car Park are among
them. A producer can still offer its data under a written licence; it then
goes through the `data-source` skill like any other source.
