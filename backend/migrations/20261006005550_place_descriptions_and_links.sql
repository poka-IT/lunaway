-- Every description a source gives, by language, and the links to the
-- place's pages elsewhere (its OpenStreetMap object, Wikidata, Wikipedia),
-- resolved by the conflation from the records like the other fields and
-- carried by the change feed.
--
-- Places written before this column carry empty lists until the conflation
-- rewrites them: `lunaway conflate --full` once after the deployment (the
-- digest of every place changes, so every place takes a new position in
-- the feed and devices receive the new fields).

ALTER TABLE places
    -- [{lang, text, sourceId}]; lang is a BCP 47 tag, `und` when the source
    -- does not say.
    ADD COLUMN descriptions jsonb NOT NULL DEFAULT '[]',
    -- [{sourceId, url, label}], http(s) only.
    ADD COLUMN external_links jsonb NOT NULL DEFAULT '[]';

-- The language a reviewer wrote in, as the app says it (BCP 47).
ALTER TABLE reviews
    ADD COLUMN lang text CHECK (lang ~ '^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$');
