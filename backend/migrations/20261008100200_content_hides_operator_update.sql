-- An operator who hides an item the reports already hid makes the hide
-- the operator's (`lunaway content hide`, run with the import role), so a
-- moderator who later keeps the item does not lift it.
GRANT UPDATE (origin) ON content_hides TO lunaway_ingest;
