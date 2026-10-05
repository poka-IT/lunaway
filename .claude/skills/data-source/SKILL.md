---
name: data-source
description: Add, update or remove a data source in Lunaway (OpenStreetMap, DATAtourisme, data.gouv.fr datasets, Wikidata, a partner feed) or change how sources are merged. Use when asked to import spots from somewhere, to add a layer (fuel prices, charging points, flood zones), or when a merge between sources looks wrong.
---

# Adding a data source

The rules live in `.claude/rules/data-sources.md`. A source is a legal
decision before it is a technical one.

## Steps

1. **Classify it.** Read its licence or terms of use and quote the clause in
   `docs/data-sources.md` with the URL and the date read. Three outcomes:
   - open with attribution (ODbL, Licence Ouverte 2.0, CC BY, CC0): ingested
     by the server;
   - proprietary: ingested only when the maintainer decides it, through a
     crawler kept in a private repository outside Lunaway that delivers a
     generic feed (`docs/feeds.md`); the source gets a generic id and display
     name, its real name never enters this repository, and the decision is
     recorded in `docs/data-sources.md`;
   - unknown: not ingested; ask the producer.
   ODbL inputs make the merged database ODbL: check the export still says so.
2. **Register it** in the `sources` table (name, licence, attribution text,
   URL) through a migration (`db-migration` skill).
3. **Write the adapter** in `lunaway-ingest`: fetch (paced, retried with
   backoff, honest User-Agent), keep the raw payload, normalise into a
   `source_record` (taxonomy codes from `lunaway-domain`, normalised name,
   coordinates, external ids). One adapter, one module, its own tests on a
   recorded payload in `tests/fixtures/`.
4. **Map the taxonomy.** Every value of the source maps to a `PlaceKind`,
   `Service` or `Activity`, or is dropped explicitly. A mapping table with a
   test that fails on an unmapped value the fixture contains.
5. **Tune the conflation**: a trust prior per field for the new source, and
   the conflation test vectors (`schema/conflation-vectors.json`) extended
   with pairs from this source: same spot, neighbours that are different
   spots, same source duplicates.
6. **Run it locally** on a bounded area, then read the result: number of new
   places, of merges into existing ones, a sample of each checked by hand on
   the map.
7. **Attribution on screen**: the source badge and its attribution text show
   on the detail screen and the about page.

## End state

A documented licence, a registered source, an adapter tested on a recorded
payload, conflation vectors covering it, and its attribution visible in the
app.
