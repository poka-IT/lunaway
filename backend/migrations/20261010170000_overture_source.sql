-- Overture Maps Places (docs/data-sources.md, "Establishments from Overture
-- Maps Places"): the establishments OpenStreetMap lacks, read at a high
-- confidence from the records of Meta, PinMeTo, DAC (CDLA Permissive 2.0)
-- and AllThePlaces (CC0 1.0), and written as points of interest outside the
-- tiles. The licence asks that "the Data Recipient makes available the text
-- of this agreement with the shared Data" (https://cdla.dev/permissive-2-0/,
-- read 2026-10-10): its URL goes with every point the API serves, through
-- `Query.sources`.
INSERT INTO sources (id, name, licence, licence_url, attribution, url) VALUES
    ('overture', 'Overture Maps Places', 'CDLA Permissive 2.0',
     'https://cdla.dev/permissive-2-0/',
     'Overture Maps Foundation, overturemaps.org: data from Meta, PinMeTo and DAC (CDLA Permissive 2.0) and AllThePlaces (CC0 1.0)',
     'https://docs.overturemaps.org/attribution/');
