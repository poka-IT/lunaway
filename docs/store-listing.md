# Store listings

Who reads this: whoever changes what the stores say about Lunaway. The text
lives in two fastlane layouts:

| Store | Folder | Read by |
|---|---|---|
| Google Play, F-Droid | `fastlane/metadata/android/<fr-FR,en-US>/` (`title.txt`, `short_description.txt`, `full_description.txt`, `changelogs/<versionCode>.txt`, `images/`) | the `google-play` MCP server (`docs/play-store.md`), fastlane `supply`, F-Droid |
| App Store | `fastlane/metadata/ios/<fr-FR,en-US>/` (`name.txt`, `subtitle.txt`, `promotional_text.txt`, `description.txt`, `keywords.txt`, `release_notes.txt`, `support_url.txt`, `marketing_url.txt`, `privacy_url.txt`), plus `copyright.txt`, `primary_category.txt`, `secondary_category.txt` and `review_information/` at the top | fastlane `deliver` with `metadata_path: "./fastlane/metadata/ios"` (`docs/app-store.md`) |

## Rules

- **Describe what the build ships, nothing more.** Each claim in the
  current text has its source in the table below; a feature that is not in
  the tagged build stays out, even if the backend serves it. The variants
  for features to come are at the end of this file.
- No superlative, no comparison with other apps, no third-party brand or
  app name in text or images (Play metadata policy, answer/9898842; App
  Store guideline 2.3.7 for keywords). Data sources are named "données
  ouvertes" / "open data"; the app itself shows each source and licence.
- Limits, checked by `python3` in the release steps (`docs/release.md`):

| Field | Limit |
|---|---|
| Play title, App Store name | 30 characters |
| App Store subtitle | 30 characters |
| Play short description | 80 characters |
| App Store promotional text | 170 characters |
| Play full description, App Store description | 4000 characters |
| Play release notes (`changelogs/<versionCode>.txt`) | 500 characters |
| App Store keywords | 100 bytes, comma separated, words of the name and subtitle not repeated |

- Both locales change together. The French text uses the app's own words
  (`app/lib/i18n/fr.i18n.json`): "Toujours là ?", "Mon véhicule passe",
  "Nuit autorisée".

## Sources of the current text

Read on 2026-10-06 in the working tree (the account and community code
was not yet committed).

| Claim | Source |
|---|---|
| Place kinds named in the first line | `app/lib/i18n/fr.i18n.json` (`kinds`), `app/lib/features/places/domain/taxonomy.dart` |
| Overnight status on every page | `app/lib/features/places/presentation/place_details.dart` |
| Filters: kind, overnight, nine services, "My vehicle fits" (height) | `app/lib/features/places/domain/place_filter.dart`, `app/lib/features/places/presentation/filters_sheet.dart` |
| Search by name or town, on the device | `app/lib/features/places/data/drift_places_repository.dart` |
| Hours, prices, services, contact, sources | `app/lib/features/places/presentation/place_details.dart` |
| Coordinates in five formats | `app/lib/core/geo/coordinate_format.dart` |
| Directions in another app, share | `app/lib/core/navigation_apps.dart`, `app/lib/features/places/presentation/place_actions.dart` |
| Places of metropolitan France copied to the device; basemap, photos and reviews need a connection | `app/lib/features/places/data/sync/sync_service.dart`, `app/lib/core/geo/geo.dart`; i18n `place.extrasOffline`; no offline basemap in `app/lib` |
| Ratings, reviews, photos, "Still there?", problem reports, edits, new places, content reports, mute | `app/lib/features/community/` |
| Features open by trust level | `app/lib/features/account/domain/account.dart`, `backend/crates/lunaway-domain/src/community/trust.rs` |
| Account without e-mail, recovery card, deletion in the app | `app/lib/features/account/` |
| Favourite lists, synced on choice | `app/lib/features/favorites/` |
| Vehicle profile fields | `app/lib/core/database/user_schema.drift` (`vehicles`) |
| Theme by sunset, light, dark; French and English; phone and tablet layouts | `app/lib/features/profile/presentation/profile_screen.dart`, `app/lib/shared/adaptive_shell.dart` |
| No ads, no trackers | `tool/allowed_hosts.txt`, `app/pubspec.yaml` (no such SDK) |
| AGPL code, ODbL places | `LICENSE`, `backend/migrations/20261006005548_accounts_and_contributions.sql` (`community` source) |

