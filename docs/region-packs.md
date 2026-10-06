# Sync regions and first-sync packs

The contract between the backend and the app for keeping places offline
region by region, and for the persisted queries. Measurements and the choice
of the format: `plan/research/23-backend-europe-packs.md`.

## Regions

A sync region is what a device downloads and keeps: one of the thirteen
regions of metropolitan France (ISO 3166-2, `FR-BRE`), or a country
elsewhere (ISO 3166-1, `ES`). The list is fixed in the code
(`lunaway_domain::region::SYNC_REGIONS`):

- a French place belongs to the region of its commune (the commune that
  covers it, else the nearest within 0.015 degree, 1.1 to 1.7 km); `FR`
  holds the few French places farther than that from every commune;
- a place elsewhere belongs to its country, by its position;
- a microstate goes with the region around it: Monaco with `FR-PAC`,
  Andorra and Gibraltar with `ES`, San Marino and the Vatican with `IT`,
  Liechtenstein with `CH`, Svalbard with `NO`, Åland with `FI`.

`Place.region` gives the region of a place. A place whose commune or
country changes moves to another region: the feed of the region it left
lists it in `left` (below).

The database stores the region (`places.region`, generated from
`lunaway_sync_region`), so a migration that changes the rule recomputes it
with a statement of its own, which must also move every changed place in
the feed:

```sql
BEGIN;
-- the writers' lock, lunaway-db's WRITER_LOCK (0x6c75_6e61_7761_7963)
SELECT pg_advisory_xact_lock(7815274093265123683);
UPDATE places
SET country_code = country_code,
    updated_seq = nextval('place_change_seq'),
    updated_at = now()
WHERE region IS DISTINCT FROM lunaway_sync_region(country_code, municipality_code);
COMMIT;
```

Without the new `updated_seq`, the departure would be recorded at the
place's old position, behind the cursors of the devices that keep the old
region, and the new region's feed would not list the place either. The
writers' lock keeps the feed's order (`.claude/rules/sqlx.md`). The comment
of migration `20261006150000`, which says an update of `country_code` to
itself suffices, predates this and stays as written (a committed migration
is never edited).

## The manifest

```graphql
{
  regions {
    code country name nameFr
    pack {
      url format bytes rawBytes sha256 version cursor places
      bounds { south west north east }
      generatedAt
    }
  }
}
```

`pack` is null while no pack of the region was built from the database the
API serves (after a restore, until the next build). `version` changes when
the pack does; a region nothing changed in keeps its pack and its version
from one build to the next.

## Downloading a pack

