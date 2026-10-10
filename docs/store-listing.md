# Store listings

Who reads this: whoever changes what the stores say about Lunaway. The text
lives in two fastlane layouts, in the six languages of the app:

| Store | Folder | Read by |
|---|---|---|
| Google Play, F-Droid | `fastlane/metadata/android/<fr-FR,en-US,de-DE,es-ES,it-IT,nl-NL>/` (`title.txt`, `short_description.txt`, `full_description.txt`, `changelogs/<versionCode>.txt`, `images/`) | the `google-play` MCP server (`docs/play-store.md`), fastlane `supply`, F-Droid |
| App Store | `fastlane/metadata/ios/<fr-FR,en-US,de-DE,es-ES,it,nl-NL>/` (`name.txt`, `subtitle.txt`, `promotional_text.txt`, `description.txt`, `keywords.txt`, `release_notes.txt`, `support_url.txt`, `marketing_url.txt`, `privacy_url.txt`), plus `copyright.txt`, `primary_category.txt`, `secondary_category.txt` and `review_information/` at the top | fastlane `deliver` with `metadata_path: "./fastlane/metadata/ios"` (`docs/app-store.md`); the App Store's Italian folder is `it` |

## Rules

- **Describe what the build ships, nothing more.** Each claim in the
  current text has its source in the table below; a feature that is not in
  the tagged build stays out, even if the backend serves it.
- No superlative, no price, no comparison with other apps, no third-party
  brand or app name in text, keywords or images (Play metadata policy,
  answer/9898842; App Store guideline 2.3.7 for keywords). Data sources
  are named "données ouvertes" / "open data"; the app itself shows each
  source and licence. The external community source is never named: the
  listing says "source communautaire externe" and its literal translation
  (`docs/translation-glossary.md`).
- No driving warning or safety disclaimer in the listing: it says what
  the app does.
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

- Every locale changes together. French carries the meaning; each text
  uses the app's own words in its language (`app/lib/i18n/<code>.i18n.json`):
  "Toujours là ?", "Mon véhicule passe", "Sur le trajet", and the
  register and trade terms of `docs/translation-glossary.md`.

## Sources of the current text

Read on 2026-10-10 against `main` at 0c656d30 and the production API
(`plan/research/95-textes-publication.md` holds the commands).

| Claim | Source |
|---|---|
| Place kinds named in the first line | `app/lib/i18n/fr.i18n.json` (`kinds`), `app/lib/features/places/domain/taxonomy.dart` |
| France and twenty other European countries | `Query.regions` in production on 2026-10-10: 34 regions in 21 countries (13 French regions plus "France, hors commune", and AT, BE, CH, CZ, DE, DK, ES, FI, GB, GR, HR, IE, IT, LU, NL, NO, PL, PT, SE, SI) |
| Free, every feature, offline included; no ads, no trackers | no purchase or paywall in `app/lib`; `tool/allowed_hosts.txt`, `app/pubspec.lock` (no analytics, ads or crash SDK) |
| Overnight status on every page | `app/lib/features/places/presentation/place_details.dart` |
| Filters: kind, night possible, free, services, minimum rating, open all year or on my dates, "My vehicle fits" | `app/lib/features/places/domain/place_filter.dart`, `filters_sheet.dart` (`minRating`, `openDays`) |
| Search of a place, a town or an address | `app/lib/features/places/application/places_providers.dart` (`searchResults`, `SearchAddresses`) |
| Price of the night and services, season, hours, photos, reviews, sources | `app/lib/features/places/presentation/place_details.dart`, `place_extras_view.dart` |
| Route for the vehicle and trailer, in every covered country | `app/lib/features/navigation/data/route_operations.dart`; `Query.routing` in production on 2026-10-10: graph `20261008T0129Z-eu`, covered countries the 21 of the places plus Andorra, Liechtenstein, Monaco, San Marino, the Vatican, Gibraltar and Morocco; IGN heights in France |
| Guidance, reroute, five stops | `app/lib/features/navigation/application/guidance_controller.dart`, `maxWaypoints` 5 |
| Voice in three modes | `app/lib/features/navigation/domain/route_settings.dart` (`VoiceMode`: full, alerts, muted) |
| Speed cameras and danger zones as each country's law allows, vehicle speed limit | `app/lib/features/navigation/domain/enforcement.dart`, `backend/crates/lunaway-domain/src/enforcement.rs` (`RULES`), `docs/speed-cameras.md` |
| Roadworks and closures updated during the trip, route around closures | `app/lib/features/navigation/data/road_events_api.dart`, `route_operations.dart` (`avoidedRoadEvents`) |
| Avoid tolls, motorways, ferries, unpaved roads | `app/lib/features/navigation/domain/route_settings.dart` (`avoid`) |
| "On the way": fuel, sleep, water and waste, groceries, bakeries, toilets and showers, health, charging, garages, with detour and opening at the passing time, added as a stop | `app/lib/features/navigation/presentation/on_the_way_sheet.dart`, `app/lib/i18n/fr.i18n.json` (`navigation.onTheWay`) |
| Around you: shops, water and waste, fuel, health, services, restaurants, sights; fuel prices of French stations, cheapest around | `app/lib/i18n/fr.i18n.json` (`poi.category`), `app/lib/features/poi/` (`FuelNearby`) |
| Regions kept offline, updated over Wi-Fi by default, offline basemap by region | `app/lib/features/regions/` (`region_updates_mobile`), `app/lib/features/offline/` (phones and tablets; web and desktop show a hint) |
| Reviews translated with one tap or automatically, on Lunaway's servers, no third party | `app/lib/features/translation/`, `backend/crates/lunaway-api/src/translate.rs`, `infra/translate/` |
| Ratings, reviews, photos, "Still there?", problem reports, edits, new places | `app/lib/features/community/` |
| Road reports during guidance: closed road, roadworks, narrow passage, low clearance, in France, Spain, the Netherlands | `app/lib/features/navigation/presentation/road_report_sheet.dart`; `Query.routing.roadEventReportCountries` in production on 2026-10-10: ES, FR, GI, MC, NL |
| Account without e-mail, made at the first contribution, recovery card, deletion in the app | `app/lib/features/account/` |
| Favourite lists, kept with the account once there is one | `app/lib/features/favorites/application/favorites_providers.dart` |
| Vehicle profile fields | `app/lib/core/database/user_schema.drift` (`vehicles`) |
| Six languages, voice guidance included | `app/lib/i18n/` (fr, en, de, es, it, nl), the routing engine's instructions in the app's language (`route_operations.dart`, `language`) |
| Theme by sunset, phone and tablet layouts | `app/lib/features/profile/presentation/profile_screen.dart`, `app/lib/shared/adaptive_shell.dart` |
| AGPL code, ODbL places | `LICENSE`, `backend/migrations/20261006005548_accounts_and_contributions.sql` (`community` source) |
| Open data, Lunaway community, an external community source under a written agreement | `docs/data-sources.md`; the in-app credits (`profile_screen.dart`, `_Attributions`) |

Left out on purpose: low-emission zones (not built), visit history (no
table), the number of places or reviews (they move every day), any
country list of speed cameras. LPG appears as a service of a place, a
fuel of the vehicle and a price of the fuel feed.

## Keywords

App Store, within the 100 bytes, checked with `python3` (bytes of
`keywords.txt`, without the final newline): fr 93, en 99 on 2026-10-10;
the other locales are measured in `plan/research/95-textes-publication.md`.
