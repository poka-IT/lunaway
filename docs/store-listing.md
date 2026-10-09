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
  the tagged build stays out, even if the backend serves it. The change
  to make when routing covers Europe is at the end of this file.
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

Read on 2026-10-07 against `main` at 93ba876 and the production API
(`plan/research/37-alignement-publication.md` holds the commands).

| Claim | Source |
|---|---|
| Place kinds named in the first line | `app/lib/i18n/fr.i18n.json` (`kinds`), `app/lib/features/places/domain/taxonomy.dart` |
| France and twenty other European countries | `Query.regions` in production on 2026-10-07: 34 regions in 21 countries (13 French regions plus "France, hors commune", and AT, BE, CH, CZ, DE, DK, ES, FI, GB, GR, HR, IE, IT, LU, NL, NO, PL, PT, SE, SI) |
| Overnight status on every page | `app/lib/features/places/presentation/place_details.dart` |
| Filters: kind, overnight, free, eight services, "My vehicle fits" (height) | `app/lib/features/places/domain/place_filter.dart` (`Amenity.offered`, `freeOnly`), `filters_sheet.dart`; LPG is no longer a filter |
| Search by name or town, on the device | `app/lib/features/places/data/drift_places_repository.dart` |
| Hours, prices, services, contact, sources | `app/lib/features/places/presentation/place_details.dart` |
| Coordinates in five formats, share | `app/lib/core/geo/coordinate_format.dart`, `app/lib/features/places/presentation/place_actions.dart` |
| Shops and services in six categories, open now, around each place, search by name | `app/lib/i18n/fr.i18n.json` (`poi.category`), `app/lib/features/poi/` (`NearbyPois`, `SearchPois`) |
| Fuel prices of French stations, shortages, trend, cheapest around | `app/lib/features/poi/application/fuel_feed_providers.dart` (`FuelNearby`, `FuelTrend`), `backend/migrations/20261006090200_points_of_interest.sql` (`prix-carburants`) |
| Route for the vehicle and trailer, in France | `app/lib/features/navigation/data/route_operations.dart`; `Query.routing` in production on 2026-10-07: graph `20261006T0847Z-fr`, covered area 41.0 to 51.6 N, 5.8 W to 10.0 E |
| Voice guidance (every instruction, alerts only, or none), reroute, five stops, avoid options | `app/lib/features/navigation/application/guidance_controller.dart`, `application/voice_queue.dart`, `domain/route_settings.dart` (`VoiceMode`, full by default; `avoid`), `maxWaypoints` 5 |
| Roadworks and closures updated during the trip, route around closures | `app/lib/features/navigation/data/road_events_api.dart` (every 3 minutes), `route_operations.dart` (`avoidedRoadEvents`) |
| Speed limit, danger zones in France, spoken reminder of the limit off by default | `app/lib/features/navigation/domain/enforcement.dart`, `domain/driving_aids.dart` (`speedSound`), `docs/speed-cameras.md` |
| Stations along the route with detour and consumption | `app/lib/features/navigation/data/fuel_along_route.dart` |
| Directions in another app | `app/lib/core/navigation_apps.dart` |
| Regions kept offline, offline basemap by region | `app/lib/features/regions/`, `app/lib/features/offline/` (phones and tablets; web and desktop show a hint) |
| Ratings, reviews, photos, "Still there?" for places and for shops and services, problem reports, edits, new places, content reports, mute | `app/lib/features/community/`, `app/lib/features/poi/presentation/poi_details.dart` (`ConfirmPoi`) |
| Features open by trust level | `app/lib/features/account/domain/account.dart`, `backend/crates/lunaway-domain/src/community/trust.rs` |
| Account without e-mail, made at the first contribution, recovery card, deletion in the app | `app/lib/features/account/` |
| Favourite lists, kept with the account once there is one | `app/lib/features/favorites/application/favorites_providers.dart` |
| Vehicle profile fields | `app/lib/core/database/user_schema.drift` (`vehicles`) |
| Theme by sunset, light, dark; French and English; phone and tablet layouts | `app/lib/features/profile/presentation/profile_screen.dart`, `app/lib/shared/adaptive_shell.dart` |
| No ads, no trackers | `tool/allowed_hosts.txt`, `app/pubspec.lock` (no such SDK) |
| AGPL code, ODbL places | `LICENSE`, `backend/migrations/20261006005548_accounts_and_contributions.sql` (`community` source) |

Left out on purpose, as not shipped on 2026-10-07: routes outside France
(the production graph is the French one; the European graph is built
weekly by `infra/routing/europe-build.sh` and the text changes the week it
serves), road event reports by users (`reportRoadEvent` exists in the API,
no screen sends it), low-emission zones (not built), visit history (no
table), a DATAtourisme import (not built). LPG appears as a service of a
place, a fuel of the vehicle and a price of the fuel feed.

## When the routing graph covers Europe

Replace "En France, itinéraire calculé..." by "Itinéraire calculé..." and
"En France, itinéraire et guidage..." by "Itinéraire et guidage..." in
the descriptions and release notes, and "in France" likewise in English,
once `Query.routing.graph.id` in production no longer ends in `-fr`.
Danger zones stay "en France" / "in France": elsewhere the app shows what
each country's law allows (`docs/speed-cameras.md`), and the listing does
not list them country by country.

## Keywords

App Store, within the 100 bytes, checked with `python3` (bytes of
`keywords.txt`): fr 91, en 98 on 2026-10-07.
