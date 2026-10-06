-- A confirmation no longer carries any trace of the device's position
-- (decision of 2026-10-06): the verdict "within 300 m" was derived from a
-- position the client chose itself, so it proved nothing, served nothing on
-- the server, and was still location data to declare. `confirm` takes no
-- position any more, and the stored verdicts go with the column.
ALTER TABLE confirmations DROP COLUMN presence;
