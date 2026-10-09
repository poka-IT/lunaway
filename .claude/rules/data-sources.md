---
paths:
  - "backend/crates/lunaway-ingest/**"
  - "backend/crates/lunaway-conflate/**"
  - "docs/data-sources.md"
---
# Data sources

Lunaway merges community contributions with every useful source and shows,
for every value, where it came from. The `data-source` skill walks the
addition of a source end to end.

## Ingestion happens on the server

Every source is ingested by the backend through the ingestion workers: open
data (OpenStreetMap, French public datasets, Wikidata) and, later, partner
data under a written licence. The app never contacts a source directly: it
talks to our API only. Gate: `structure_check` rule `allowed-hosts`.

A proprietary database (spots, reviews, photos) is crawled or imported only
under a written licence from its producer that covers the reviews and photos
of its contributors, kept by the maintainer outside the repository. The one
such source is `extcom`, shown with the contractual mention "Source
communautaire externe": its crawler lives in a private repository, the public
one holds only the generic importer (`docs/feeds.md`). Its values never enter
a public ODbL export (`docs/data-sources.md`). Every other value Lunaway shows
is credited to its real source.

A source is documented before any line of code: its licence or terms are read
and quoted in `docs/data-sources.md`, with the maintainer's decision when the
terms are restrictive.

## Crawlers

- Paced by a global rate limiter, bounded concurrency, retries with backoff
  that honour `Retry-After`, a circuit breaker after repeated failures.
- Resumable: the crawl state is persisted, a restart continues where it
  stopped.
- Raw payloads cached under `data/` (gitignored) in development, on the data
  volume in production.
- A neutral User-Agent naming Lunaway. No proxy rotation, no IP rotation, no
  fingerprint games: when a source refuses us, the crawler stops and reports.
  A robots.txt that refuses every robot on the host a list is read from
  (`Disallow: /`) is a refusal: the list is suspended until a written
  agreement (Catalonia's speed cameras, 2026-10-09). The scheduled download
  of a file whose address the publisher's own reuse API gives is no crawl,
  even under a `Disallow` of its file tree (data.gouv.fr's `/resources`,
  decision of 2026-10-09, the question asked to data.gouv.fr).
- Incremental refresh (sitemap or `lastmod` diffs, change detection on
  aggregates) rather than full re-crawls.

## Provenance

- Every record keeps its source, external id, fetch date and raw payload.
- Every place exposes its sources (`Place.sources`) and, per field, which
  source supplied the value (`Place.provenance`).
- Reviews, ratings, descriptions and photos carry their `sourceId`; the app
  shows a source badge on each.
- The attribution text of every open source shown on a screen appears on the
  detail screen and in the about page; the ODbL requires it for OSM-derived
  data.

## Conflation

Records from several sources that describe the same spot become one place,
with every source kept (`docs/architecture.md`, "Conflation"):

- the match score and its components are stored, so a merge can be explained;
- two records of the same source are never merged automatically;
- a human merge or split becomes a constraint every later import respects;
- each field of a place records which source supplied its value;
- the shared vectors `schema/conflation-vectors.json` pin the behaviour.
