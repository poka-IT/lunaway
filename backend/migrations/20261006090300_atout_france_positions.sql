-- The Atout France campsites the address geocoder cannot place are placed,
-- in a second pass, by the campsite toponyms of IGN BD TOPO (the
-- Géoplateforme's `poi` index, Licence Ouverte 2.0): their attribution
-- names both.
UPDATE sources
SET attribution = 'Atout France, hébergements touristiques classés (data.gouv.fr); positions: Base Adresse Nationale, IGN BD TOPO'
WHERE id = 'atout-france';