`url` names a static file under `https://api.lunaway.net/packs/places/`
that never changes: a new pack has a new name. It answers byte ranges, so a
download cut off resumes with `Range: bytes=<what is there>-`. The previous
pack of a region stays served until the next build, so a device that read
the manifest just before a build still finds its file. A region left
without a live place loses its pack (`pack` null) and every file of it at
the next build, previous file included: nothing of the region remains to
serve. After a place is taken down (personal data, a court order), and
once its tombstone is in the change feed (written by the worker, or under
the writers' lock with a new `updated_seq`), `lunaway packs build
--region <code> --takedown` rebuilds its region, and every region whose
pack is behind (the place may have left one), and removes every pack file
the manifest does not name; a device that reads a file the manifest no
longer names gets a 404 and reads the manifest again. A code that is not a
sync region fails the command. One build runs at a time: a takedown
started during the daily build waits for it (half an hour at most), then
removes what it wrote. A build writes its files in `.work/`, beside
`places/` and never served, and clears what a stopped build left there.

Before using the file, the device checks its size against `bytes` and its
SHA-256 against `sha256`, then decompresses it (gzip) to a temporary file
of `rawBytes` bytes.

## The file (`sqlite-gzip-1`)

An SQLite database, compressed with gzip, holding two tables.

`pack`, one row per key (`key TEXT PRIMARY KEY, value TEXT`):

| key | value |
|---|---|
| `format` | `sqlite-gzip-1` |
| `region` | the region's code |
| `cursor` | the `since` cursor that continues the feed after the pack (the manifest gives the same) |
| `places` | how many places |
| `generatedAt` | when it was built (RFC 3339) |
| `licence`, `attribution` | ODbL 1.0, and what the about page credits |

`places`, one row per live place of the region, every value as the GraphQL
API writes it for `Place` (enum values in capitals, dates in RFC 3339, lists
and objects as JSON text with the field names of the schema):

| column | GraphQL field |
|---|---|
| `id`, `name`, `kind`, `lat`, `lon`, `overnight` | same |
| `services`, `activities` | JSON arrays of enum values |
| `description` | same |
| `street`, `postcode`, `city`, `country_code` | `address { street postcode city countryCode }` |
| `municipality`, `region` | same |
| `price_parking_eur`, `price_services_eur`, `max_height_m`, `max_length_m`, `max_width_m`, `max_weight_t`, `capacity`, `stars` | same |
| `opening_hours`, `opening_hours_parsed` (0 or 1) | same |
| `opening_intervals` (JSON `[{start, end}]`), `opening_intervals_until` | same |
| `website`, `phone`, `last_confirmed_at`, `updated_at` | same |
| `sources`, `provenance`, `descriptions`, `ratings`, `external_links` | the JSON of the same fields, with the selection of the app's `PlaceFields` fragment |
| `verification`, `review_count`, `photo_count` | `verification`, `reviewCount`, `photoCount` |
| `cover_photos`, `reported_issues` | JSON of `coverPhotos`, `reportedIssues` |

The selection is `lunaway_api::packs::PLACE_SELECTION`; a field the app
adds to its offline copy is added there, with a new format version.

## Importing it

The fastest import measured copies the attached pack into the cache in one
statement (0.29 to 0.36 s for the 18 391 French places, against 1.0 to 1.5 s
to decode the same places from JSON):

```sql
ATTACH DATABASE '<the decompressed file>' AS pack;
-- the app's own mappings, from its Dart enums
CREATE TEMP TABLE kind_family (wire TEXT PRIMARY KEY, family INTEGER);
CREATE TEMP TABLE service_bit (wire TEXT PRIMARY KEY, bit INTEGER);
INSERT INTO places (id, name, kind, family, lat, lon, services, ..., sources_json, ...)
SELECT p.id, p.name, p.kind, coalesce(k.family, 3), p.lat, p.lon,
       (SELECT coalesce(sum(b.bit), 0) FROM json_each(p.services) j
          JOIN temp.service_bit b ON b.wire = j.value),
       ..., p.sources, ...
FROM pack.places p LEFT JOIN temp.kind_family k ON k.wire = p.kind
WHERE true
ON CONFLICT (id) DO UPDATE SET ...;
DETACH DATABASE pack;
```

The measured version of this statement, mapping for mapping, is in the
report above. Importing a pack is a full sync of its region: the places of
the region the pack does not hold are gone.

The web app's SQLite (WebAssembly) can attach a file only once it is in its
virtual file system; until it does, the web app syncs the region with
`changes(region:)` from `since: null`.

## After the pack

```graphql
query($region: String, $since: String) {
  changes(region: $region, since: $since) { places { ...PlaceFields } deleted left cursor hasMore }
}
```

with `since` the pack's cursor, then each page's cursor. A place changed or
deleted after the pack was built comes in the first pages. `left` lists
the places that moved to another region: a device drops them unless it
keeps the region they moved to (their `region` there tells which). `RESYNC` means
the cursor belongs to another copy of the database: import the region's
current pack again (or sync from `since: null`). `changes` takes either
`bbox` or `region`.

## Persisted queries

The API follows Apollo's convention (APQ). The client sends the
lowercase hexadecimal SHA-256 of its document instead of the document:

```json
{"operationName": "Changes", "variables": {...},
 "extensions": {"persistedQuery": {"version": 1, "sha256Hash": "<sha256>"}}}
```

- a known hash runs the document it names;
- an unknown hash answers HTTP 200 with the error code
  `PERSISTED_QUERY_NOT_FOUND` (message `PersistedQueryNotFound`): the client
  sends the same request with `query` added, which runs and makes the hash
  known;
- a `query` whose SHA-256 is not the hash is refused (`INVALID_INPUT`);
- a document is kept only once it ran without an error; the server keeps
  512 at most, the least recently used going first, takes 60 new ones a
  minute at most and 20 of them from one address (an IPv6 /48), and
  forgets them on a restart, so a client handles
  `PERSISTED_QUERY_NOT_FOUND` at any time, and a document it sent may not
  be kept (the next request with the hash alone gets the same answer);
- a request without a hash is served as before.

The sync request of the app weighs 1 280 bytes with its document and 298
with the hash.
