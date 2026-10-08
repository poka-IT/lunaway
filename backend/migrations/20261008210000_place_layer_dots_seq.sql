-- The change feed's position the places' dots cover (`place_dots`, the next
-- migration): a publication of the places' tiles applies to the dots the
-- places written after it. Apart from `published_seq`, so that a version
-- published by a release that does not keep the dots (the worker of the
-- release before, until the deploy restarts it, or a rollback) is caught up
-- by the next publication of a release that does. The next migration sets
-- it when it fills the dots.
--
-- A migration of its own: adding the column locks `place_layer` against
-- every reader, here for an instant, where in the next migration the lock
-- would last the whole fill (and take it on top of the lock that migration
-- holds against the writers of the row, which can deadlock with one of
-- them).
SET LOCAL lock_timeout = '10s';
ALTER TABLE place_layer ADD COLUMN dots_seq bigint NOT NULL DEFAULT 0;
