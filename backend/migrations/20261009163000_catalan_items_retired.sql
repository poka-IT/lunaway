-- The items built from Catalonia's suspended list go with its cameras
-- (migration 20261009161000 retired them and stopped citing the list): each
-- at a new revision, so the phones drop them at their next poll, and no item
-- served names a list the answer no longer cites. The next build serves
-- OpenStreetMap's cameras of Catalonia on their own. The writers' lock of
-- lunaway_db::enforcement::write_items: the new revisions become visible
-- together, after every earlier one.
LOCK TABLE enforcement_items IN SHARE ROW EXCLUSIVE MODE;
UPDATE enforcement_items
SET deleted_at = now(), updated_at = now(), revision = nextval('enforcement_revision_seq')
WHERE deleted_at IS NULL AND 'cat-sct-radars' = ANY (source_ids);
