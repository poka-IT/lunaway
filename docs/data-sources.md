# Data sources

Every source, its terms as read, and how Lunaway uses it. A source enters this
table before any code reads it (`.claude/skills/data-source/SKILL.md`).

## Ingested by the server

| source | content | licence | attribution | status |
|---|---|---|---|---|
| OpenStreetMap | motorhome areas (`tourism=caravan_site`), campsites (`tourism=camp_site`), dump stations, drinking water, toilets, LPG, height limits; for routing, the height, width, length, weight and axle limits and the motorhome, caravan and trailer bans of roads and barriers (`lunaway routing prepare`); read from the daily France extract (Geofabrik or OpenStreetMap France), or region by region through Overpass | ODbL 1.0, https://www.openstreetmap.org/copyright | "© OpenStreetMap contributors" | ingested |
| DATAtourisme | `CamperVanArea`, `RVServiceArea` | Licence Ouverte 2.0 (credit the producer and the update date) | the producing territory, via DATAtourisme | planned, phase 1 (needs a free API key) |
| Atout France, classified accommodation (data.gouv.fr) | classified campsites; external key `<postcode>:<municipality>:<name>` | Licence Ouverte | "Atout France" | ingested |
| Base Adresse Nationale (Géoplateforme geocoder, `data.geopf.fr/geocodage`) | coordinates of the Atout France campsites, geocoded from their address | Licence Ouverte 2.0 | "Base Adresse Nationale" (part of the `atout-france` attribution) | used by the Atout France adapter |
| Contours administratifs (data.gouv.fr dataset `683424e996857155175d4f68`, published by data.gouv.fr) | the outlines of the French communes, 2025, simplified to 100 m (`communes-100m.geojson.gz`, about 8 MB); each place takes the name of the commune that covers it, for the search and the offline copy. Built "à partir du produit Admin Express de l'IGN" and, for the overseas collectivities, OpenStreetMap (dataset page, read 2026-10-06) | ODbL (licence `odc-odbl` in the dataset's metadata, read 2026-10-06), the same as the places database | "Contours administratifs, data.gouv.fr (IGN Admin Express, OpenStreetMap)" | ingested (`lunaway ingest municipalities`), not a `sources` row: it gives no place, only the commune of each |
| Lunaway community (`community` source) | new places and place edits by Lunaway users, as records conflated with the others | ODbL 1.0 (joins the places database); reviews and photos are CC BY 4.0, outside the database | "Lunaway contributors" | written by the conflation worker from the users' submissions |
| IGN BD TOPO, road sections (`BDTOPO_V3:troncon_de_route`, Géoplateforme WFS) | the sections with a height, total weight, width or length restriction (134 321 in France on 2026-10-06), for motorhome routing: merged into the routing graph where they match an OpenStreetMap way (the most restrictive value wins, a gap over 10 cm or 0.5 t is queued for review), and kept with their own geometry for the check of every route (`docs/deploy.md`, "Routing"). The axle load is not read: almost all of its values are the national 13 t on classified roads. Not stored as places | Licence Ouverte 2.0 (`lov2` in the data.gouv.fr dataset `bd-topo-r`; the IGN metadata record reads "Licence Ouverte / Open License (compatible ODC-BY, CC-BY 2.0)", read 2026-10-06). The licence asks for "an acknowledgement of the authorship of the 'Information': its source (at least, the name of the 'Grantor') and the date of the most recent update of the reused 'Information'" | "IGN, BD TOPO" with the edition date the WFS states (2026-06-15 on 2026-10-06: the WFS serves the edition before the downloadable one); IGN publishes no wording of its own, this one is ours | read weekly by the routing graph build (`lunaway routing fetch-ign`) |
| Fuel prices, live feed v2 (data.gouv.fr) | LPG price and stock-outs | Licence Ouverte 2.0 | "Ministère de l'Économie, prix des carburants" | planned, phase 1 |
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
| `download.geofabrik.de` (default) or `download.openstreetmap.fr` | the France extract, once a day, resumed with `If-Range` | ODbL data (the OpenStreetMap row above) |
| `overpass-api.de` | OSM by region, when the extract is not used | "users are expected to send a maximum of about 10000 requests per day and keep their download volume below about 1 GB per day" (Overpass API documentation, "Commons", read 2026-10-06); 13 queries a day is far below. The same page asks applications serving non-mappers not to use the public instances as a live backend: Lunaway queries it from the server at import time only, never from the app |
| `www.data.gouv.fr` | the Atout France dataset's metadata | Etalab platform, open API |
| `data.classement.atout-france.fr` (also accepted: `static.data.gouv.fr`, `object.files.data.gouv.fr`, `www.data.gouv.fr`) | the Atout France CSV, at the location the metadata gives; any other host is refused | Licence Ouverte |
| `data.geopf.fr` | BAN geocoding, CSV endpoint | Licence Ouverte 2.0; the CSV endpoint announces one request per second, the adapter waits 2 s between chunks |
| `object.data.gouv.fr` | the communes file, when an operator runs `lunaway ingest municipalities` (once a year, when a new year's file is published), cached under `municipalities/` | the data.gouv.fr object storage of the "Contours administratifs" dataset above |
| `data.geopf.fr` (WFS, `/wfs/ows`) | BD TOPO's restricted road sections, by the routing graph build once a week: about 27 pages of 5 000 sections (the server's cap), one at a time, a second apart, sorted by `cleabs` (the server's paging is not transaction-safe), cached gzip-compressed under `ign-bdtopo/` | Licence Ouverte 2.0 (the BD TOPO row above). The Géoplateforme's terms set a fair-use limit of "30 requêtes/s" per address for the WFS, answered with a 429 for 5 seconds beyond it (https://cartes.gouv.fr/cgu/, version of 2024-10-15, article 3.2, read 2026-10-06); a page takes 7 to 17 s to answer |

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
