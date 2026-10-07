-- The API reads every column of the partner's reviews and photos but the
-- partner's author id, which it never serves: a fault in one of its
-- queries cannot leak it either. The id stays with the importers, who
-- need it to honour an erasure the partner forwards.
REVOKE SELECT ON external_reviews, external_photos FROM lunaway_app;
GRANT SELECT (id, source_id, record_id, external_id, author, written_at, lang, rating, body,
              vehicle, licence, fetched_at, changed_at) ON external_reviews TO lunaway_app;
GRANT SELECT (id, source_id, record_id, external_id, url, author, licence, taken_at,
              fetched_at, path, thumb_path, width, height, thumb_width, thumb_height, thumbhash,
              processed_at, attempts, retry_after, retired_at) ON external_photos TO lunaway_app;
