-- Three speed camera sources (docs/data-sources.md, "Speed cameras"; their
-- terms read on 2026-10-09):
--   - France's yearly list of fixed cameras on data.gouv.fr, Licence Ouverte
--     2.0: "mentionner la paternité de l'"Information" : sa source (a minima
--     le nom du "Concédant") et la date de la dernière mise à jour";
--   - Brussels' regional and municipal cameras, CC0 (the dataset's page on
--     data.mobility.brussels);
--   - Ireland's mobile safety camera zones, the Irish PSI licence (circular
--     12/2016: "adopts CC-BY as the standard PSI licence"), served as a layer
--     of their own, apart from OpenStreetMap.
INSERT INTO sources (id, name, licence, licence_url, attribution, url) VALUES
    ('fr-dsr', 'Liste des radars fixes en France', 'Licence Ouverte 2.0',
     'https://www.etalab.gouv.fr/licence-ouverte-open-licence/',
     'Ministère de l''Intérieur, Délégation à la sécurité routière (data.gouv.fr)',
     'https://www.data.gouv.fr/datasets/6712583387af110196942793/'),
    ('be-bru-radars', 'Bruxelles Mobilité, radars fixes', 'CC0 1.0',
     'https://creativecommons.org/publicdomain/zero/1.0/',
     'Bruxelles Mobilité, data.mobility.brussels',
     'https://data.mobility.brussels/en/info/speedcameras/'),
    ('ie-garda', 'An Garda Síochána, safety camera zones', 'CC BY 4.0',
     'https://creativecommons.org/licenses/by/4.0/',
     'An Garda Síochána, Irish Public Sector Information, CC BY',
     'https://www.garda.ie/en/roads-policing/safety-cameras-save-lives/mobile-safety-camera-detection/');

-- A zone an authority publishes as watched by mobile cameras, stored with its
-- line in `data` (lunaway_domain::enforcement::DeviceKind::MobileZone).
ALTER TABLE enforcement_devices DROP CONSTRAINT enforcement_devices_kind_check;
ALTER TABLE enforcement_devices ADD CONSTRAINT enforcement_devices_kind_check
    CHECK (kind IN ('fixed', 'red_light', 'section', 'level_crossing', 'mobile_zone'));
