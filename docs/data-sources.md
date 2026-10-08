# Data sources

Every source, its terms as read, and how Lunaway uses it. A source enters this
table before any code reads it (`.claude/skills/data-source/SKILL.md`).

## Ingested by the server

| source | content | licence | attribution | status |
|---|---|---|---|---|
| OpenStreetMap | places: motorhome areas (`tourism=caravan_site`), campsites (`tourism=camp_site`, their pitches folded into them), dump stations, car parks open to motorhomes or caravans (`motorhome=yes\|designated`, `caravan=yes\|designated`), rest and service areas (`highway=rest_area\|services`), with their services, height, length, width and weight limits (mapping table in `lunaway-ingest/src/osm.rs`); points of interest around them: shops, food vending machines, water and sanitation, fuel and energy, health, services (mapping table in `lunaway-ingest/src/poi_osm.rs`, `lunaway ingest pois`); for routing, the height, width, length, weight and axle limits and the motorhome, caravan and trailer bans of roads and barriers (`lunaway routing prepare`); read from Geofabrik's daily extracts of France and of the European countries motorhomes visit most (`osm_extract::EUROPE`, read country by country), or region by region through Overpass; each element belongs to the country its position lies in, from the boundaries the `country-boundaries` crate embeds (derived from OpenStreetMap, ODbL), which gives its time zone, its public holidays and its sync region; the routing coverage is the union of the Geofabrik extract outlines (`.poly` files, embedded as `lunaway-domain/data/routing-coverage.poly` and checked against `infra/routing/europe-extracts.txt`) | ODbL 1.0, https://www.openstreetmap.org/copyright | "© OpenStreetMap contributors" | ingested |
| DATAtourisme (ADN Tourisme, `api.datatourisme.fr/v1`) | the motorhome areas (`CamperVanArea`), service areas (`RVServiceArea`) and campsites (`CampingAndCaravanning` and its subclasses) the French tourist offices publish, 9 389 objects on 2026-10-07, as records the conflation merges (mapping table `datatourisme::CLASSES`); their descriptions and photos stay in the record's raw payload and reach the card through the content worker ("Open content" below) | Licence Ouverte 2.0: "L'usage est soumis aux termes de la Licence Ouverte d'Etalab ainsi qu'aux Conditions Générales d'Utilisation. L'utilisateur doit toujours mentionner la paternité du jeu de données (identifiée sous l'appellation « HasBeenCreatedBy » au sein de chaque jeu de données) utilisé dans le cadre de sa réutilisation et la date de dernière mise à jour du jeu de données réutilisé." (https://www.datatourisme.fr/utiliser-les-donnees/, read 2026-10-07); CGU v2.0 art. 62: "Tous les Jeux de données publiés sur l'Interface diffuseurs sont régis par la Licence Ouverte / Open Licence publiée par Etalab" | the producing office (`hasBeenCreatedBy`) and its last update (`lastUpdate`), "via DATAtourisme" | ingested weekly (`lunaway ingest datatourisme`, a free key in `LUNAWAY_DATATOURISME_KEY`) |
| Atout France, classified accommodation (data.gouv.fr) | classified campsites; external key `<postcode>:<municipality>:<name>` | Licence Ouverte | "Atout France" | ingested |
| Base Adresse Nationale (Géoplateforme geocoder, `data.geopf.fr/geocodage`) | coordinates of the Atout France campsites, geocoded from their address; for the campsites that fails on, a second pass with the address stripped of what the BAN cannot read (a "lieu-dit" marker, a road number, a post box), then the campsite's name among the Géoplateforme's points of interest (`index=poi`, IGN BD TOPO toponyms of category `camping`), then the municipality alone, the record then flagged approximate: such a record enriches the place it merges with, and makes no place of its own (195 of the 225 that would have stood alone had a campsite of a close name mapped in OSM in the same commune on 2026-10-06, `docs/conflation.md` section 3) | Licence Ouverte 2.0 (BAN and BD TOPO alike, the BD TOPO row below) | "Base Adresse Nationale, IGN BD TOPO" (part of the `atout-france` attribution) | used by the Atout France adapter |
| Contours administratifs (data.gouv.fr dataset `683424e996857155175d4f68`, published by data.gouv.fr) | the outlines of the French communes, 2025, simplified to 100 m (`communes-100m.geojson.gz`, about 8 MB); each place takes the name of the commune that covers it, for the search and the offline copy. Built "à partir du produit Admin Express de l'IGN" and, for the overseas collectivities, OpenStreetMap (dataset page, read 2026-10-06) | ODbL (licence `odc-odbl` in the dataset's metadata, read 2026-10-06), the same as the places database | "Contours administratifs, data.gouv.fr (IGN Admin Express, OpenStreetMap)" | ingested (`lunaway ingest municipalities`), not a `sources` row: it gives no place, only the commune of each |
| Lunaway community (`community` source) | new places and place edits by Lunaway users, as records conflated with the others | ODbL 1.0 (joins the places database) | "Lunaway contributors" | written by the conflation worker from the users' submissions |
| External community source (`extcom` source), shown as "Source communautaire externe" ("External community source") | a partner community platform's spots, their overnight status, services, prices, descriptions, rating summaries, reviews and photos, received as a feed (`docs/feeds.md`); the reviews and photos hang on the partner's records and are read per place, never in the change feed or the packs; the photos are downloaded on first view by the API's photo proxy and re-encoded | a written agreement with the partner, signed on 2026-10-07 as the maintainer's coordinator states; its text is kept outside the repository, and its reference is set on the server (`LUNAWAY_EXTCOM_AGREEMENT_REF`). Every record, review, rating and photo carries that reference as its licence. The agreement makes Lunaway a separate controller of the data and asks it to pass erasures on (`docs/feeds.md`, "Deletions", "Erasure of one author"). After the agreement ends, what was imported before stays stored and shown under the same mention (art. 11.4), and later feeds are refused (`docs/feeds.md`, "After the agreement ends"). Its values stay out of any public ODbL dump ("Licences of the places database", below). The partner is not named in the repository | the attribution text of the agreement, from the feed's header; the places' map tiles credit it as "Source communautaire externe", a constant (`lunaway-api/src/tiles.rs`) to change by hand if an agreement words it otherwise | ingested since 2026-10-07 (a regional test feed first), from the inbox its producer fills on the backend (`docs/deploy.md`, "The external community feed") |
| Lunaway community, reviews and photos (`community-cc-by` source) | ratings, reviews and photos by Lunaway users, each row filed under this source (`reviews.source_id`, `photos.source_id`), so `Review.sourceId`, `Photo.sourceId` and `Place.ratings.sourceId` lead to its licence in `Query.sources` | CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/), outside the places database; a CC BY grant cannot be withdrawn from what was published under it, hence a source of its own rather than a licence that could change | "Lunaway contributors", with the author's pseudonym the app shows on each | written by the API |
| IGN BD TOPO, road sections (`BDTOPO_V3:troncon_de_route`, Géoplateforme WFS) | the sections with a height, total weight, width or length restriction (134 321 in France on 2026-10-06), for motorhome routing: merged into the routing graph where they match an OpenStreetMap way (the most restrictive value wins, a gap over 10 cm or 0.5 t is queued for review), and kept with their own geometry for the check of every route (`docs/deploy.md`, "Routing"). The axle load is not read: almost all of its values are the national 13 t on classified roads. Not stored as places | Licence Ouverte 2.0 (`lov2` in the data.gouv.fr dataset `bd-topo-r`; the IGN metadata record reads "Licence Ouverte / Open License (compatible ODC-BY, CC-BY 2.0)", read 2026-10-06). The licence asks for "an acknowledgement of the authorship of the 'Information': its source (at least, the name of the 'Grantor') and the date of the most recent update of the reused 'Information'" | "IGN, BD TOPO" with the edition date the WFS states (2026-06-15 on 2026-10-06: the WFS serves the edition before the downloadable one); IGN publishes no wording of its own, this one is ours | read weekly by the routing graph build (`lunaway routing fetch-ign`) |
| Fuel prices, live feed v2 (data.gouv.fr dataset `prix-des-carburants-en-france-flux-instantane-v2-amelioree`, served by data.economie.gouv.fr) | for every fuel station of the feed, joined to the OpenStreetMap station that carries its id (`ref:FR:prix-carburants`, 84 % of them): prices and their dates, temporary and definitive shortages (LPG included; a "temporary" shortage older than 90 days reads as stopped: 346 of the 513 stations "temporarily" out of LPG on 2026-10-06 had been so for over a year), services (gas bottles, laundry, showers, cash machine), 24 h card machine, motorway. The dataset description says "Le flux de données instantané est mis à jour toutes les 10 minutes" and "22/05/2026 : la planification du moissonnage des jeux de données est réglée à 15 min" (read 2026-10-06), so the poller runs every 15 minutes | Licence Ouverte 2.0 (`lov2`, publisher "Ministères économiques et financiers", read 2026-10-06) | "Ministère de l'Économie, prix des carburants (data.economie.gouv.fr)" | ingested (`lunaway ingest fuel --refresh`), joined to the points of interest |
| La Poste, opening calendar (data.laposte.fr dataset `laposte-ouvertur`) | the opening ranges of every post office, postal agency and relay, day by day, holidays included, joined to the OpenStreetMap post office that carries its id (`ref:FR:LaPoste`, 95 % of them): the next 14 days replace the evaluation of the `opening_hours` tag | ODbL ("Open Database License (ODbL)" in the dataset's metadata, read 2026-10-06), the same licence as the places database | "La Poste, calendrier d'ouverture des bureaux de poste (data.laposte.fr)" | ingested daily (`lunaway ingest laposte --refresh`), joined to the points of interest |
| FINESS, structures (data.gouv.fr dataset `finess-structures-1`, Agence du numérique en santé) | for the health establishments the points carry a number of (`ref:FR:FINESS`, 92 % of the pharmacies), whether FINESS lists them as open (`etatObjet` `A`) or closed, with the closure date; a closed one shows as "maybe closed" (a pharmacy that changes owner may get a new number). The dataset says "les structures FINESS fermées sont également présentes dans ce jeu de données" and "Un snapshot mensuel est publié le premier de chaque mois" (read 2026-10-06); the fields are those of the schema `flux/out/data.gouv/structure/schema/schema-structures-v1.json` of github.com/ansforge/finess | Licence Ouverte 2.0 (`lov2`, read 2026-10-06) | "FINESS, Agence du numérique en santé (data.gouv.fr)" | ingested monthly (`lunaway ingest finess`), joined to the points of interest |
| SIRENE, stock of establishments (data.gouv.fr) | would flag a shop whose `ref:FR:SIRET` (53 621 points, 26 560 of them groceries, on 2026-10-06) is closed | Licence Ouverte 2.0 | "Insee, base Sirene" | not ingested yet: the monthly file weighs 2.88 GB zipped (2.22 GB as Parquet, data.gouv.fr metadata read 2026-10-06), for a signal that only sends a shop to review (`plan/research/18-backend-poi.md`) |
| Low-emission zones, charging points, Géorisques, ARCEP coverage, Météo-France | practical layers | Licence Ouverte 2.0 | per dataset | planned, phases 2 and 3 |

Merging OpenStreetMap makes the places database a derivative database under
the ODbL: it is published under the ODbL with the attribution above.

### Licences of the places database

The places database is under the ODbL, except the values whose provenance
(`Place.provenance`, per field) is the external community source
(`extcom`): they are licensed under its written agreement, which keeps the
partner's data out of the open licence unless Lunaway decides otherwise
(art. 6.4) and asks for a separate agreement before the raw data goes to
third parties outside Lunaway's normal features (art. 15.3), as the
maintainer's coordinator summarised it on 2026-10-07. Decision of the
product owner, 2026-10-07:

- the app's features carry them: map tiles, place cards, the change feed
  and the region packs (art. 6.2 and 6.3);
- a published dump of the database (an ODbL export) carries none of them:
  each place is resolved again without the withheld sources
  (`lunaway_domain::conflation::public_dump::resolve_for_public_dump`), so
  every such value is replaced by the next source's or dropped, with no
  alternative or description of theirs left, and a spot only `extcom`
  knows is left out entirely. Any export goes through that function; its
  tests pin the rule. No export exists yet: the one that is written calls
  it for every place. The places' grouping is kept as the conflation made
  it: two records of open sources joined only through an `extcom` record
  stay one place in a dump, with open values only;
- a region pack carries them and says so: its licence names the
  exception and its attribution adds the agreement's
  (`lunaway-api/src/packs.rs`, `pack_terms`).

## Hosts the importers call

The importers speak HTTPS only (redirects included), follow a redirect only
within the host first asked or to a host of this table, read at most a
bounded number of bytes from each answer, retry only on load shedding (429,
408, 500, 502, 503, 504), and never sooner than a `Retry-After`; one asking
for more than an hour stops the import.

| host | for | terms as read |
|---|---|---|
| `download.geofabrik.de` (default) or `download.openstreetmap.fr` | the extracts of France (daily) and of the 23 other European countries (weekly, in six groups from Monday to Saturday) (24 files, 27.8 GB on 2026-10-06), each resumed with `If-Range`; a run started again within 20 hours reads the files it already downloaded. Each mirror has its own place in the cache: OpenStreetMap France's France file reaches further across the borders than Geofabrik's | ODbL data (the OpenStreetMap row above) |
| `ftp5.gwdg.de`, reached only through a redirect from `download.geofabrik.de` (`lunaway_ingest::http::MIRRORS`) | the Geofabrik extracts Geofabrik sends there (Germany, 4.9 GB, on 2026-10-06), under `/pub/misc/openstreetmap/download.geofabrik.de/`: the same files, by the same `-latest` names, resumed with `If-Range` on their `Last-Modified` | the mirror server of GWDG (computing centre of Göttingen University and the Max Planck Society): "a large variety of project mirrors ... serve users from all over the world" (front page of `ftp5.gwdg.de`, read 2026-10-07), no further terms stated; the data is Geofabrik's, ODbL (the OpenStreetMap row above) |
| `overpass-api.de` | OSM by region, when the extract is not used | "users are expected to send a maximum of about 10000 requests per day and keep their download volume below about 1 GB per day" (Overpass API documentation, "Commons", read 2026-10-06); 13 queries a day is far below. The same page asks applications serving non-mappers not to use the public instances as a live backend: Lunaway queries it from the server at import time only, never from the app |
| `www.data.gouv.fr` | the Atout France dataset's metadata | Etalab platform, open API |
| `data.classement.atout-france.fr` (also accepted: `static.data.gouv.fr`, `object.files.data.gouv.fr`, `www.data.gouv.fr`) | the Atout France CSV, at the location the metadata gives; any other host is refused | Licence Ouverte |
| `data.geopf.fr` | BAN geocoding, CSV endpoint; and, for the Atout France campsites the BAN cannot place, one search of the `poi` index per campsite (`/geocodage/search?index=poi`, a few hundred a month), cached under `geopf-poi/` | Licence Ouverte 2.0; the CSV endpoint announces one request per second, the adapter waits 2 s between chunks and 1 s between two searches |
| `data.economie.gouv.fr` | the fuel price export (`exports/json` with only the fields read), every 15 minutes, asked gzip-compressed (1.9 MB instead of 11.5 MB), the last answer kept under `fuel/` | the export answers `x-ratelimit-limit: 50000` per day; 96 polls a day |
| `data.laposte.fr` | La Poste's calendar through the data-fair `lines` API, the next 15 days (`date_calendrier_gte`/`_lte`), pages of 10 000 lines following the `next` links on that host only, 1 s apart: about 29 pages and 43 MB a day, cached for the day under `laposte/` | open data-fair API of La Poste |
| `www.data.gouv.fr`, `static.data.gouv.fr` | FINESS: the dataset's metadata, then its newest monthly snapshot (`finess-structures-mensuel-AAAAMM.json.gz`, about 50 MB, 751 MB inflated, read as a stream), cached under `finess/` | Etalab platform |
| `object.data.gouv.fr` | the communes file, when an operator runs `lunaway ingest municipalities` (once a year, when a new year's file is published), cached under `municipalities/` | the data.gouv.fr object storage of the "Contours administratifs" dataset above |
| the partner's export host, when the feed is given as a URL | the external community source's feed, downloaded once into the cache (`extcom/`), at most 8 GiB, streamed to disk | the written agreement (row above) |
| the partner's photo hosts (`LUNAWAY_EXTCOM_PHOTO_HOSTS`, set on the server) | one photo the first time a device asks for it, by the API's photo proxy (`GET /external-photos/...`): HTTPS, those hosts only (redirects included), public addresses only, 10 MB at most, two downloads at once, a failed one tried again an hour later, then doubling up to a week | the written agreement (row above) |
| `data.geopf.fr` (WFS, `/wfs/ows`) | BD TOPO's restricted road sections, by the routing graph build once a week: about 27 pages of 5 000 sections (the server's cap), one at a time, a second apart, sorted by `cleabs` (the server's paging is not transaction-safe), cached gzip-compressed under `ign-bdtopo/` | Licence Ouverte 2.0 (the BD TOPO row above). The Géoplateforme's terms set a fair-use limit of "30 requêtes/s" per address for the WFS, answered with a 429 for 5 seconds beyond it (https://cartes.gouv.fr/cgu/, version of 2024-10-15, article 3.2, read 2026-10-06); a page takes 7 to 17 s to answer |

## Fuels of the price feed

The feed gives each station one column group per fuel; the adapter
(`lunaway-ingest/src/fuel.rs`, `FUELS`) maps each to the domain's
`FuelKind` and the API's `FuelKind` enum. The test
`each_column_of_the_feed_maps_to_its_fuel` (`lunaway-ingest/tests/fuel_history.rs`)
reads the recorded export near the A20 and checks that no price column is
left without a fuel.

| feed columns (`<prefix>_prix`, `_maj`, `_rupture_type`, `_rupture_debut`) | name in the shortage lists | `FuelKind` (API) | what it is |
|---|---|---|---|
| `gazole` | `Gazole` | `DIESEL` | diesel (B7) |
| `sp95` | `SP95` | `SP95` | unleaded 95 (E5) |
| `e10` | `E10` | `E10` | unleaded 95 with up to 10 % ethanol |
| `sp98` | `SP98` | `SP98` | unleaded 98 |
| `e85` | `E85` | `E85` | superethanol |
| `gplc` | `GPLc` | `LPG` | LPG for vehicles |

The feed has no AdBlue: a station's record holds 46 fields, of which these
six fuels are the only priced ones, and the 27 kinds of services the
export listed on 2026-10-06 name none (the word appears nowhere in its
11.5 MB), so the enum has no such value. OpenStreetMap's `fuel:adblue`
tag says where it is sold, without a price.

Rhythm: the feed is refreshed every 10 minutes at the source and harvested
by data.economie.gouv.fr every 15 minutes (the dataset row above); the
poller reads it every 15 minutes. A station updates its own prices when it
changes them: on 2026-10-06, 44 % of the diesel prices dated from the last
24 hours, 99 % from the last 30 days, and 9 of 9 006 from more than 90 days;
LPG prices change less often (183 of 1 513 older than 90 days). A price
older than 90 days is not offered by `fuelNearby` and `fuelAlongRoute`
(`lunaway_domain::fuel::MAX_PRICE_AGE_DAYS`).

History: each poll writes, per station and fuel, the day's lowest and
highest price (`fuel_price_days`, the day in Paris time, 30 days kept),
which `priceTrend` shows. A day the poller did not see stays absent.

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
| Rennes Métropole, `travaux_30_jours` (data.rennesmetropole.fr) | one record per traffic measure of the works of the next 30 days, drawn as lines: "Circulation interdite" and "Fermeture sens ..." as closures (both directions: the direction is named by cardinal points only), narrowing, alternating traffic, dead end and lane closure as lane restrictions; whole days, the end day included | "Licence ODbL 1.0" (dataset metadata, read 2026-10-06): share-alike, as Paris | "Rennes Métropole (data.rennesmetropole.fr)" | ingested hourly |
| Métropole Aix-Marseille-Provence, `fr-fermeture-des-tunnels-exploites-par-la-metropole` (data.ampmetropole.fr) | closures of the tunnels the metropolis runs, planned and unplanned, one line per tunnel and direction drawn in its direction of travel, with UTC date-times | "Licence Ouverte 2.0 (Etalab)" (dataset metadata), `lov2` on data.gouv.fr, read 2026-10-06 | "Métropole Aix-Marseille-Provence (data.ampmetropole.fr)" | ingested hourly |
| Département de la Mayenne, `225300011_waze_road-closures` (data.lamayenne.fr) | closed roads (`ROAD_CLOSED`) and works (`CONSTRUCTION`, as lane restrictions) in Waze's fields, lines; the dates as days, the daily hours from `timestart` and `timeend` ("7h", "19h", "24h_24") | "Licence Ouverte v2.0 (Etalab)" (dataset metadata, read 2026-10-06) | "Département de la Mayenne (data.lamayenne.fr)" | ingested hourly |
| Département des Côtes-d'Armor, `cd22arreteschantiers` (Data Fair of datarmor.cotesdarmor.fr) | works orders on departmental roads with their road and PR, lines: "Interdiction" as closures, alternating traffic as lane restrictions; whole days (the hours are free text) | "Licence Ouverte / Open Licence" (dataset metadata, no version stated, read 2026-10-06) | "Département des Côtes-d'Armor (datarmor.cotesdarmor.fr)" | ingested hourly, the orders ending today or later only (`DATEFIN_gte`) |
| Département de la Sarthe, `227200029_chantiers_routiers` (data.sarthe.fr) | works on departmental roads, lines: "Route barrée avec déviation" and "Déviation 2 sens" as closures, alternating traffic and a lane taken as lane restrictions | "Licence Ouverte v2.0 (Etalab)" (dataset metadata, read 2026-10-06) | "Département de la Sarthe (data.sarthe.fr)" | ingested hourly |
| Bordeaux Métropole, `ci_chantier` (opendata.bordeaux-metropole.fr; Bordeaux and Mérignac) | works orders and their measures: a line whose every right of way is "Circulation interdite" as a closure, any other closure, narrowing, alternating traffic or lane taken as a lane restriction (a closure of one right of way would otherwise close the whole works line); points only warn | "Licence Ouverte" (dataset metadata, version 1.0 by its URL, read 2026-10-06) | "Bordeaux Métropole (opendata.bordeaux-metropole.fr)" | ingested hourly |
| Netherlands, NDW "Planningsfeed wegwerkzaamheden en evenementen" (opendata.ndw.nu, the Dutch national access point) | planned and current road works and events of every Dutch road authority, DATEX II 3: carriageway and road closures for all vehicles (lorry-only ones apply to goods vehicles), height, width, length and weight limits, lane closures and narrow lanes, and the detour routes drawn as lines (`alternativeRoute`); lines in WGS 84, written latitude first. Read every three hours, the measures active now or starting within 14 days (the furthest a route can start) | The national access point lists the feed with `"termsOfService": {"type": "LICENSE_ACCORDING_CREATIVE_COMMONS"}`, shown as "License according to Creative Commons or similar" (https://ntm.ndw.nu/api/data-publications, read 2026-10-06). NDW's factsheet: "NDW-gegevens zijn beschikbaar als open data. Daarmee zijn de gegevens vrij beschikbaar voor hergebruik in toepassingen van derden." (NDW data is open data, freely available for reuse in third-party applications). Its copyright page: "Tenzij anders vermeld is op de inhoud van deze website de Creative Commons Zero (CC0) verklaring van toepassing", and "bij het citeren van de inhoud [mag] niet de indruk gewekt worden dat NDW zonder meer de strekking van het afgeleide werk onderschrijft" (https://www.ndw.nu/service/copyright, read 2026-10-06). Decision (the project's brief of 2026-10-06, which names NDW among the feeds usable without a contract): ingested as open data, NDW credited, with no claim of endorsement; the exact licence is asked of NDW in writing (`plan/research/27-backend-communaute-travaux2.md`) | "NDW, Nationaal Dataportaal Wegverkeer (opendata.ndw.nu)" | ingested (`road-events poll --only ndw`, every three hours); neither matched to the graph, which covers France only, nor sent to the phones (`road_event_sources.routed`) |
| Spain, DGT "Incidencias DGT DATEX II v3.7" (nap.dgt.es, the Spanish national access point) | the incidents and works the DGT publishes as active, DATEX II 3.7 (profile "DGT RTTI"): road and carriageway closures, lane closures, alternating traffic, narrow lanes, width, weight and length limits; sections from and to a point with their kilometre points, on roads named "A-4", "N-332" | The access point's dataset page names "Licencia: Creative Commons Attribution" (no version) and "Términos de Uso: https://www.dgt.es/contenido/aviso-legal/", with "Frecuencia de actualización: 1 min" (https://nap.dgt.es/dataset/incidencias-dgt-datex2-v3-7, read 2026-10-06). That notice is the dgt.es portal's: "Los derechos de propiedad intelectual de este portal de Internet, su diseño gráfico y los códigos que contiene, son titularidad de la Dirección General de Tráfico" (read 2026-10-06). Decision (the project's brief of 2026-10-06, "DGT, every minute, CC BY"): the dataset's own licence, CC BY, governs the data, the portal notice its portal; credited as CC BY asks, and the version is asked of the DGT (`plan/research/27-backend-communaute-travaux2.md`) | "DGT, Dirección General de Tráfico (nap.dgt.es)" | ingested (`road-events poll`, every pass); neither matched to the graph, which covers France only, nor sent to the phones (`road_event_sources.routed`) |
| Lunaway community (`community` source) | closed roads, works, narrow passages and low clearances the users report on the road (`reportRoadEvent`) | ODbL 1.0, as the community's other contributions to the database | "Lunaway contributors" | written by the API |

Not ingested: the toll motorways publish no open feed of their closures
(none in the access point's catalogue on 2026-10-06); Waze's data is not
open and its partner agreement forbids turn-by-turn navigation; TomTom,
HERE and Google are paid or forbid use with another map and engine
(research, part 4). The other city feeds the research listed carry no
closure field (Lille) or no data (Strasbourg, Grenoble). Read on
2026-10-06 and not ingested: Brest's temporary orders (areas, none
current), Hauts-de-Seine's works (no traffic field, dates as free text),
Versailles Grand Parc's closures and the Drôme's CIFS file (no licence
stated), La Rochelle's orders (3 closures, an address that answered an
error page in August), Bordeaux's `ci_mesure_a` (no geometry) and
`ci_evenmt_p` (three points, last changed in July). In Europe, the German
Autobahn API publishes no licence, the Länder feeds of the Mobilithek ask
for a subscription, Switzerland, Austria (EVIS), Portugal and Wallonia for
an account or a contract (research, part 2).

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
| `data.rennesmetropole.fr`, `data.ampmetropole.fr`, `data.lamayenne.fr`, `data.sarthe.fr`, `opendata.bordeaux-metropole.fr` | their Opendatasoft GeoJSON exports (Rennes 139 kB, Aix-Marseille-Provence 12 kB, Mayenne 16 kB, Sarthe 16 kB, Bordeaux 73 kB compressed on 2026-10-06), hourly | |
| `datarmor.cotesdarmor.fr` | the Data Fair lines of `cd22arreteschantiers` ending today or later, as GeoJSON, 1 000 at most, hourly | |
| `opendata.ndw.nu` | `planningsfeed_wegwerkzaamheden_en_evenementen.xml.gz` (16.5 MB, a gzip file served as is, 204 MB of XML), every three hours, conditional on its ETag, by its own unit with the memory it takes | the feed is written every 15 minutes (the access point's `MIN_15`) |
| `nap.dgt.es` | `datex2/v3/dgt/SituationPublication/datex2_v37.xml` (173 kB compressed, 6.8 MB), every pass; it sends no ETag | written every minute |

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
BD TOPO (Licence Ouverte 2.0, France only): it is built weekly on a
throwaway Hetzner server driven by the maintainer's Mac
(`infra/ops/mac-routing/`, `infra/routing/europe-build.sh`), which downloads
the dated extracts of the 25 countries of `infra/routing/europe-extracts.txt`
(the European import and Morocco) from `download.geofabrik.de`, three at a
time and each checked against its MD5, and the restricted sections from
`data.geopf.fr` as above; the Mac signs it and publishes it as the assets of
the release `routing-graph` of the public repository. The backend downloads it from
`github.com` (redirected to GitHub's asset host) and checks it against the
signed sums before serving it (`docs/deploy.md`, "Routing"). The app shows,
with every route, "© OpenStreetMap contributors", "IGN, BD TOPO" and the
date of the data (`Query.routing.graph`).

## Speed cameras

The cameras the server stores (`enforcement_devices`) and the zones and
points it builds from them (`docs/speed-cameras.md`). Research and
measurements: `plan/research/28-radars-limites.md`, part 2.

| source (`sources.id`) | content | licence | attribution | status |
|---|---|---|---|---|
| Sécurité routière, the official map's list (`securite-routiere`) | France's fixed, discriminating, urban, red light, level crossing and average speed cameras (3 664 rows on 2026-10-06, 3 206 cameras once the 458 routes of the radar cars are left out: they are mobile). One point each, no direction, no limit | No licence is written on the site or in the answer. The Code des relations entre le public et l'administration applies: L321-1 lets anyone reuse published public information, and L322-1 asks that it be "pas altérées, que leur sens ne soit pas dénaturé et que leurs sources et la date de leur dernière mise à jour soient mentionnées". Decision of the product owner, 2026-10-06: ingested under the CRPA, the source served with every answer. The list gives no date of its own last update (no `Last-Modified`, no field): the date of the last read stands for it (`EnforcementSource.fetchedAt`; `listUpdatedAt` stays null), our reading of L322-1. Turning a point into a danger zone does not alter what it says (our reading, not a lawyer's) | "Sécurité routière, radars.securite-routiere.gouv.fr" with the read date | ingested daily (`lunaway ingest cameras --list france --refresh`) |
| GITD CANARD, dane.gov.pl resource 989898 (`pl-canard`) | Poland's fixed, average speed, red light and level crossing cameras, sections with their end and length; Windows-1250 CSV, half-yearly snapshots (the latest of 2025-12-29 on 2026-10-06) | CC0 1.0 | "Główny Inspektorat Transportu Drogowego (CANARD), dane.gov.pl" | ingested (`--list poland`); a new snapshot is a new resource number, changed in `CameraList::url` |
| Ponts et Chaussées, `data.geoportail.lu/radar` (`lu-pch-radars`) | Luxembourg's fixed cameras (points) and average speed sections (lines) | CC0 1.0 | "Administration des ponts et chaussées, data.public.lu" | ingested (`--list luxembourg`) |
| Servei Català de Trànsit, `radars.txt` (`cat-sct-radars`) | Catalonia's cameras: road, kilometre point, limit, UTM 31 coordinates; a range of kilometre points is an average speed section. 17 of 247 rows of the file of 2026-09-17 carry coordinates that are no place in Catalonia and are left out | "Llicència oberta d'ús d'informació - Catalunya" (the dataset's catalogue entry, `analisi.transparenciacatalunya.cat` `re3y-fftf`, points to it as its terms), read on web.gencat.cat on 2026-10-06: it allows "la reutilització de la informació" and "la transformació de la informació per fer-ne obres derivades, per a tot el món i sense cap limitació temporal", on the conditions "Cal citar la font de la informació de la manera següent: Generalitat de Catalunya. Departament de [nom departament]. [organisme autònom, empresa pública]" and "S'ha d'informar de la darrera data d'actualització de la informació" | "Generalitat de Catalunya. Departament d'Interior i Seguretat Pública. Servei Català de Trànsit", with the file's own date (its `Last-Modified`, 2026-09-17 on 2026-10-06; `EnforcementSource.listUpdatedAt`) | ingested (`--list catalonia`); kept apart from OpenStreetMap: its compatibility with the ODbL's share-alike is not checked |
| Statens vegvesen, NVDB API Les v4, object type 162 (`no-nvdb-atk`) | Norway's fixed cameras, paged 1 000 at a time; the API asks every client to name itself in `X-Client` | NLOD 1.0 | "Inneholder data under norsk lisens for offentlige data (NLOD) tilgjengeliggjort av Statens vegvesen." | ingested (`--list norway`); kept apart from OpenStreetMap like Catalonia |
| OpenStreetMap, `highway=speed_camera` nodes and `type=enforcement` relations (`osm`) | the direction of travel (the relation's `from` member, or the node's `direction`), the limit, and the end of average speed sections; read from the same extracts as the places | ODbL 1.0 | "© OpenStreetMap contributors" | ingested weekly (`lunaway ingest cameras-osm`). In a country whose official list is national (France, Poland, Luxembourg, Norway) a node completes the official camera within 50 m and makes nothing of its own: in France 1 264 of 4 120 nodes had no official camera within 150 m, some removed long ago. Elsewhere the nodes stand on their own |

Every list's cameras take the list's country, and nothing within 1 km of
Switzerland is stored, whatever the source (`docs/speed-cameras.md`,
"Borders").

Mixing: the French zones take their direction and limit from OpenStreetMap,
so the items built from them are a database derived from OpenStreetMap,
served under the ODbL with both attributions; CC0 lists may join it. Each
item lists its sources (`EnforcementItem.sourceIds`).

Not ingested:

- Sweden, Trafikverket's API (`TrafficSafetyCamera`, CC0 according to
  data.europa.eu): it takes a key. Whether the key comes without a contract
  was not established (the data portal is a JavaScript application the
  reading tool could not read, 2026-10-06); to settle before any code.
- Spain outside Catalonia, the DGT's DATEX II list: its catalogue entry says
  CC BY and the DGT's legal notice forbids reproduction without
  authorisation; written agreement first.
- Waze (its terms forbid building a database from its content), Lufop
  (decision of the product owner, 2026-10-06; its announced CC BY-SA 4.0
  would not mix with the ODbL database) and the commercial bases (TomTom,
  HERE, SCDB, POIbase, Blitzer.de, Radarbot, Coyote): their terms forbid the
  reuse, or no open licence is known (`plan/research/28-radars-limites.md`,
  2.5).
- Reports by Lunaway users of police checks: none in any country
  (`docs/speed-cameras.md`, "Police checks").

### Hosts the camera importers call

| host | for | terms as read |
|---|---|---|
| `radars.securite-routiere.gouv.fr` | `/radars/all`, once a day: 2.1 MB, no `ETag` nor `Last-Modified`, read whole | the CRPA, row above; `robots.txt` answers 403 |
| `api.dane.gov.pl` | the CANARD resource, redirected to a file on the same host | CC0 |
| `data.geoportail.lu` | `/radar`, GeoJSON | CC0 |
| `transit.gencat.cat` | `radars.txt` | Generalitat open licence |
| `nvdbapiles.atlas.vegvesen.no` | `/vegobjekter/162`, at most 20 pages, a second apart, following the `neste` link on that host only | NLOD; the API documents 40 calls a second |

## Open content

Photos, descriptions and reviews shown on a place's card, read by the
content worker (`lunaway content refresh`, weekly) and kept apart from the
places: neither the change feed nor the offline packs carry them; the
card asks for them by place (`Place.externalPhotos`,
`Place.externalDescriptions`, `Place.externalReviews`). Every item keeps
its source, author, licence and link, and the app shows them with it.
Photos are downloaded once by the server, re-encoded from their pixels
(`lunaway-media`: no metadata of the source file survives) and served
from `api.lunaway.net/media/external/`: the app never loads a source's
URL. Only a licence that allows reuse and redistribution with attribution
is accepted (`lunaway_domain::content::accepted_licence`: CC0, public
domain, CC BY, CC BY-SA, Licence Ouverte, ODbL); a non-commercial or
no-derivatives licence is refused. Research and measurements:
`plan/research/46-contenus-ouverts.md`. Read 2026-10-07.

| source (`sources.id`) | content | licence, as read | attribution shown | status |
|---|---|---|---|---|
| Wikimedia Commons (`wikimedia-commons`) | the files a place's OpenStreetMap tags name (`wikimedia_commons` as a file or a category, `image` when it is a Commons file), the image of its Wikidata item (P18) and the first files of its Commons category, and the geotagged files taken within 80 to 250 m of it (by kind), four at most, shown as the surroundings | per file, read from its own metadata (`extmetadata.LicenseShortName`): "Wikimedia Commons only accepts free content" and "the license must meet the following conditions: Republication and distribution must be allowed. Publication of derivative work must be allowed. Commercial use of the work must be allowed" (https://commons.wikimedia.org/wiki/Commons:Licensing) | the file's author (`Artist`, as text), its licence with a link, its page | ingested weekly |
| Wikipedia (`wikipedia`) | the introduction of the article a place's OpenStreetMap `wikipedia` tag or its Wikidata item names, in up to three languages (the tag's, French, English, the country's), cut to 1 200 characters with an ellipsis | CC BY-SA 4.0: "To re-distribute text on Wikipedia in any form, provide credit to the authors either by including a) a hyperlink (where possible) or URL to the page or pages you are re-using" (https://en.wikipedia.org/wiki/Wikipedia:Copyrights) | "Wikipedia", the licence with its link, the article | ingested weekly |
| Wikidata (no row of its own) | which article and which image an item names | CC0: "All structured data (i.e. the main, Property, Lexeme, and EntitySchema namespaces) is released into the public domain under Creative Commons Zero" (https://www.wikidata.org/wiki/Wikidata:Licensing) | none required | read weekly, nothing stored |
| Panoramax (`panoramax`) | street-level pictures looking at a place (`place_position` search of the meta catalogue), a flat one whole, a 360-degree one cut to the 90 degrees facing the place; two at most, and those its OpenStreetMap `panoramax` tag names; from the OpenStreetMap France and IGN instances only | per picture (`properties.license`). OpenStreetMap France: "Les contenu est sous licence Creative Commons CC-BY-SA 4.0 pour toute diffusion des photos originales ou de photos dérivées" (https://panoramax.openstreetmap.fr/api/pages/terms-of-service/fr); IGN: "La licence de publication des photos ainsi que des métadonnées et tags sémantiques est la Licence Ouverte 2.0" (https://panoramax.ign.fr/api/pages/terms-of-service/fr) | the producer's name, the instance, the licence, the picture's page | ingested weekly |
| DATAtourisme (`datatourisme`) | the descriptions (long, else short, per language) and the photos of the objects the conflation linked to a place | Licence Ouverte 2.0 (the row above). For photos, the CGU put every published file under it unless its annotation says otherwise: "un producteur de données n'est supposé publier sur DATAtourisme que les liens vers les photos publiables en open data sous licence ouverte", and the reuser must "mentionner, en plus de la source et de la date de MAJ, le crédit photo (propriété HasCredit) à proximité immédiate du visuel et [...] respecter la date de fin de droits quand celle ci est mentionnée" (https://support.datatourisme.fr/t/2341, read 2026-10-07). A photo without a credit, with a licence of its own that is refused (11 644 of 24 377 say `By-NC-ND 4.0`), or whose rights end within 8 days is left out | the office, the update date, the photo's credit and licence, the object's page | ingested weekly, from the records |
| Mangrove Reviews (`mangrove`) | reviews of places on the map (a `geo:` subject), matched to the nearest place within the uncertainty the reviewer's app gave, or to the place they name within its radius; reviews written by a machine (`is_generated`) left out; ten per place at most, chosen by the age of their keys ("Mangrove reviews" below). Anyone can sign a review with a new key, so an operator also hides a review, every review of one key (kept as its SHA-256), a place's reviews or the whole source (`lunaway content hide`, `hide-place`, `hide-source`), and no refresh brings them back. Users report a review or a photo of any external source from the card (`reportContent` with `EXTERNAL_REVIEW` or `EXTERNAL_PHOTO`): three reports hide it until a moderator decides, and a rejection hides it for good | CC BY 4.0, or the review's own: "Currently accepted licenses are CC-BY-4.0 and CC-BY-SA-4.0. When no license is specified, CC-BY-4.0 applies. Re-users of the dataset must comply with the license specified in each individual review." (https://mangrove.reviews/terms, section 8) | the reviewer's nickname, the licence, a link to the review | ingested weekly, every review read |

Not used:

- Mapillary: its terms let a registered application download images and
  serve them, on conditions a third-party app cannot keep: "must be
  designed to provide products or services that materially supplement
  those provided via the Mapillary Services (and not to merely redistribute
  Content [...])", "you must attribute the image(s) by visibly displaying
  the Mapillary logo", and Meta may "throttle usage, revoke client_ids"
  (https://www.mapillary.com/terms, section 11, effective 2024-02-15).
  Panoramax and Commons cover the same need without them.
- OpenStreetMap `note`: "A note to other mappers regarding the feature's
  mapping [...] To inform end-users about something, use description
  instead" (https://wiki.openstreetmap.org/wiki/Key:note). The
  `description` tags already reach the place (`Place.descriptions`).
- An OpenStreetMap `image` that is not a Commons file: "there is no
  guarantee whatsoever that you can display this image. In general there
  is also no way to get info about licensing status of image"
  (https://wiki.openstreetmap.org/wiki/Key:image).
- The other Panoramax instances, until their terms are read
  (`content::panoramax::INSTANCES`).

### Mangrove reviews

A Mangrove review is signed with a key its author makes in a second, and
the date it carries is the author's: neither says whether a real person
wrote it. Lunaway ranks reviews by what it saw itself, which no author
sets:

- whether the key has a review shown on the place now;
- the key's age: `content_review_keys` records, per key (the SHA-256
  of the key as one line of PEM, the form the API serves), when a review
  it signed was first kept, on any place. A key absent from it is new,
  and so is a key one of whose reviews stands hidden by the reports, a
  moderator or the operator (`content_review_strikes`): a hide names one
  signature, and the author could sign the same text again under
  another. The strike lasts as long as the hide: a moderator who keeps
  the review gives the key its age back. A review the reports hid stays
  stored, never shown, until the moderator decides, so the moderator
  finds it even once its author signed it anew; a moderator's or the
  operator's hide is final, and the review's row goes at the next run.
  `lunaway content hide --show`, which names a review by its Lunaway id,
  works only before that run;
- when Lunaway first read the review (`content_review_sightings`).

A review that would add a key to a place is a new pair, whatever the
key's age. Each weekly run chooses the reviews of each place
(`lunaway_domain::content::reviews::pick_reviews`, caps in
`MANGROVE_CAPS`):

1. hidden reviews and hidden keys take no room (`content_hides`);
2. one review per key and place, its latest;
3. the reviews of keys shown on the place first, the oldest key first;
4. then the new pairs: keys kept before first, the oldest first, then new
   keys, each group in the order Lunaway first read the reviews; at most
   2 new pairs per place, 3 new places per key and 50 new pairs per run
   over every place, 20 of which only new keys may take;
5. ten reviews per place at most.

The review's date and the number of places a key reviews give no rank:
whoever makes the keys sets both. Ten fresh keys therefore never push the
reviews shown off a place: those reviewers keep their slots, and new
pairs fill only free ones, two per place and fifty in all per week, where
the reports and the operator's hides reach them. A key that reviews every
place on the map reaches three more of them a week, aged or not, and its
reviews wait in the order they were read, behind those read before them.
The weekly room is shared by the whole map: a thousand reviews of spam
read before a real one hold that one back about twenty weeks, unless the
reports or the operator clear them first. Keys aged on purpose take at
most thirty pairs a week, so first-time reviewers always have twenty. A
legitimate reviewer of a place that already shows ten reviews waits
until one goes, and a place gains its first reviews two a week. The keys
of the reviews already shown when the rule arrived, or stored by a
release older than it, start known, dated from the last run that fetched
them (`review_keys`). Each run prints the new keys it let in, the new
pairs it held for a later run and the strikes it recorded (`lunaway
content refresh`, "new author keys").

The key's age means something only if a review cannot borrow a key.
Mangrove's API documentation (https://docs.mangrove.reviews/, read
2026-10-07) states the signature format without saying the server checks
it, so the importer checks each review itself: the ES256 signature of
its token (`jwt`) must verify against the P-256 key its `kid` names, and
the subject, rating, text, date and metadata are read from that signed
token, never from the copy the API lays out beside it
(`content::mangrove`, skip reason `Unverified`). On 2026-10-07 the 968
reviews of the API's first page all verified; the copies differed from
the signed tokens only in layout (line breaks of `kid`, an empty image
label). A key must be an uncompressed point, so one key has one
identity. Half of those signatures had a high `s`, so both forms are
accepted: anyone can derive a second valid signature of someone else's
review, which reaches Lunaway as a new pair, under the caps, of a key
struck while the first copy stands hidden.

### Hosts the content worker calls

HTTPS only, each source on its own hosts, the User-Agent
`Lunaway/<version> (+https://lunaway.net)`, retries on load shedding only
and never sooner than a `Retry-After`; a source whose places keep failing
is stopped for the run.

| host | for | pace and terms |
|---|---|---|
| `commons.wikimedia.org`, `www.wikidata.org`, `<lang>.wikipedia.org` | the action API, with `maxlag=5` except on Wikidata, whose lag counts its query service's, which a read of items does not wait for (every request waited for minutes on 2026-10-07) | one request at a time, 300 ms apart for all of Wikimedia: "keep the concurrency of your requests to 1 at a time, and below 5 requests per second overall" (https://wikitech.wikimedia.org/wiki/Robot_policy) and 200 a minute for an identified bot (https://www.mediawiki.org/wiki/Wikimedia_APIs/Rate_limits) |
| `thumb.wikimedia.org`, `upload.wikimedia.org` | the 1 280-pixel thumbnail, a standard width ("direct requests (hotlinking) will be rejected unless they use a standard size", https://www.mediawiki.org/wiki/Common_thumbnail_sizes) | the same pace, one download at a time |
| `api.panoramax.xyz` | the search of the meta catalogue | 500 ms apart; no limit published |
| `panoramax.openstreetmap.fr`, `panoramax.ign.fr`, and `panoramax-storage-public-fast.s3.gra.perf.cloud.ovh.net` reached only through a redirect from IGN's instance (its object storage, `http::MIRRORS`) | the pictures | the same pace |
| `api.datatourisme.fr` | the catalogue, 100 objects a page, the key in `X-API-Key`, with a client that follows no redirect (the key would follow it) | one page a second; "Limite de 1000 requêtes/heure" (https://api.datatourisme.fr/v1/docs) |
| the offices' photo hosts (`content::DATATOURISME_MEDIA_HOSTS`: `*.tourinsoft.eu`, `*.tourinsoft.com`, `static.apidae-tourisme.com`, ...) | the photos | 500 ms apart; a host outside the list is left out and counted |
| `api.mangrove.reviews` | `/reviews`, 1 000 a page (3 500 pass the 5.8 MB its host serves), the latest edit of each | 2 s apart, 11 pages a week; the terms forbid "placing an undue burden on the website" |

## Addresses of the map's search

`Query.searchAll` gives, under the places, the postal addresses, streets,
towns and postcodes a geocoder finds for the text typed
(`lunaway-api/src/geocode.rs`, ranking in `lunaway-domain/src/address.rs`).
Nothing is stored: each search asks the geocoders, through the backend's
Caddy (`infra/caddy/geocoders.caddy`), and the answer goes to the app with
the source of each address, which the app shows under the list and on the
address's page. Research and measures: plan/research/58-recherche-adresses.md.

| source | content | licence | attribution | status |
|---|---|---|---|---|
| Base Adresse Nationale, through IGN's Géoplateforme geocoder (`data.geopf.fr/geocodage/search`, `index=address`, `autocomplete=1`) | France: house numbers, streets, localities ("lieux-dits"), municipalities, typos and missing accents forgiven (16 of 20 real addresses found to the number, the other four to the street or the town, plan/research/58) | Licence Ouverte 2.0: "Sauf indication contraire, tout le contenu de ce site est disponible sous la licence Open Licence 2.0" (data.gouv.fr page of the API, read 2026-10-07); the Géoplateforme's terms apply the Licence Ouverte of Etalab to every dataset whose producer sets no other (https://cartes.gouv.fr/cgu, "Droits des Fournisseurs de données", read 2026-10-07) | "Base Adresse Nationale, IGN Géoplateforme" | live, server side |
| OpenStreetMap, through Lunaway's Photon (Apache 2.0) on the geocoding server, over GraphHopper's Europe database for Photon and a Morocco import of its Africa dump (`infra/geocode/`) | every other country of Europe and Morocco; French matches are left to the BAN | ODbL 1.0 (the OpenStreetMap row above) | "© OpenStreetMap contributors" | live, server side |

| host | for | terms as read |
|---|---|---|
| `data.geopf.fr` (`/geocodage/search`) | one request per search once typing pauses, the text and the map's centre on the 0.05 degree grid, 40 a second at most for every client together, stopped for as long as a 429's `Retry-After` says | "50 requêtes par seconde depuis une même adresse IP", open access without a key (data.gouv.fr page of the API, read 2026-10-07); beyond, "une erreur HTML 429 (Too Many Requests) est envoyée en réponse à toute requête. Ce blocage intervient pour une durée de 5 secondes" (cartes.gouv.fr, "Limites d'usage des API", read 2026-10-07); the terms name commercial and non-commercial developers alike ("Développeur : Utilisateur API effectuant un développement (par exemple : site Internet, application web, application mobile) à des fins commerciales ou non", https://cartes.gouv.fr/cgu) |
| `download1.graphhopper.com` | Photon's databases, by the geocoding server once a month: the Europe database (about 32 GB) and the Africa dump (about 600 MB), each checked against its published MD5 | "This is the download service for dumps of OpenStreetMap data, preprocessed for use with the Photon geocoder. You can use these dumps to set up your own local Photon server." (its front page, read 2026-10-07); ODbL data |
| `github.com` | the Photon jar, pinned by its SHA-256 (`infra/geocode/version.sh`) | Apache 2.0 |

Not used: the public `photon.komoot.io` ("You can use the API for your
project, but please be fair - extensive usage will be throttled. We do not
guarantee for the availability", its front page, read 2026-10-07) and
Nominatim's public instance ("an absolute maximum of 1 request per second",
"Auto-complete search: This is not yet supported by Nominatim and you must
not implement such a service on the client side using the API",
https://operations.osmfoundation.org/policies/nominatim/, read 2026-10-07).

## Never ingested

Proprietary databases of spots, reviews and photos are not ingested, whoever
publishes them: their terms forbid reuse, and their reviews and photos belong
to the people who wrote and took them. Campercontact, iOverlander, WikiCamps,
Freecampsites, Searchforsites, France Passion and Camping-Car Park are among
them. A producer can still offer its data under a written licence; it then
goes through the `data-source` skill like any other source.
