-- Idempotency keys of the contributions a device may send twice: the app
-- keeps a contribution in its outbox until the server accepts it, and an
-- answer lost on a weak network makes it send the same one again. With a key
-- (the outbox entry's id), the second request returns what the first one
-- made instead of making it twice.
--
-- A key belongs to its account, is stored in the transaction of the write it
-- names, and is dropped after 30 days by the API (and with its account).
CREATE TABLE idempotency_keys (
    account_id uuid NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
    -- Chosen by the client: a UUID or any token of the same alphabet.
    key text NOT NULL CHECK (key ~ '^[A-Za-z0-9._:-]{8,128}$'),
    operation text NOT NULL CHECK (operation IN (
        'add_place', 'edit_place', 'confirm', 'report_issue', 'report_road_event')),
    -- SHA-256 of the request's arguments: the same key sent with other
    -- arguments is a client error, not a replay.
    request_hash bytea NOT NULL CHECK (octet_length(request_hash) = 32),
    -- What the first request made: the submission, confirmation, issue
    -- report or road report.
    result_id uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (account_id, key)
);

CREATE INDEX idempotency_keys_created_idx ON idempotency_keys (created_at);

-- The API writes and purges them; nothing else reads them.
REVOKE ALL ON idempotency_keys FROM lunaway_app, lunaway_ingest;
GRANT SELECT, INSERT, DELETE ON idempotency_keys TO lunaway_app;
