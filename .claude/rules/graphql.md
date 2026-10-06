---
paths:
  - "backend/crates/lunaway-api/**"
  - "schema/**"
  - "app/lib/**/graphql/**"
  - "app/lib/**/*.graphql"
---
# GraphQL

`schema/lunaway.graphql` is the contract between the backend and the app. It
is exported from the Rust code (`cargo run -p lunaway-api --bin export-schema`
in `backend/`) and the test `committed_schema_matches_the_code` fails when the
committed file is stale. The `graphql-schema-change` skill walks a change end
to end.

## Server

- Resolvers stay thin: they parse arguments, call a service, map the result.
  Logic lives in the domain or a service crate, so the GraphQL library can be
  swapped.
- Every query is bounded: depth and complexity limits in `build_schema`, a
  maximum page size on every list, a maximum area on every viewport query.
  A root field that queries the database adds `DB_FIELD_COST` to its
  complexity, whatever it returns. Before async-graphql parses a document,
  `guard.rs` refuses it by size, by its count of opening brackets anywhere
  in the text (the parser recurses per level and a stack overflow aborts the
  process) and by its number of selections with fragments expanded
  (async-graphql walks every spread without memoisation); keep those checks
  ahead of any new walk of the document.
- The endpoint takes one operation per `POST`, as `application/json` only:
  no batch, no GET, no multipart. Photos go to `POST /upload` (multipart,
  a session of level 1, 10 MB), a separate route that reads the image into
  memory within its limit and answers with the same error body. Body,
  response, concurrency, cost in flight, timeout and the per-client budget
  (a fixed cost per request plus its complexity; IPv4 or IPv6 /64, with a
  shared budget per IPv6 /48; `X-Forwarded-For` believed only behind the
  loopback proxy) are `config::Limits`, read from the environment
  (`.env.example`); the per-account and per-client quotas of actions are
  `config::Quotas`, in memory.
- Introspection stays enabled in production: the schema is public in the
  repository, and the same limits bound introspection queries.
- Lists are paginated with a cursor; a list that cannot grow past a small
  fixed size (a taxonomy) may be returned whole.
- Nested lists go through a DataLoader: no resolver issues one SQL query per
  parent row.
- Authorization is checked in the resolver of every mutation and of every
  field that is not public, from the request context (`auth.rs`: the
  bearer session, resolved once per request), never trusted from an
  argument. A public read ignores a bad token; a field that needs an
  account answers `UNAUTHENTICATED`. Trust levels and quotas are checked
  before any write.
- Errors the client must act on carry an `extensions.code`
  (`UNAUTHENTICATED`, `FORBIDDEN` with `requiredLevel` and `level`,
  `NOT_FOUND`, `RATE_LIMITED` with `retryAfterSeconds` and a
  `Retry-After` header, `INVALID_INPUT`, `RESYNC` for a sync cursor issued
  by another copy of the database: sync again from `since: null`,
  `UNAVAILABLE` when a service behind the API, the routing engine or its
  data, is down: try again later); internal
  errors are logged and returned as a generic message with `INTERNAL`. The
  codes and what the client does are listed in `lunaway-api/src/error.rs`;
  a new code goes there and here.

## Evolution

Additive changes only on a released schema: a new field, a new optional
argument, a new enum value the app tolerates. Removing or renaming goes
through `@deprecated` first and waits for the app versions that read it to
age out.
