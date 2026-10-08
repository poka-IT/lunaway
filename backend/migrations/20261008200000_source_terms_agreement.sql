-- The terms a source is shown with. The reference of a written agreement
-- (the external community source's) is the legal key of what its feeds
-- delivered: every record, review and photo keeps it as its licence, and a
-- regional pack names it in its own licence. It means nothing to a reader,
-- and a place's card showed it as the source's licence
-- (plan/research/71-audit-ux-publication.md, M8): the licence shown is now
-- the source's own label, "Written agreement", and the reference moves to
-- a column of its own, added at the end as CREATE OR REPLACE VIEW
-- requires. The grants of the view stay as they were.
CREATE OR REPLACE VIEW source_terms AS
SELECT s.id, s.name,
       s.licence,
       coalesce(a.licence_url, s.licence_url) AS licence_url,
       coalesce(a.attribution, s.attribution) AS attribution,
       s.url,
       w.hidden_at,
       a.reference AS agreement
FROM sources s
LEFT JOIN LATERAL (
    SELECT reference, licence_url, attribution FROM source_agreements g
    WHERE g.source_id = s.id
    ORDER BY g.last_seen_at DESC, g.reference
    LIMIT 1
) a ON true
LEFT JOIN source_switches w ON w.source_id = s.id;
