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

Every source is ingested by the backend: open data (OpenStreetMap, French
public datasets, Wikidata) through the ingestion workers, and external
community sources through the generic feed importer (`docs/feeds.md`). The
app never contacts a source directly: it talks to our API only, and images
come from our media store. Gate: `structure_check` rule `allowed-hosts`.

An external community source is crawled by a private repository outside
Lunaway, which delivers a feed. Inside Lunaway it has a generic id and
display name (`extcom`, "Communauté externe"); its real name never appears in
this repository, the app or the API. Gate: the local `.leak-denylist`
(edit guard, pre-commit, commit-msg).

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
