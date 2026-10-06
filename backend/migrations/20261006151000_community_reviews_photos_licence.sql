-- Reviews and photos are published under CC BY 4.0, outside the places
-- database (docs/architecture.md, "Licences"); new places, place edits, the
-- points users add and road reports join the databases under the ODbL. The
-- `community` source carries the ODbL, so reviews and photos get a source of
-- their own, and every row says which source it is under: `Source.licence`
-- of a review's or a photo's `sourceId` then gives its real licence.
--
-- The id names the licence because the licence is what separates the two
-- sources, and a CC BY grant cannot be withdrawn from what was published
-- under it: a later licence would be a third source.
INSERT INTO sources (id, name, licence, licence_url, attribution, url) VALUES
    ('community-cc-by', 'Lunaway community, reviews and photos', 'CC BY 4.0',
     'https://creativecommons.org/licenses/by/4.0/',
     'Lunaway contributors',
     'https://lunaway.net');

-- A constant default fills the existing rows without rewriting the tables
-- (PostgreSQL 11 and later); the foreign key is checked against them.
ALTER TABLE reviews
    ADD COLUMN source_id text NOT NULL DEFAULT 'community-cc-by' REFERENCES sources (id);
ALTER TABLE photos
    ADD COLUMN source_id text NOT NULL DEFAULT 'community-cc-by' REFERENCES sources (id);
