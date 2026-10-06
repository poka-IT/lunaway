-- Speed cameras, after the reviews of 2026-10-06 (docs/speed-cameras.md).

-- What an import of extracts retires by (osm_extract::scope_of): the
-- country, or a part of it another extract holds (the Canary Islands, IC).
-- An official list retires by its source alone.
ALTER TABLE enforcement_devices ADD COLUMN scope text;
UPDATE enforcement_devices SET scope = country;
ALTER TABLE enforcement_devices
    ALTER COLUMN scope SET NOT NULL,
    ADD CONSTRAINT enforcement_devices_scope_check
        CHECK (scope ~ '^[A-Z]{2}$' AND scope <> 'CH');

-- No query reads the devices by place.
DROP INDEX enforcement_devices_geom_idx;

-- The date a list gives of its own last update, when it gives one (an HTTP
-- Last-Modified): the Generalitat's open licence asks for it ("S'ha
-- d'informar de la darrera data d'actualització de la informació"), the
-- CRPA for the French list's (which gives none, the read date stands for
-- it).
ALTER TABLE enforcement_sources ADD COLUMN list_updated_at timestamptz;

-- The citation the Generalitat's licence prescribes: "Generalitat de
-- Catalunya. Departament de [nom departament]. [organisme autònom, empresa
-- pública]" (web.gencat.cat, Llicència oberta d'ús d'informació -
-- Catalunya, read 2026-10-06).
UPDATE sources
SET attribution = 'Generalitat de Catalunya. Departament d''Interior i Seguretat Pública. Servei Català de Trànsit'
WHERE id = 'cat-sct-radars';

-- The API reads only what it serves: not `device_key`, which leads to the
-- camera a zone comes from, nor `content_hash`.
REVOKE SELECT ON enforcement_items FROM lunaway_app;
GRANT SELECT (id, kind, category, country, line, point, bearing_deg, limit_kmh, source_ids,
              revision, updated_at, deleted_at)
    ON enforcement_items TO lunaway_app;