Left out on purpose, as not shipped in the app on 2026-10-06: in-app
navigation and roadworks, the "around me" layer and fuel prices (served by
the backend since 69f9c98, shown nowhere in the app), low-emission zones
(not built anywhere), visit history (no table), offline basemap, a
DATAtourisme import (not built). LPG appears only as a service of a place
and a filter.

## Variants for features to come

Pick the paragraph when the tagged build ships the feature, check its
claims against the code of that build, and update the Data safety
inventory (`docs/play-store.md`) and the App Store label
(`docs/app-store.md`) in the same change: directions and "around me" send
the device position.

### Directions computed for the vehicle (`route` query)

Two levels, depending on what the app ships.

Route preview with warnings, no guidance (fr, new section before
"PARTICIPER"):

```
ITINÉRAIRE POUR VOTRE VÉHICULE
• Itinéraire calculé pour la hauteur, la largeur, la longueur et le poids de votre véhicule : les ponts trop bas et les routes interdites à votre gabarit sont écartés
• Alertes sur le trajet, par exemple un pont à 3,20 m, avec la date des données
• Options : éviter les péages, les autoroutes, les ferries et les routes non revêtues
Les hauteurs et les limites viennent de données ouvertes et peuvent manquer : la signalisation sur place reste la référence. Le départ, l'arrivée et les dimensions du véhicule partent vers notre serveur pour le calcul, sans être enregistrés.
```

```
DIRECTIONS FOR YOUR VEHICLE
• A route computed for your vehicle's height, width, length and weight: bridges too low and roads closed to your size are left out
• Warnings along the way, such as a 3.20 m bridge, with the date of the data
• Options: avoid tolls, motorways, ferries and unpaved roads
Heights and limits come from open data and can be missing: the signs on the road come first. The start, the destination and the vehicle's dimensions go to our server for the computation and are not stored.
```

With turn-by-turn guidance and voice, add one bullet (only if the build
speaks and follows the vehicle):

```
• Guidage pas à pas et à la voix, recalcul si vous quittez l'itinéraire
• Turn-by-turn and voice guidance, recomputed when you leave the route
```

Short description (Play, 80 characters at most), if directions ship:

```
Aires, parkings et campings, et itinéraires adaptés au gabarit du véhicule
Motorhome areas, car parks, campsites, and routes that fit your vehicle
```

Remove "Itinéraire vers le lieu dans l'application de navigation de votre
choix" only if the app stops offering other apps.

### Roadworks and closures (`road_events`, not served on 2026-10-06)

Only together with directions, and only for the networks the build reads
(on 2026-10-06 the design covers the national roads run by the DIR and the
DiaLog orders, `plan/research/20-travaux-temps-reel.md`):

```
• Fermetures et chantiers publiés pour le réseau routier national pris en compte dans l'itinéraire
• Closures and roadworks published for the national road network taken into account in the route
```

Do not write "temps réel" / "real time" unless the build refreshes them
during guidance.

### "Around me" layer and fuel prices

```
AUTOUR DE VOUS
• Courses, distributeurs, eau et vidange, carburant et énergie, santé, services : les points utiles autour d'un lieu, avec leurs horaires et s'ils sont ouverts
• Prix des carburants et du GPL des stations françaises, avec la date de mise à jour et les ruptures signalées
```

```
AROUND YOU
• Groceries, vending machines, water and dump points, fuel and energy, health, services: the useful points around a place, with their hours and whether they are open
• Fuel and LPG prices of French stations, with the time of the last update and reported shortages
```

The six category names are those of `backend/crates/lunaway-domain/src/poi.rs`;
use the labels the app shows.

### Offline basemap (if regional packs ship)

```
Téléchargez aussi le fond de carte d'une région avant de partir : la carte s'affiche alors sans réseau.
You can also download the basemap of a region before you leave: the map then shows without a network.
```

### Low-emission zones

Not built. No wording until a build shows them.

## Keywords to add with the variants

App Store, within the 100 bytes: `itinéraire,gabarit,hauteur,pont` (fr),
`route,height,bridge,clearance` (en) for directions; `GPL,carburant,
distributeur` (fr), `fuel,LPG,vending` (en) for "around me". Drop
weaker words to stay within the limit.
