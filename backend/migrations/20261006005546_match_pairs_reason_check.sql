-- The reason of a stored pair is one of lunaway_domain's `Reason` codes
-- (tested in lunaway-db, tests/schema_and_records.rs), never an empty or
-- unknown string a reviewer could not act on.

ALTER TABLE match_pairs ADD CONSTRAINT match_pairs_reason_check CHECK (reason IN (
    'score', 'shared_identifier', 'conflicting_identifier', 'incompatible_kinds',
    'same_source'));
