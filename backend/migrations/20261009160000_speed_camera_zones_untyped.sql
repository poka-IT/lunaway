-- A danger zone never carries the kind of its camera
-- (lunaway_domain::enforcement::ZONE_CATEGORY, docs/speed-cameras.md):
-- every zone is served as `danger_zone`. The zones already built take it
-- here, each at a new revision so that the phones fetch them again, and the
-- table refuses a typed zone from now on. The writers' lock of
-- lunaway_db::enforcement::write_items: the new revisions become visible
-- together, after every earlier one.
LOCK TABLE enforcement_items IN SHARE ROW EXCLUSIVE MODE;
ALTER TABLE enforcement_items DROP CONSTRAINT enforcement_items_category_check;
ALTER TABLE enforcement_items ADD CONSTRAINT enforcement_items_category_check
    CHECK (category IN ('fixed', 'red_light', 'section_control', 'section', 'level_crossing',
                        'danger_zone'));

UPDATE enforcement_items
SET category = 'danger_zone', revision = nextval('enforcement_revision_seq'), updated_at = now()
WHERE kind = 'zone' AND category <> 'danger_zone';

ALTER TABLE enforcement_items ADD CONSTRAINT enforcement_items_zone_untyped_check
    CHECK (kind <> 'zone' OR category = 'danger_zone');
