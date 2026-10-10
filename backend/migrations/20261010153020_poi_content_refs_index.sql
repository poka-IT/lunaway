-- no-transaction
-- The live points whose OpenStreetMap tags name open content (`refs.commons`,
-- `refs.wikidata`, `refs.panoramax` of their record): the content worker
-- walks them by id (`lunaway_db::content::pois_due`, whose queries repeat
-- this predicate word for word), never the millions of others. Built
-- without blocking the writers, outside a transaction, in a migration of its
-- own (a statement CONCURRENTLY cannot share its migration).
CREATE INDEX CONCURRENTLY IF NOT EXISTS pois_content_refs_idx ON pois (id)
    WHERE deleted_at IS NULL AND NOT hidden
      AND (data -> 'refs') ?| ARRAY['commons', 'wikidata', 'panoramax'];
