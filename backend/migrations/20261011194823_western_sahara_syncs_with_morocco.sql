-- Morocco joins the sync regions (lunaway_domain::region::SYNC_REGIONS,
-- plan/research/132-hors-ligne-pays.md), and Western Sahara syncs with it:
-- the offline map of Morocco (Natural Earth's outline) and the routing
-- graph's cut of Morocco both hold Western Sahara, so the one download
-- serves a trip down the coast. A place there keeps its country (`EH`);
-- its region becomes `MA`, as Gibraltar's is `ES`.
-- lunaway_domain::region::sync_region_of says the same;
-- lunaway-db/tests/regions.rs holds the two together.
CREATE OR REPLACE FUNCTION lunaway_sync_region(country text, commune text) RETURNS text
    LANGUAGE sql IMMUTABLE PARALLEL SAFE
    RETURN CASE
        WHEN country IS NULL THEN NULL
        WHEN upper(country) = 'FR' THEN coalesce(
            CASE
                WHEN left(commune, 2) IN ('01', '03', '07', '15', '26', '38', '42', '43', '63',
                                          '69', '73', '74') THEN 'FR-ARA'
                WHEN left(commune, 2) IN ('21', '25', '39', '58', '70', '71', '89', '90')
                    THEN 'FR-BFC'
                WHEN left(commune, 2) IN ('22', '29', '35', '56') THEN 'FR-BRE'
                WHEN left(commune, 2) IN ('18', '28', '36', '37', '41', '45') THEN 'FR-CVL'
                WHEN left(commune, 2) IN ('2A', '2B') THEN 'FR-20R'
                WHEN left(commune, 2) IN ('08', '10', '51', '52', '54', '55', '57', '67', '68',
                                          '88') THEN 'FR-GES'
                WHEN left(commune, 2) IN ('02', '59', '60', '62', '80') THEN 'FR-HDF'
                WHEN left(commune, 2) IN ('75', '77', '78', '91', '92', '93', '94', '95')
                    THEN 'FR-IDF'
                WHEN left(commune, 2) IN ('14', '27', '50', '61', '76') THEN 'FR-NOR'
                WHEN left(commune, 2) IN ('16', '17', '19', '23', '24', '33', '40', '47', '64',
                                          '79', '86', '87') THEN 'FR-NAQ'
                WHEN left(commune, 2) IN ('09', '11', '12', '30', '31', '32', '34', '46', '48',
                                          '65', '66', '81', '82') THEN 'FR-OCC'
                WHEN left(commune, 2) IN ('44', '49', '53', '72', '85') THEN 'FR-PDL'
                WHEN left(commune, 2) IN ('04', '05', '06', '13', '83', '84') THEN 'FR-PAC'
            END,
            'FR')
        WHEN upper(country) = 'MC' THEN 'FR-PAC'
        WHEN upper(country) IN ('AD', 'GI') THEN 'ES'
        WHEN upper(country) IN ('SM', 'VA') THEN 'IT'
        WHEN upper(country) = 'LI' THEN 'CH'
        WHEN upper(country) = 'SJ' THEN 'NO'
        WHEN upper(country) = 'AX' THEN 'FI'
        WHEN upper(country) = 'EH' THEN 'MA'
        ELSE upper(country)
    END;

-- `places.region` is stored: the places of Western Sahara move to Morocco
-- here, each with a new position in the change feed, under the writers'
-- lock (lunaway-db's WRITER_LOCK, 0x6c75_6e61_7761_7963) so the feed keeps
-- its order (docs/region-packs.md, "Regions"). Twelve places on 2026-10-11.
SELECT pg_advisory_xact_lock(7815274093265123683);
UPDATE places
SET country_code = country_code,
    updated_seq = nextval('place_change_seq'),
    updated_at = now()
WHERE region IS DISTINCT FROM lunaway_sync_region(country_code, municipality_code);
