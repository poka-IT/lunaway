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
- Lists are paginated with a cursor; a list that cannot grow past a small
  fixed size (a taxonomy) may be returned whole.
- Nested lists go through a DataLoader: no resolver issues one SQL query per
  parent row.
- Authorization is checked in the resolver of every mutation and of every
  field that is not public, from the request context, never trusted from an
  argument.
- Errors the client must act on carry an `extensions.code`
  (`UNAUTHENTICATED`, `RATE_LIMITED`, `INVALID_INPUT`); internal errors are
  logged and returned as a generic message.

## Evolution

Additive changes only on a released schema: a new field, a new optional
argument, a new enum value the app tolerates. Removing or renaming goes
through `@deprecated` first and waits for the app versions that read it to
age out.
