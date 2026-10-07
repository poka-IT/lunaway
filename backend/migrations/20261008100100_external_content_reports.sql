-- Users report a photo or a review of an external source (the partner's
-- community, Commons, Panoramax, the tourist offices, Mangrove) the way
-- they report the community's: a `content_reports` row and a moderation
-- entry. Three reporters past level 0 hide the item until a moderator
-- decides; a moderator's rejection hides it for good. Both go through
-- `content_hides`, which every card query reads, so no import or refresh
-- brings the item back.

ALTER TABLE content_reports
    DROP CONSTRAINT content_reports_target_type_check,
    ADD CONSTRAINT content_reports_target_type_check CHECK (target_type IN (
        'review', 'photo', 'place', 'external_review', 'external_photo'));

ALTER TABLE moderation_queue
    DROP CONSTRAINT moderation_queue_target_type_check,
    ADD CONSTRAINT moderation_queue_target_type_check CHECK (target_type IN (
        'review', 'photo', 'place', 'submission', 'poi', 'road_event', 'place_hold',
        'external_review', 'external_photo'));

-- Who hid an item: an operator (`lunaway content hide`), the reports
-- (undone when a moderator keeps the item), or a moderator's rejection.
ALTER TABLE content_hides
    ADD COLUMN origin text NOT NULL DEFAULT 'operator'
        CHECK (origin IN ('operator', 'reports', 'moderator'));

-- The API's role files the reports and decides them: it hides and shows
-- an item, nothing else of the content. A rejection turns the reports'
-- hide into the moderator's, hence the update of `origin` alone.
GRANT INSERT, DELETE, UPDATE (origin) ON content_hides TO lunaway_app;
