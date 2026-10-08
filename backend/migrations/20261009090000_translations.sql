-- Machine translations of what the app shows in another language than the
-- reader's: the reviews of Lunaway's community, of the external community
-- source and of Mangrove, and the descriptions of a place (its own, from
-- the change feed, and those of the open sources). Lunaway's translation
-- server makes them with open models (docs/deploy.md, "Translation"), only
-- from a text stored here, never from a text a client sends; the API keeps
-- each one so the same text is translated once.
--
-- An item is named as the API names it: a review by its id, a description
-- by its place, source and language. A translation is served only while
-- the text it came from still has the same SHA-256 (`source_sha256`): an
-- edited review or a refreshed description is translated again. A review is
-- what a person wrote: when it goes, or its text changes, its translations
-- go with it at once, whoever deletes it (the triggers below run with the
-- owner's rights, so the import role, which never reads this table, still
-- clears it when a partner's review is erased).
CREATE TABLE translations (
    item_kind text NOT NULL CHECK (item_kind IN (
        'review', 'external_review', 'content_review', 'place_description', 'content_description')),
    -- The review's id, or the place's for a description.
    item_id uuid NOT NULL,
    -- A description's source and language as the place lists them; empty
    -- for a review.
    item_source text NOT NULL DEFAULT '' CHECK (char_length(item_source) <= 64),
    item_lang text NOT NULL DEFAULT '' CHECK (char_length(item_lang) <= 35),
    -- The language asked, and the one the text was taken to be in (its
    -- source's label, else guessed from its words).
    target_lang text NOT NULL CHECK (target_lang ~ '^[a-z]{2}$'),
    source_lang text NOT NULL CHECK (source_lang ~ '^[a-z]{2,3}$'),
    source_sha256 bytea NOT NULL CHECK (octet_length(source_sha256) = 32),
    text text NOT NULL CHECK (char_length(text) BETWEEN 1 AND 12000),
    -- The engine (`opus-mt`) and the model of the language pair, with its
    -- release, as the translation server named them.
    engine text NOT NULL CHECK (char_length(engine) BETWEEN 1 AND 64),
    model text NOT NULL CHECK (char_length(model) BETWEEN 1 AND 200),
    translated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (item_kind, item_id, item_source, item_lang, target_lang),
    CHECK ((item_kind IN ('place_description', 'content_description')) = (item_source <> ''))
);

-- Deletes the translations of the reviews a statement deleted (transition
-- table `gone`): one statement for a whole purge of a source.
CREATE FUNCTION translations_forget_deleted() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN
    DELETE FROM public.translations t
    USING gone g
    WHERE t.item_kind = TG_ARGV[0] AND t.item_id = g.id;
    RETURN NULL;
END
$$;

-- Deletes the translations of one review whose text changed or went.
CREATE FUNCTION translations_forget_changed() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN
    DELETE FROM public.translations
    WHERE item_kind = TG_ARGV[0] AND item_id = OLD.id;
    RETURN NULL;
END
$$;

REVOKE ALL ON FUNCTION translations_forget_deleted() FROM PUBLIC;
REVOKE ALL ON FUNCTION translations_forget_changed() FROM PUBLIC;

CREATE TRIGGER reviews_translations_deleted
    AFTER DELETE ON reviews REFERENCING OLD TABLE AS gone
    FOR EACH STATEMENT EXECUTE FUNCTION translations_forget_deleted('review');
CREATE TRIGGER reviews_translations_changed
    AFTER UPDATE OF body ON reviews
    FOR EACH ROW WHEN (OLD.body IS DISTINCT FROM NEW.body)
    EXECUTE FUNCTION translations_forget_changed('review');

CREATE TRIGGER external_reviews_translations_deleted
    AFTER DELETE ON external_reviews REFERENCING OLD TABLE AS gone
    FOR EACH STATEMENT EXECUTE FUNCTION translations_forget_deleted('external_review');
CREATE TRIGGER external_reviews_translations_changed
    AFTER UPDATE OF body ON external_reviews
    FOR EACH ROW WHEN (OLD.body IS DISTINCT FROM NEW.body)
    EXECUTE FUNCTION translations_forget_changed('external_review');

CREATE TRIGGER content_reviews_translations_deleted
    AFTER DELETE ON content_reviews REFERENCING OLD TABLE AS gone
    FOR EACH STATEMENT EXECUTE FUNCTION translations_forget_deleted('content_review');
CREATE TRIGGER content_reviews_translations_changed
    AFTER UPDATE OF text ON content_reviews
    FOR EACH ROW WHEN (OLD.text IS DISTINCT FROM NEW.text)
    EXECUTE FUNCTION translations_forget_changed('content_review');

-- A place's own descriptions: a takedown empties them, and what it said
-- (a private home) must not stay translated.
CREATE TRIGGER places_translations_changed
    AFTER UPDATE OF descriptions ON places
    FOR EACH ROW WHEN (OLD.descriptions IS DISTINCT FROM NEW.descriptions)
    EXECUTE FUNCTION translations_forget_changed('place_description');

REVOKE ALL ON translations FROM lunaway_app, lunaway_ingest;
-- The API reads, writes and replaces the translations it makes; nothing
-- else reads them.
GRANT SELECT, INSERT, UPDATE, DELETE ON translations TO lunaway_app;
