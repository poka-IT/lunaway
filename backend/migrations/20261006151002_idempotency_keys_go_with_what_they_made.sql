-- An idempotency key names its account, its time, what it made and a hash
-- of the request: for a confirmation, the place and the answer, which a
-- search over the public places finds again. Once what it made is deleted
-- (by its author, a moderator, or the expiry of a road report), the key
-- goes with it; kept, it would tell which place an account confirmed after
-- the confirmation itself is gone, which the privacy page does not allow.
-- An account's deletion already takes its keys (ON DELETE CASCADE).
--
-- One trigger per table a key can point at, on the statement's deleted
-- rows, so that a purge of thousands of road reports drops their keys in
-- one statement. The function runs with its owner's rights: the importers'
-- role, which purges the road reports, has no right on the keys.
CREATE INDEX idempotency_keys_result_idx ON idempotency_keys (result_id);

CREATE FUNCTION idempotency_keys_follow_deletions() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN
    DELETE FROM public.idempotency_keys k USING gone WHERE k.result_id = gone.id;
    RETURN NULL;
END
$$;
REVOKE ALL ON FUNCTION idempotency_keys_follow_deletions() FROM PUBLIC;

CREATE TRIGGER confirmations_drop_their_keys AFTER DELETE ON confirmations
    REFERENCING OLD TABLE AS gone
    FOR EACH STATEMENT EXECUTE FUNCTION idempotency_keys_follow_deletions();
CREATE TRIGGER issue_reports_drop_their_keys AFTER DELETE ON issue_reports
    REFERENCING OLD TABLE AS gone
    FOR EACH STATEMENT EXECUTE FUNCTION idempotency_keys_follow_deletions();
CREATE TRIGGER place_submissions_drop_their_keys AFTER DELETE ON place_submissions
    REFERENCING OLD TABLE AS gone
    FOR EACH STATEMENT EXECUTE FUNCTION idempotency_keys_follow_deletions();
CREATE TRIGGER road_event_reports_drop_their_keys AFTER DELETE ON road_event_reports
    REFERENCING OLD TABLE AS gone
    FOR EACH STATEMENT EXECUTE FUNCTION idempotency_keys_follow_deletions();
