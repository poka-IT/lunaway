# Lunaway

Website: https://lunaway.net. API: https://api.lunaway.net/graphql.

A free and open map of places to stop with a motorhome or a van: motorhome
areas, campsites, car parks that tolerate a night, service points, farms and
spots in nature. No ads, no tracking, no paywall, usable offline, and no
account needed to browse.

- **App**: Flutter for Android, iOS, macOS, Windows and the web.
- **Backend**: Rust (axum, async-graphql) over PostgreSQL and PostGIS.
- **Data**: open data (OpenStreetMap, French public datasets) merged with
  community contributions, every value credited to its source.
- **Licences**: code under AGPL-3.0-or-later, places database under ODbL,
  reviews and photos under CC BY 4.0.

Status: early development. The architecture is in `docs/architecture.md`,
the sources and their terms in `docs/data-sources.md`.

## Getting started

```bash
sh tool/setup.sh                 # git hooks, missing tools report
cd app && fvm flutter run        # the app (Flutter pinned in .fvmrc)
cd backend && cargo run -p lunaway-api   # the API on 127.0.0.1:8484
tool/check.sh                    # every gate and test, as the CI runs them
```

Contributors and coding agents start with `AGENTS.md`.

## En français

Lunaway est une carte libre des lieux où s'arrêter en camping-car ou en van :
aires, campings, parkings où la nuit est tolérée, bornes de services, fermes,
coins de nature. Sans publicité, sans pistage, sans abonnement, utilisable
hors ligne, sans compte pour consulter. Les données ouvertes (OpenStreetMap,
données publiques françaises) sont fusionnées avec les contributions de la
communauté, et chaque information indique sa source.
