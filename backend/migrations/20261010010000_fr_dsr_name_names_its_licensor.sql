-- The French list of fixed cameras (Licence Ouverte 2.0) asks to be cited by
-- its licensor ("a minima le nom du Concédant") with the date of its last
-- update. Where room is short, the guidance banner and a camera's callout
-- cite a list by its name with that date, and every other list's name
-- already names its licensor; this one said only "Liste des radars fixes en
-- France". The full attribution stays for the route preview and the
-- credits.
UPDATE sources
SET name = 'Délégation à la sécurité routière, radars fixes'
WHERE id = 'fr-dsr';
