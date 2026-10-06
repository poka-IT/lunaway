-- Road events, second milestone: the Dutch and Spanish national feeds and
-- six more French local datasets (docs/data-sources.md, "Road events",
-- terms as read on 2026-10-06).
--
-- The routing graph covers France only (lunaway_domain::routing::
-- covered_area): a Dutch or Spanish line asked of the engine would fail,
-- and thousands of them would hold back the French events in the matching
-- queue. `routed` says whether the graph covers a feed's area; the matcher
-- takes the lines of routed feeds only. Turn it on when the graph grows.
ALTER TABLE road_event_sources ADD COLUMN routed BOOLEAN NOT NULL DEFAULT true;

-- Staleness: twice the feed's own period plus a margin, as for the others.
INSERT INTO road_event_sources (id, name, licence, attribution, url, stale_after_s, routed) VALUES
    ('rennes', 'Rennes Métropole, travaux à 30 jours',
     'ODbL 1.0',
     'Rennes Métropole (data.rennesmetropole.fr)',
     'https://data.rennesmetropole.fr/explore/dataset/travaux_30_jours/',
     10800, true),
    ('aix-marseille-tunnels', 'Métropole Aix-Marseille-Provence, fermeture des tunnels',
     'Licence Ouverte 2.0',
     'Métropole Aix-Marseille-Provence (data.ampmetropole.fr)',
     'https://data.ampmetropole.fr/explore/dataset/fr-fermeture-des-tunnels-exploites-par-la-metropole/',
     10800, true),
    ('mayenne', 'Département de la Mayenne, routes barrées',
     'Licence Ouverte 2.0',
     'Département de la Mayenne (data.lamayenne.fr)',
     'https://data.lamayenne.fr/explore/dataset/225300011_waze_road-closures/',
     10800, true),
    ('cotes-d-armor', 'Département des Côtes-d''Armor, arrêtés de chantiers',
     'Licence Ouverte',
     'Département des Côtes-d''Armor (datarmor.cotesdarmor.fr)',
     'https://datarmor.cotesdarmor.fr/datasets/cd22arreteschantiers',
     10800, true),
    ('sarthe', 'Département de la Sarthe, chantiers routiers',
     'Licence Ouverte 2.0',
     'Département de la Sarthe (data.sarthe.fr)',
     'https://data.sarthe.fr/explore/dataset/227200029_chantiers_routiers/',
     10800, true),
    ('bordeaux', 'Bordeaux Métropole, chantiers',
     'Licence Ouverte',
     'Bordeaux Métropole (opendata.bordeaux-metropole.fr)',
     'https://opendata.bordeaux-metropole.fr/explore/dataset/ci_chantier/',
     10800, true),
    ('ndw', 'NDW, planningsfeed wegwerkzaamheden en evenementen (Netherlands)',
     'Open data, free reuse (Creative Commons per the Dutch access point)',
     'NDW, Nationaal Dataportaal Wegverkeer (opendata.ndw.nu)',
     'https://opendata.ndw.nu/',
     25200, false),
    ('dgt', 'DGT, incidencias DATEX II v3.7 (Spain)',
     'CC BY (version not stated)',
     'DGT, Dirección General de Tráfico (nap.dgt.es)',
     'https://nap.dgt.es/dataset/incidencias-dgt-datex2-v3-7',
     1800, false);
