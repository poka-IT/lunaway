# Data sources

Every source, its terms as read, and how Lunaway uses it. A source enters this
table before any code reads it (`.claude/skills/data-source/SKILL.md`).

## Ingested by the server

| source | content | licence | attribution | status |
|---|---|---|---|---|
| OpenStreetMap | motorhome areas (`tourism=caravan_site`), campsites (`tourism=camp_site`), dump stations, drinking water, toilets, LPG, height limits | ODbL 1.0, https://www.openstreetmap.org/copyright | "© OpenStreetMap contributors" | planned, phase 1 |
| DATAtourisme | `CamperVanArea`, `RVServiceArea` | Licence Ouverte 2.0 (credit the producer and the update date) | the producing territory, via DATAtourisme | planned, phase 1 (needs a free API key) |
| Atout France, classified accommodation (data.gouv.fr) | classified campsites | Licence Ouverte | "Atout France" | planned, phase 1 |
| Fuel prices, live feed v2 (data.gouv.fr) | LPG price and stock-outs | Licence Ouverte 2.0 | "Ministère de l'Économie, prix des carburants" | planned, phase 1 |
| Low-emission zones, charging points, Géorisques, ARCEP coverage, Météo-France | practical layers | Licence Ouverte 2.0 | per dataset | planned, phases 2 and 3 |

Merging OpenStreetMap makes the places database a derivative database under
the ODbL: it is published under the ODbL with the attribution above.

## External feeds

| source id | displayed as | delivered by | use |
|---|---|---|---|
| `extcom` | "Communauté externe" / "External community" | a crawler maintained by the maintainer in a private repository, outside Lunaway (decision of 2026-10-06, under the maintainer's responsibility) | imported every 6 hours through the generic feed importer (`docs/feeds.md`): places with their metadata, reviews and photos; photos served from our media store; every item carries the source badge |

## Never ingested

Campercontact, iOverlander, WikiCamps, Freecampsites, Searchforsites,
France Passion and Camping-Car Park: their terms forbid reuse or are
proprietary. They are reachable through outbound links only.
