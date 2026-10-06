-- The identity of this copy of the change feed. A sync cursor carries the
-- epoch it was issued under, and the API answers a cursor of another epoch
-- with RESYNC: after a restore from a dump, `updated_seq` starts again from
-- the dump's value, so a device holding a later cursor would otherwise skip
-- every change made between the dump and its last sync.
--
-- A restore regenerates the epoch (docs/deploy.md, "Backups and restore"):
--     UPDATE sync_epoch SET epoch = gen_random_uuid(), created_at = now();

CREATE TABLE sync_epoch (
    -- One row: the key can only be true.
    singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
    epoch uuid NOT NULL DEFAULT gen_random_uuid(),
    created_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO sync_epoch DEFAULT VALUES;
