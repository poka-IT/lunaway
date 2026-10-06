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
| `lunaway-ingest` | one adapter per source (OpenStreetMap places and points of interest, Atout France, the fuel price feed, La Poste, FINESS), paced HTTP client, raw payload cache |
| `lunaway-conflate` | incremental conflation into places, opening hours windows; the worker's part of the points of interest (their hours, the vending machines users add, "still there?") |
| `lunaway-api` | HTTP and GraphQL; thin resolvers over the repositories |
| `lunaway-cli` | the `lunaway` command: migrate, ingest, conflate (and its `--watch` worker), stats, moderation, accounts |
| `lunaway-auth` | device keys (ES256 over P-256), session tokens, recovery codes (argon2id), generated pseudonyms; passkeys later |
| `lunaway-media` | photo pipeline: bounded decoding, re-encoding from pixels (no metadata survives), 2048 px and 512 px WebP, thumbhash, content-addressed files |

The GraphQL schema is exported to `schema/lunaway.graphql` and is the contract
the app is generated from. Every query is bounded in depth, complexity, page
size and viewport area.

## Data model

- `sources`: one row per source, with its licence and attribution text.
- `source_records`: what a source said about a spot, normalised, with the raw
  payload and the fetch date.
- `places`: the canonical spot, typed and filterable columns (kind, services,
  activities, prices, maximum height and length, capacity, opening periods,
  overnight status), plus freshness (`last_confirmed_at`).
- `place_sources`: the link from a place to each record that describes it,
  with the match score.
- Community tables: reviews, photos, confirmations ("still open?"), reports
  (occupancy, service status), lists of favourites, accounts and their
  credentials, the moderation queue. The API writes them; it never writes a
  record or a place.
- `place_submissions`: new places and edits, kept as revisions. The
  conflation worker (`lunaway conflate --watch`, woken by the API through
  `NOTIFY`) writes each accepted one into a record of the `community` source
  and conflates it like any other.
- The community summary of a place (ratings, counts, cover photos, recent
  issues, verification) lives on `places`, recomputed by the same worker,
  so the change feed carries it.
- `municipalities`: the French communes; each place takes the name of the
  one that covers it, for the search and the offline copy.
- `changes`: a monotonic cursor the app syncs from.
- `pois`: the points of interest around the places (shops, food vending
  machines, water and sanitation, fuel and energy, health, services), one
  source each, never conflated with the places; `poi_join_records`: what
  the fuel price feed, La Poste's calendar and FINESS say of a point,
  joined by an identifier its record carries; `poi_layer`: the version of
  the map tiles; `poi_confirmations` and `poi_refresh_queue`: the
  community's "still there?" answers and the points the worker recomputes.

## Points of interest

The "around me" layer (`plan/research/05-poi-sources.md`): what a
traveller looks for near a place to stop, in six categories (groceries,
vending machines, water, fuel, health, services).

- **Sources.** OpenStreetMap, read from the same daily France extract as
  the places (`lunaway ingest pois`, about 323 000 points). Values of other
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
  zoom 6 to 12. The version in the URL moves with every change a tile
  would show, so a tile is cached for good; the API keeps recent tiles in
  memory and builds a few at a time.
- **Details and offline.** GraphQL: `poi(id)`, `nearbyPois` (the nearest
  per category around a place or a point), `searchPois`, and `pois(bbox)`
  pages for a device to keep a region offline.
- **Community.** `confirmPoi` ("still there?"; three accounts of level 1
  and up saying "gone" hide a point and send it to the moderators) and
  `addVendingMachine` (level 1, a `place_submissions` row of kind `poi`
  the worker writes as a point of the `community` source, ODbL).

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

- **Offline first**: the synced places live in a local SQLite database with an
  R*Tree index for the viewport and FTS5 for search; contributions queue
  locally and replay when the network returns; regions can be downloaded
  (places, basemap, municipality names for offline search).
- **Map**: MapLibre (`maplibre_gl` on Android, iOS and the web; `maplibre`
  through a WebView on macOS and Windows), behind one interface; the visible
  places feed a clustered GeoJSON source, never one widget per spot.
  Basemap: self-hosted Protomaps PMTiles. Linux users use the web app.
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
- Reviews and photos: CC BY 4.0.

The sources and their terms are listed in `docs/data-sources.md`.
