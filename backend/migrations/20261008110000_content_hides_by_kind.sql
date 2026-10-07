-- A hide of one item names its kind: a review and a photo of one source
-- may carry the same id at the source (the partner's feed does not say its
-- ids differ between kinds), and an `item` hide matched both, so a report
-- of a review hid the photo of the same id too.
--
-- Every hide made so far is kept: an `item` hide becomes the hide of each
-- kind a stored row of that id has, and of both kinds when no stored row
-- has it (the item left its source and may come back), which hides
-- exactly what it hid before.

ALTER TABLE content_hides
    DROP CONSTRAINT content_hides_scope_check,
    ADD CONSTRAINT content_hides_scope_check CHECK (scope IN (
        'item', 'photo', 'review', 'author', 'place', 'source'));

INSERT INTO content_hides (source_id, scope, key, created_at, origin)
SELECT h.source_id, k.kind, h.key, h.created_at, h.origin
FROM content_hides h
CROSS JOIN LATERAL (
    SELECT 'review' AS kind
    WHERE EXISTS (SELECT 1 FROM content_reviews r
                  WHERE r.source_id = h.source_id AND r.external_id = h.key)
       OR EXISTS (SELECT 1 FROM external_reviews r
                  WHERE r.source_id = h.source_id AND r.external_id = h.key)
    UNION ALL
    SELECT 'photo'
    WHERE EXISTS (SELECT 1 FROM content_photos p
                  WHERE p.source_id = h.source_id AND p.external_id = h.key)
       OR EXISTS (SELECT 1 FROM external_photos p
                  WHERE p.source_id = h.source_id AND p.external_id = h.key)
) k
WHERE h.scope = 'item'
ON CONFLICT (source_id, scope, key) DO NOTHING;

INSERT INTO content_hides (source_id, scope, key, created_at, origin)
SELECT h.source_id, k.kind, h.key, h.created_at, h.origin
FROM content_hides h
CROSS JOIN (VALUES ('review'), ('photo')) AS k (kind)
WHERE h.scope = 'item'
  AND NOT EXISTS (SELECT 1 FROM content_reviews r
                  WHERE r.source_id = h.source_id AND r.external_id = h.key)
  AND NOT EXISTS (SELECT 1 FROM external_reviews r
                  WHERE r.source_id = h.source_id AND r.external_id = h.key)
  AND NOT EXISTS (SELECT 1 FROM content_photos p
                  WHERE p.source_id = h.source_id AND p.external_id = h.key)
  AND NOT EXISTS (SELECT 1 FROM external_photos p
                  WHERE p.source_id = h.source_id AND p.external_id = h.key)
ON CONFLICT (source_id, scope, key) DO NOTHING;

DELETE FROM content_hides WHERE scope = 'item';

ALTER TABLE content_hides
    DROP CONSTRAINT content_hides_scope_check,
    ADD CONSTRAINT content_hides_scope_check CHECK (scope IN (
        'photo', 'review', 'author', 'place', 'source'));
