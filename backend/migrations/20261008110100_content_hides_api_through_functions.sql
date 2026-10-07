-- The API's role wrote `content_hides` directly, so its credentials could
-- lift any hide, an operator's included, though the API only ever lifts
-- the hide the reports put on one item. The two writes it makes are now
-- functions running with their owner's rights, and the role keeps only
-- SELECT on the table: a leak of the API's credentials can add a hide of
-- one photo or review (what three reports or a moderator do) and lift a
-- hide the reports made, nothing else.

-- Hides one photo or review of a source wherever it shows, for the
-- reports or a moderator; a moderator's hide replaces one the reports
-- made, and neither replaces an operator's. Returns the rows written.
CREATE FUNCTION content_hide_reported(
    p_source text, p_scope text, p_key text, p_origin text
) RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE
    written bigint;
BEGIN
    IF p_scope IS NULL OR p_scope NOT IN ('photo', 'review')
       OR p_origin IS NULL OR p_origin NOT IN ('reports', 'moderator') THEN
        RAISE EXCEPTION 'the API hides one photo or review, for the reports or a moderator'
            USING ERRCODE = 'insufficient_privilege';
    END IF;
    INSERT INTO public.content_hides AS h (source_id, scope, key, origin)
    VALUES (p_source, p_scope, p_key, p_origin)
    ON CONFLICT (source_id, scope, key) DO UPDATE SET origin = excluded.origin
    WHERE h.origin = 'reports';
    GET DIAGNOSTICS written = ROW_COUNT;
    RETURN written;
END
$$;

-- Lifts the hide the reports put on one photo or review; an operator's or
-- a moderator's stays. Returns the rows removed.
CREATE FUNCTION content_unhide_reported(p_source text, p_scope text, p_key text)
RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE
    removed bigint;
BEGIN
    DELETE FROM public.content_hides
    WHERE source_id = p_source AND scope = p_scope AND key = p_key
      AND scope IN ('photo', 'review') AND origin = 'reports';
    GET DIAGNOSTICS removed = ROW_COUNT;
    RETURN removed;
END
$$;

REVOKE ALL ON FUNCTION content_hide_reported(text, text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION content_unhide_reported(text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION content_hide_reported(text, text, text, text) TO lunaway_app;
GRANT EXECUTE ON FUNCTION content_unhide_reported(text, text, text) TO lunaway_app;

REVOKE INSERT, UPDATE, DELETE ON content_hides FROM lunaway_app;
REVOKE UPDATE (origin) ON content_hides FROM lunaway_app;
