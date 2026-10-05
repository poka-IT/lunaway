---
name: graphql-schema-change
description: Change the Lunaway GraphQL API end to end, from the Rust resolver to the Flutter client. Use when adding a query, a mutation, a field or an argument, when the app needs data the API does not serve, or when the schema drift test fails.
---

# Changing the GraphQL API

The contract is `schema/lunaway.graphql`, exported from the Rust code. The
rules live in `.claude/rules/graphql.md`; this is the procedure.

## Steps

1. **Domain first.** If the change carries a new concept, it lands in
   `lunaway-domain` (types, validation) with its unit tests, before any
   resolver.
2. **Resolver.** Add the field or mutation in `lunaway-api`, thin: parse,
   call the service, map. Bound it: page size, viewport area, complexity
   cost on expensive fields. Check authorization from the context for every
   mutation and private field.
3. **Test over HTTP** in `backend/crates/lunaway-api/tests/`: the query a
   client sends, the JSON it gets back, and the refusal cases (unauthorised,
   too large, invalid input).
4. **Export the contract**:
   ```bash
   cd backend && cargo run -p lunaway-api --bin export-schema
   ```
   `committed_schema_matches_the_code` turns green again.
5. **Additive or breaking?** Removing or renaming a field, an argument or an
   enum value breaks released apps: deprecate first (`#[graphql(deprecation =
   "use x")]`) and keep serving it.
6. **App side.** Write the operation in the feature's `graphql/` folder,
   regenerate (`fvm dart run build_runner build` in `app/`), use the
   generated types in the repository, never raw maps. Widget tests feed the
   repository a fake built from the same generated types.
7. `tool/check.sh` green, then commit the Rust change, the exported schema and
   the app change together.

## End state

The schema file, the server and the app agree in one commit, each side
tested, and no released field removed without a deprecation.
