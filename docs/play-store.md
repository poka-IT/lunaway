# Publishing on Google Play

Who reads this: whoever ships an Android release. The store listing lives in
`fastlane/metadata/android/<locale>/` (F-Droid reads the same layout).

The app exists in the AxiomTeam developer account, an organization account:
package `legal.p2p.lunaway`, default language fr-FR, free. Public URLs:

| Use | URL |
|---|---|
| contact email (listing, public) | contact@lunaway.net |
| website (listing contact) | https://lunaway.net |
| privacy policy (listing, App content, and a link inside the app) | https://lunaway.net/privacy |
| account deletion request (Data safety) | https://lunaway.net/account/delete |

## Access and tools

On the maintainer's machine, two MCP servers drive the Play Console. They
are registered in the local Claude Code scope (`~/.claude.json`), so they are
not part of the repo.

| Server | What it does | Setup |
|---|---|---|
| `google-play` | Google Play Developer API: edits, bundle upload, tracks, listings, images, testers, Data safety | `app-publish-mcp` (github.com/mikusnuz/app-publish-mcp) built from audited commit 56afe77, never from npm (the published 0.4.1 lags behind); started from a directory without `.env`, since it loads one from its working directory |
| `play-console-browser` | Playwright MCP attached over CDP to a dedicated Brave profile, for what the API cannot do | `~/.config/lunaway/play-browser.sh` starts Brave with `--remote-debugging-port=9333`; the Google login is done by hand in that window |

The service account key sits outside the repo, mode 0600, and never enters
an agent's context: the MCP server reads it, nobody prints it. Google no
longer asks to link a Cloud project; the service account email is invited in
Play Console, Users and permissions, with rights on Lunaway only (releases
and store presence, no admin, no financial data).

### Who can do what

| Task | API (`google-play`) | Browser only |
|---|---|---|
| Create the app in Play Console | | yes |
| First release of a never published app | upload, as `draft` only | roll out the draft |
| Later releases, all tracks, staged rollout | yes | |
| Store listing text, images, release notes | yes | |
| Testers of a closed track (Google Groups) | yes | |
| Data safety form | yes (CSV) | |
| Content rating, target audience, ads, app access, privacy policy URL | | yes |
| Apply for production access (personal accounts only) | | yes |

The API refuses any status other than `draft` on an app that was never
published ("Only releases with status draft may be created on draft app").
The first rollout is a click in the Console.

Google refuses to validate any API edit while the app has no contact email
("This app does not have a contact email address set"): set it once in the
store settings before the first API push.

## Signing

Play App Signing holds the app signing key. We keep the upload key:

- PKCS12, RSA 4096, alias `upload`, valid 10 000 days from 2026-10-06,
  stored outside the repo;
- `app/android/key.properties` (gitignored, deny-listed for agents) points at
  it with `storeFile`, `storePassword`, `keyAlias`, `keyPassword`;
- upload certificate SHA-256:
  `98:8B:3F:B8:5F:26:27:71:E0:09:8B:07:6F:59:D7:B9:AF:7B:C1:79:F9:16:B2:38:58:35:C2:63:30:16:A0:C1`.

The `store` flavor signs its release with `key.properties`. Without the file,
a store release stops at its first task (`checkStoreReleaseSigning`) unless
the build passes `-P allowDebugSigning=true` (flutter) or
`-PallowDebugSigning` (gradle): the build is then signed with the debug key,
its version name ends in `-debugsigned`, and it serves local tests only. The
`fdroid` release is never signed here. Back up the keystore and its password
together. A lost upload key is replaced
through Play Console (App signing, request upload key reset), which takes
days.

F-Droid signs its own builds: a user cannot update a Play install with an
F-Droid APK or the reverse.

## Requirements that bind the code

Checked on Google's pages on 2026-10-06.

- **targetSdk 36 or higher** for new apps and updates since 2026-08-31
  (developer.android.com/google/play/requirements/target-sdk).
- **16 KB memory pages** on 64-bit devices for apps targeting API 35+;
  updates without it are refused from 2027-02-01
  (developer.android.com/guide/practices/page-sizes). `maplibre_gl` ships
  native libraries, so check every release bundle:
  `bundletool dump config --bundle=<aab> | grep alignment` must print
  `PAGE_ALIGNMENT_16K`.
- **Account deletion.** The app creates an account at the first
  contribution, or when the user chooses to sync favourites
  (`app/lib/features/account/data/account_service.dart`), so it must offer
  an in-app path to delete the account and its data, and a public web page
  to request it (support.google.com/googleplay/android-developer/answer/13327111).
- **Privacy policy** reachable over HTTPS without login, linked from the
  listing, the App content section and inside the app.

## Store listing rules

- Limits: title 30 characters, short description 80, full description 4000.
  `changelogs/<versionCode>.txt` holds the release notes, 500 characters.
- No comparison with other apps or brands, no third-party brand without
  permission, no keyword stuffing (Play metadata policy,
  support.google.com/googleplay/android-developer/answer/9898842). The
  listing, text and images, never names or shows a third-party brand.
- Images to produce from the finished app: icon 512 x 512 PNG, feature
  graphic 1024 x 500, at least two phone screenshots.

## App content answers

Filed on 2026-10-06, stable: no ads, not a government app, no financial
feature, no health feature, privacy policy URL, target audience 18 and over,
category Travel and Local, contact details. The store listing text of fr-FR
and en-US is pushed (the 2026-10-06 text): push the 2026-10-10 text of
`fastlane/metadata/android/` again before the submission, now in six
locales (fr-FR, en-US, de-DE, es-ES, it-IT, nl-NL).

Saved as drafts in the Console, not submitted: the content rating
questionnaire (category "all other app types", answers below) and the Data
safety form up to step 4. The Data safety draft predates the inventory
below and differs from it: it declares precise location as ephemeral (it
is kept, with a new place and a road report), lacks Device or other IDs,
App interactions, Approximate location and In-app search history, and
shares nothing. Correct it from "Data safety, the form" before
submitting. Both forms are submitted at release, once the build confirms
these answers.

Decisions from the app side behind those answers (checked against `main`
at 0c656d30 on 2026-10-10):

- Users can hide every contribution of an author (a mute synced with the
  account) and report a review, a photo or a place.
- Place and town search run on the device when it holds places; on a
  device without places (the web, a phone before its regions arrive) the
  text and the map centre snapped to a 0.05 degree grid go to our server.
  The search of addresses and of shops and services send their text to
  our server. Our servers neither store nor log them: declared as In-app
  search history, processed ephemerally. The address text, with the
  rounded map centre and without the client's address, goes on to IGN's
  Géoplateforme geocoder, whatever the country
  (`backend/crates/lunaway-api/src/geocode.rs`): In-app search history
  declared as shared, and Approximate location too, since that map centre
  is the device position rounded when the map follows the user. An API
  that stopped sending the point to IGN (`ask_ban`, `lat` and `lon`)
  would take Approximate location off the shared data.
- Road reports ship (`app/lib/features/navigation/presentation/road_report_sheet.dart`):
  a precise position kept 14 days with the account, weighed for abuse
  (two accounts of level 1 or more before an event changes routes):
  Precise location gains Fraud prevention, security, and compliance.
- Every build uses the self-hosted basemap on tiles.lunaway.net; the app
  has no other tile host (`app/lib/core/config/app_config.dart`,
  `tool/allowed_hosts.txt`).
- The pseudonym starts generated, the user can edit it, and it is public on
  their contributions: declared as "name".
- A user can delete any single review, rating, photo, place proposal,
  confirmation, answer about a shop or a service, or problem report of
  their own without deleting the account (Profile, My contributions). The
  deletion page explains both paths.

- **App access** ("Informations de connexion"): filed as "no restricted
  part", because the Console requires it before the target audience. At
  release, switch it to restricted: browsing and directions need no
  account, but a fresh account starts at trust level 0 (favourites,
  ratings, confirmations); written reviews and photos need level 1 and new
  places level 2 (`backend/crates/lunaway-domain/src/community/trust.rs`).
  The demo account comes from `sudo lunaway-admin accounts create-demo
  --level 2` on the backend (`docs/deploy.md`, "lunaway-admin"), which
  prints a recovery code; the reviewer enters it in Profile, "Recover my
  account". The code goes into the Console field only, never into the
  repository.
- **Content rating:** users publish reviews, ratings, photos, places and
  road reports, all public to every user (a road report as an event
  without author). Moderation: automatic text rules (links,
  contact details, repetition, a word list;
  `backend/crates/lunaway-domain/src/community/moderation.rs`) hold a text
  for a moderator; a review or photo reported by three trusted accounts is
  hidden until a moderator decides; moderators work the queue from the
  command line; users can report content and hide an author. No user to
  user messaging; users are pseudonymous; no location tied to a user is
  shown to others (a road report becomes a public event without author,
  at about 11 m, with its times), but the places an author reviewed,
  photographed or added are
  public under their pseudonym, with the visit date they chose to give
  (`app/lib/features/places/data/graphql/operations.dart`: `authorId`,
  `visitedAt`); no purchases. Unchanged by the guidance: the speed limit
  and the danger zones are information shown during a route, with no
  user-reported police check (`docs/speed-cameras.md`, "Police checks");
  the answers of the questionnaire on violence, gambling, user location
  sharing and user interaction stay as above.
- **Foreground service permissions** (App content, required since the
  bundle declares `FOREGROUND_SERVICE_LOCATION`, merged from
  `app/packages/lunaway_nav/android/src/main/AndroidManifest.xml`): type
  `location`, use case navigation. Text: "During guidance the user starts
  towards a place, the app follows the vehicle and speaks the instructions
  and the alerts (a bridge lower than the vehicle, a closure ahead, a
  danger zone or a speed camera where the country's law allows it), with
  the screen off or another app in front. The service starts from the app
  in the foreground and stops at the arrival or when the guidance ends." The
  Console asks for a video: the trip of
  `app/integration_test/navigation_drive_test.dart` filmed on a device. No
  `ACCESS_BACKGROUND_LOCATION` is declared, so the background location
  declaration does not apply.
- **Data safety:** "Data safety, the form" below.

## Data safety inventory

Rewritten on 2026-10-10 from `main` at 0c656d30: the app (`app/lib`), the
backend (`backend/`) and the infrastructure (`infra/`), each fact with its
file, by four read-only audits whose findings are kept in
`plan/research/95-textes-publication.md` (maintainer's copy).
`docs/app-store.md` derives the App Store privacy label from this
section; the privacy page (`tool/site/src/pages/*/privacy.html`)
describes the same facts. Change them together.

### What leaves the device

The app talks only to our hosts, api.lunaway.net and tiles.lunaway.net,
over HTTPS (`app/lib/core/config/app_config.dart`,
`tool/allowed_hosts.txt`). It has no third-party SDK for analytics, crash
reports or ads (`app/pubspec.lock`). Native requests carry the User-Agent
`Lunaway/<version> (+https://lunaway.net)`
(`app/lib/features/places/data/graphql/graphql_client.dart`); MapLibre's tile requests on
Android and iOS carry its own (`legal.p2p.lunaway/<version> (<build>)
MapLibre Android/<version> Android/<API level> (<ABI>)`, read in the access
log on 2026-10-07); the web app, and the map web view of macOS and
Windows, send the browser's.

| Datum | Sent when | Kept on the server | Source |
|---|---|---|---|
| Regions of the place sync | phones and computers (the web keeps no places): the list of regions, the pack of each region kept (its URL names the region), then the changes of each region by its code, at launch, on resume when the data is older than 12 h, after an accepted contribution and when the network turns unmetered; on a metered network, updates wait unless the user allows mobile data. The first region is chosen on the device from the device position (else the map view, else the device's country): the region code of the first sync therefore follows the position, at region scale | nothing in the database; the access log writes every pack path as `/packs/places/[pack]` | `app/lib/features/regions/` (`region_providers.dart`, `regionHere`), `app/lib/features/places/application/places_providers.dart`, `infra/caddy/Caddyfile` (`access_log`) |
| Offline basemap packs | the user downloads a region's map (Android and iOS) | nothing; logged as `/packs/[pack].pmtiles` | `app/lib/features/offline/`, `Caddyfile` |
| Map area viewed | basemap tiles (tiles.lunaway.net), place tiles and point of interest tiles (api.lunaway.net); a reachability probe (`planet.json`) every 10 min and on resume, carrying nothing | nothing; the access log and the API's request span keep the zoom only | `Caddyfile`, `backend/crates/lunaway-api/src/tiles.rs`, `app/lib/features/offline/application/offline_providers.dart` |
| List of places beside the map, count of the filter sheet | online, the map zoomed out below 12, or from 12 on when the tiles do not answer within 6 s: the visible area widened to a 0.05 degree grid, the map centre on the same grid (the device position, rounded, when the map follows it), the filters, and with "on my dates" the days of the year of the stay (`openDays`, without the year). Then, for the rating and the opening of each row's description (`placeDigests`): the ids of the rows (also those of the "On the way" list), or from zoom 12 the visible area widened to the same grid (around the device position when the map follows it); kept in memory on the device | nothing: a POST body | `app/lib/features/map/application/map_state.dart`, `listed_places.dart`, `app/lib/features/places/application/place_digests.dart`, `app/lib/features/places/data/graphql/operations.dart` (`openDays`), `online_places.dart` |
| Search of places, towns, addresses and points of interest | every online device, once typing pauses (offline, or when the API does not answer within 8 s, a device with regions searches its own): the text, the app language and the map centre snapped to a 0.05 degree grid (the device position, rounded, when the map follows it), and from 3 characters the number of points asked; no session; one request (`SearchAll`) | nothing: a POST body | `app/lib/features/places/application/places_providers.dart` (`searchResults`), `online_places.dart` (`searchAnchor`) |
| Search of addresses | every online device, 3 characters or more: the text, the app language and the map centre on the 0.05 degree grid (rounded again by the server); no session. The server sends the text and that point, without the client's address or any identifier, to its own Photon (OpenStreetMap) and to IGN's Géoplateforme geocoder (`data.geopf.fr`), whatever the country | nothing on our servers (no access log on the geocoders' proxy, the API logs neither); IGN receives the text and the rounded point and keeps them under its own terms (not known to us) | `places_providers.dart` (`searchResults`, `SearchAll`), `backend/crates/lunaway-api/src/geocode.rs`, `address_query.rs`, `infra/caddy/geocoders.caddy` |
| A place's page | the place id: the place on a device without its region (`Place`), its Lunaway community reviews and photos with the session when an account exists (`PlaceExtras`), the external community source's reviews, ratings and photos without a session (`PlaceExternal`), the points around it (`NearbyPois`) | nothing about the place; the session's last-use date moves at most once an hour, and the account's day count | `app/lib/features/places/`, `backend/crates/lunaway-api/src/auth.rs`, `backend/crates/lunaway-db/src/accounts.rs` |
| Photos | `/media/...` and `/external-photos/<uuid>/thumb\|large` on api.lunaway.net; the second makes our server download the partner's photo on its first view (the partner's host sees the server, never the device) | the re-encoded file, served from `/media/`; the access log masks both paths | `app/lib/shared/images/image_fetcher.dart`, `backend/crates/lunaway-api/src/external_photos.rs`, `Caddyfile` |
| Translation | the user taps Translate, or automatic translation of reviews is on (off by default): the item's kind and id, the description's source and language, the app language; never the text; no session | the translation, keyed by the item and the target language, as long as the original stands (the cache of every reader); nothing about who asked; the text goes from the backend to our translation server on the private network, which keeps nothing | `app/lib/features/translation/`, `backend/crates/lunaway-api/src/translate_query.rs`, `translate.rs`, migration `20261009090000_translations.sql`, `infra/translate/` |
| Places along a route, on a device without places | the route preview opens on the web or a phone before its regions arrive: up to 20 stretches of the route as boxes widened to a 0.05 degree grid, and the filters | nothing: a POST body | `app/lib/features/navigation/application/route_extras.dart` |
| Photos and prices of the places near a route | the maps of the preview and the guidance: the ids of the places drawn (during guidance, places 250 to 1 200 m from the vehicle) | nothing | `app/lib/features/navigation/data/place_thumbs.dart` |
| Fuel stations of the view | the fuel layer is on and the zoom is 10 or more: the visible area widened to a 0.05 degree grid, at most 1.95 degree a side | nothing: a POST body | `app/lib/features/poi/application/poi_providers.dart` (`FuelStations`) |
| The point of the cheapest fuel list | the list of the cheapest around the user, when the view is zoomed out below 10 or holds too many stations: the user's position, else the map centre, rounded on the device to a twentieth of a degree (about 5 km), the fuel, a 20 km radius | nothing: a POST body; the server rounds again to 0.05 degree | `app/lib/features/poi/application/fuel_feed_providers.dart`, `backend/crates/lunaway-api/src/fuel_query.rs` |
| Price history of a station | a station's page opens: its id and one fuel | nothing | `fuel_feed_providers.dart` (`FuelTrend`) |
| Search of shops, services and other points of interest | in the search's one request (above), from 3 characters | nothing: a POST body | `app/lib/features/map/presentation/map_search.dart`, `app/lib/features/poi/data/poi_operations.dart` (`searchAnchor`, `searchPoiCount`) |
| Around a place, a point's page | the place id, or the point id | nothing | `app/lib/features/poi/data/poi_repository.dart` |
| Route request | the user asks for a route: start (the device position, or a place, town or address the user chose), destination, up to 5 stops, the vehicle's kind, size, weight and cruising speed and its trailer's, avoid options, language, whether the start is the vehicle; during guidance each new route (off the route, a closure ahead, a stop added or removed) from the current position with its heading, and the route through a stop priced before it is confirmed; no session | nothing: a POST body; the API logs per route its timings and outcome, never a coordinate; the routing engine's journal holds no coordinate | `app/lib/features/navigation/application/navigation_providers.dart`, `guidance_controller.dart`, `data/route_operations.dart`; `backend/crates/lunaway-api/src/lib.rs`, `routing_query.rs` |
| The route line, for "On the way" (fuel and other categories) | the user opens the list: the line as the server drew it, from 2 km past the start in the preview or 2 km ahead of the vehicle during guidance, the category, the vehicle profile, and for fuel the fuel and consumption; against an API without that search, five points ahead each rounded to a hundredth of a degree | nothing: a POST body; the server drops 2 km more at each end before any use | `app/lib/features/navigation/data/fuel_along_route.dart`, `on_the_way_api.dart`, `fuel_stations_api.dart`; `backend/crates/lunaway-api/src/along_query.rs`, `schema.rs` (`trim_ends`) |
| Road events of the guidance | at the start and every three minutes during guidance: a cursor only | nothing | `app/lib/features/navigation/data/road_events_api.dart` |
| Speed camera data | at the route preview, at the start of a guidance, after each new route, when the setting of exact positions in France changes, and every six hours: the country codes the route crosses (worked out on the device) and the cursor; with that setting on, the code FR (`exactIn`); never a position | nothing: the choice is neither logged nor kept, and the access log drops the request size (`backend/crates/lunaway-api/src/enforcement_query.rs`, `Caddyfile`) | `app/lib/features/navigation/data/enforcement_api.dart`, `application/driving_aids.dart`, `preview_enforcement.dart` |
| Road report | the user reports a closed road, roadworks, a narrow passage, a low clearance or another problem (France, Spain and the Netherlands; the API also accepts Monaco and Gibraltar, inside their map extracts), from the guidance or a point of the map, or answers "Still there" or "It's over" on a reported event: kind, exact position (the vehicle's, snapped to the route, or the point chosen; for "Still there", the event's), heading during guidance, measured value; "It's over" sends the event id. Through the outbox, with the session; the first report creates the account | `road_event_reports`: account, kind, exact position, heading, value, date; deleted after 14 days and with the account. The public event has no account and no heading, its position rounded to 4 decimals (about 11 m). A confirmed event, and an "It's over" on an event that changed routes, opens a moderation entry with the account, deleted a year after the decision | `app/lib/features/navigation/presentation/road_report_sheet.dart`, `guidance_screen.dart`, `point_details.dart`, `app/lib/features/community/data/community_operations.dart`; `backend/crates/lunaway-db/src/road_events.rs` (`REPORT_KEEP_DAYS`), migration `20261006120000_road_events.sql` |
| Device public key (P-256), signature, app language | the first contribution or favourites sync creates the account, then each sign-in; with an account, `MyAccount` at each launch with the session | the public key, its RFC 7638 thumbprint, creation and last-use dates (`device_keys`); the language only draws the pseudonym and is not stored | `app/lib/features/account/data/account_service.dart`, `application/account_providers.dart`; `backend/crates/lunaway-api/src/mutation.rs` (`signIn`) |
| Pseudonym | drawn by the server at account creation in the app's language, editable, public | `accounts.pseudonym` | `backend/migrations/20261006005548_accounts_and_contributions.sql`; `backend/crates/lunaway-auth/src/pseudonym.rs` |
| Account record | derived by the server | id, trust level, granted level, number of days of use and last active day, creation date, moderation removals, ban date and reason | same migration; `20261006005551_moderation_removals_and_reporters.sql` |
| Session | each sign-in | SHA-256 of the token and its dates; expires 60 days after last use, purged every hour | `backend/crates/lunaway-api/src/config.rs`, `src/main.rs` |
| Recovery code | the user makes a recovery card | the argon2id hash only | `backend/crates/lunaway-api/src/mutation.rs` |
| Rating, review (text, visit date, vehicle kind, language) | the user rates or writes | `reviews`, published under CC BY 4.0 (`community-cc-by`) | `app/lib/features/community/data/community_operations.dart`; migration `20261006151000` |
| Photo | the user adds one | two WebP files re-encoded from the pixels (2048 and 512 px), no metadata; the original is not kept | app: `app/lib/features/community/data/photo_prepare_io.dart` resizes to 2560 px and clears EXIF and ICC before upload; server: `backend/crates/lunaway-media/src/pipeline.rs` |
| "Still there?" on a place | the user answers | `confirmations`: status and an optional note for moderators; no position; deleted after two years, the place keeping the counts (`confirmation_tallies`) | `community_operations.dart`; `backend/crates/lunaway-db/src/retention.rs` (`CONFIRMATION_DAYS`) |
| "Still there?" on a shop or service | the user answers | `poi_confirmations`: point, answer, date, account; purged after 365 days | `app/lib/features/poi/presentation/poi_details.dart`; `backend/crates/lunaway-db/src/pois.rs` (`ANSWER_DAYS`) |
| Problem report, content report | the user reports | `issue_reports` (deleted after 90 days), `content_reports` (deleted a year after the moderator's decision): kind or reason, optional note | 20261006005548; `retention.rs` (`ISSUE_REPORT_DAYS`, `RESOLVED_DAYS`) |
| New place, new vending machine, place edit | the user submits | `place_submissions`: the payload, with the position the user sets (a long press, or the map centre, which after "Show my position", or a launch that opens the map on the user, is the device's own position), linked to the account and device key; a rejected or withdrawn one emptied 30 days after the decision; at the account's deletion, the unapplied ones emptied and the applied ones kept without account | `app/lib/features/map/presentation/map_screen.dart`, `locate_flow.dart`, `app/lib/features/community/presentation/place_form.dart`, `add_vending.dart`, `backend/crates/lunaway-db/src/submissions.rs`, `accounts.rs`, `retention.rs` (`SUBMISSION_PAYLOAD_DAYS`) |
| Favourite lists | as soon as an account exists (made by the sync or by the first contribution), then 3 s after each change, at launch and on resume | list names and place ids (`favorite_lists`, `favorite_items`); the points saved outside the places (an address, a town, a bare point, a shop): the name the user gave, an optional note, the postal address when known and the coordinates (`favorite_points`), private to the account and deleted with it | `app/lib/features/favorites/application/favorites_providers.dart`, `data/favorites_sync.dart` |
| Muted authors | the user mutes | `muted_authors` | 20261006005548 |
| Idempotency keys | each contribution sent through the queue | key, operation, SHA-256 of the arguments (for a road report, kind and value only), result id; 30 days (14 for a road report), deleted with what they made and with the account | `app/lib/features/community/data/outbox_sender.dart`; migrations `20261006151001`, `20261006151002`; `backend/crates/lunaway-api/src/main.rs` |
| Client address | every request | not stored: rate limits and quotas count per IPv4 address or IPv6 block in memory, reset by a restart | `backend/crates/lunaway-api/src/{rate,quota,client}.rs` |
| Request line and headers | every request | access log: date, method, host, path without query string, status, duration, User-Agent and the other request headers but `Authorization`, `Cookie`, `X-Forwarded-For`, `Content-Length` and the cache and range headers; IP truncated to /16 (IPv4) or /32 (IPv6); photo paths, tile coordinates and pack names masked. A new file every day, a line kept about 14 days (`roll_interval 24h`, `roll_keep_for 288h`); system journal, a new file every week, removed once its last entry is a month old (six weeks at most); both also in Hetzner's 7 daily images of the backend's root disk | `infra/caddy/Caddyfile`, `infra/files/etc/systemd/journald.conf.d/lunaway.conf`, `docs/deploy.md` ("How long things are kept") |

Not sent: place and town search on a device that holds places
(`app/lib/features/places/data/drift_places_repository.dart`), contacts,
e-mail, phone number, crash data, microphone or audio (the app has no
microphone permission). The position also goes, on the device, to
Organic Maps when the user opens a route in it (the only navigation app
that takes a start point, `app/lib/core/navigation_apps.dart`); this is a
user-initiated transfer, which the form does not count as sharing.

### Data safety, the form

Data collection and security:

- Does your app collect or share any of the required user data types: yes.
- Is all of the user data collected by your app encrypted in transit: yes
  (HTTPS only; the debug build alone allows cleartext, to the emulator
  host, `app/android/app/src/debug/AndroidManifest.xml`).
- Which of the following methods of account creation does your app
  support: other (a key pair made on the device; no user name, password,
  e-mail or third-party sign-in). Delete account URL:
  https://lunaway.net/account/delete.
- Do you provide a way for users to request that some or all of their data
  is deleted, without deleting the account: yes (Profile, My
  contributions).
- Data shared with third parties: In-app search history and Approximate
  location, to IGN (see below). Hetzner hosts the servers as a service
  provider, which the form does not count as sharing.
- Independent security review: no. Families policy: not applicable
  (audience 18 and over).

Data types, in the form's categories. Every collected type is optional:
browsing and search work without an account and without the location
permission, directions need the location permission but no account, and
none of the stored data exists before the first contribution or
favourites sync.

| Category | Data type | Collected | Shared | Processed ephemerally | Required or optional | Purposes |
|---|---|---|---|---|---|---|
| Location | Approximate location | yes | yes | yes | optional | App functionality |
| Location | Precise location | yes | no | no | optional | App functionality, Fraud prevention, security, and compliance |
| Personal info | Name | yes | no | no | optional | App functionality, Account management |
| Personal info | User IDs | yes | no | no | optional | App functionality, Account management, Fraud prevention, security, and compliance |
| Photos and videos | Photos | yes | no | no | optional | App functionality |
| App activity | App interactions | yes | no | no | optional | App functionality, Fraud prevention, security, and compliance |
| App activity | In-app search history | yes | yes | yes | optional | App functionality |
| App activity | Other user-generated content | yes | no | no | optional | App functionality |
| App activity | Other actions | yes | no | no | optional | App functionality |
| Device or other IDs | Device or other IDs | yes | no | no | optional | Account management, Fraud prevention, security, and compliance |

What each line covers:

- Approximate location: the point of the cheapest fuel list, the device
  position rounded to about 5 km; the region of the first sync, chosen
  from the device position; the ids of the places drawn near the vehicle
  during guidance; the fuel stations of the view, the list of places
  beside the map, the count of the filters and the places along a route,
  each an area widened to a 0.05 degree grid; the map centre on that grid
  sent with each search, which is the device position rounded when the
  map follows the user; nothing stored. Shared: the point of an address
  search goes on to IGN with its text (next line), for App functionality.
- Precise location: the start of each route and of each reroute of a
  guidance, and the route line sent for "On the way", processed for the
  request only; the position of a new place or vending machine, which can
  be the device's own and is kept; the coordinates of the points saved
  in the favourite lists (an address, a bare point, a shop), kept with
  the account once there is one; the position and heading of a road
  report, kept 14 days with the account. The form asks one answer per
  type: since part of it is kept, "Processed ephemerally" is no. Fraud
  prevention covers the road reports, which change the routes only once
  two accounts of level 1 or more agree.
- Name: the pseudonym (generated, editable, public on contributions).
- User IDs: the account id.
- Photos: the photos the user adds to places.
- App interactions: the number of days of use, the last active day, the
  last-use dates of sessions and device keys (trust levels, abuse
  control).
- In-app search history: the text of the search of addresses, of shops
  and services, and of places on a device without places, processed for
  the request only on our servers. Shared: the text of each address
  search, with the map centre on the 0.05 degree grid and without the
  client's address, goes from our server to IGN's Géoplateforme geocoder,
  a French public service that answers under its own terms; we have no
  agreement with IGN on its logs, so the transfer is declared as sharing,
  for App functionality.
- Other user-generated content: reviews, new places, vending machines and
  edits, road reports, notes attached to confirmations and reports,
  favourite list names.
- Other actions: ratings, "Still there?" answers on places, on shops and
  services and on road events, problem and content reports, places saved
  in synced lists, mutes.
- Device or other IDs: the device public key, one per installation.

Not declared, with the reason:

- Personal info, Email address, Phone number, Address, Other info: none
  asked.
- Location through Play Services: the store flavor carries
  `play-services-location` through maplibre_gl. The guidance and the
  route's start force Android's own LocationManager
  (`app/lib/features/navigation/data/location_feed.dart`,
  `forceLocationManager: true`); the map's own location layer creates
  Google's provider only for a high accuracy request, and the app sets no
  `locationEngineProperties` (`app/lib/features/map/presentation/gl_map.dart`;
  maplibre_gl 0.27.1, `LocationEngineFactory.kt`), so MapLibre's default
  engine on Android's LocationManager runs.
- App info and performance (crash logs, diagnostics): none collected; the
  logs stay on the device and reach only an attached debugger
  (`app/lib/main.dart`).
- Translations: the request names a published item, never the text nor
  the reader; the translation kept is the item's, served to every reader.
- Web browsing, installed apps, files, calendar, contacts, messages,
  audio, health, financial: none.
- Android Backup (favourites, settings with the stay dates and the regions
  offered, vehicle, the account id of synced favourites, contributions
  waiting to be sent, road reports included;
  `app/android/app/src/main/res/xml/`): it goes to the user's own Google
  backup (end-to-end encrypted from Android 9; on Android 7 and 8, which
  ignore that condition, the ordinary cloud backup, `backup_rules.xml`)
  and never reaches us. Assumption: the Google page read on 2026-10-06
  (answer/10787469) does not say whether it counts; the privacy page
  discloses it.

Data deletion:

- Whole account: in the app (Profile, Your account, Delete my account,
  Continue, "I understand this is final", Delete the account;
  `app/lib/features/account/presentation/account_pages.dart`) or with the
  recovery code on https://lunaway.net/account/delete
  (`deleteAccountWithRecoveryCode`); the page exists in the six languages
  of the app (`/en/`, `/de/`, `/es/`, `/it/`, `/nl/`), and the app opens
  the one of its language (`AppConfig.sitePage`).
- Some data without deleting the account: Profile, My contributions:
  reviews, ratings, photos, confirmations, answers about shops and
  services, problem reports, place proposals
  (`app/lib/features/community/presentation/contributions_screen.dart`).
  A road report is not deleted on its own: it goes after 14 days.

### Retention and deletion

`delete_account` (`backend/crates/lunaway-db/src/accounts.rs`), in one
transaction, after the deletion is written to the deletion journal
(`backend/crates/lunaway-db/src/deletions.rs`):

- deleted: the account, device keys, sessions, recovery code, favourite
  lists, mutes in both directions, sponsorships (an API feature the app
  has no action for), every photo and its files, ratings without text and
  unpublished reviews, problem reports, content reports filed, answers
  about shops and services, road reports, idempotency keys, the reports
  and moderation entries about the content deleted; the content of every
  unapplied submission (pending, rejected, withdrawn) is emptied;
  moderation queue entries about content that stays keep it with the
  author set to null; a banned account's confirmations are deleted and
  its key hashes kept two years (`banned_keys`);
- kept without author: published reviews with text (text, rating, visit
  date, vehicle) and their translations, confirmations of places (note
  erased) until their two years, applied submissions with their payload
  and position (part of the ODbL places database), the public road
  events (which never carry an account).

Single items (`backend/crates/lunaway-db/src/community.rs`,
`submissions.rs`): a deleted review or photo is gone, except a review
hidden by moderators or reported (its text goes, its stars stop counting,
the row stays for the moderators) and a photo pending, hidden or reported
(its files go, the row stays); a withdrawn proposal stays in the revision history, linked to
the account until the account is deleted, its content emptied 30 days
after the withdrawal.

Daily sweep (`lunaway retention`, 03:40 UTC,
`backend/crates/lunaway-db/src/retention.rs`): problem reports after 90
days, content reports and decided moderation entries a year after the
decision, confirmations after two years (counts kept), the content of
rejected or withdrawn submissions 30 days after the decision, a banned
account's key hashes two years after its deletion, translations whose
original changed or went.

Backups (`infra/files/usr/local/sbin/lunaway-pgdump`,
`lunaway-replica`, `infra/ops/mac/lunaway-ops.sh`): nightly database
dumps, plaintext on the backend's data volume (7), age-encrypted on its
root disk (3, inside Hetzner's 7 daily images) and in its off-site
directory (7), pulled to the ops server (15 days, pruned before and after
each pull) and to the maintainer's Mac (30 days, pruned at each nightly
run and at start-up); deleted photos stay 26 days in the copies. A
deleted account therefore survives in backups about 30 days, longer
only while the Mac is off. The deletion journal (45 days, hourly
encrypted copy, 46 days in the copies, longer on the Mac while it is off) is replayed after a restore
(`lunaway accounts replay-deletions`).

Takedowns (`backend/crates/lunaway-db/src/takedown_journal.rs`): a place
taken down at someone's request is noted in a journal of place ids, date,
a reason code, and keyed hashes of its cells, without name, position or
the text of the request; kept without limit, copied encrypted every hour.

The external community source (`docs/feeds.md`, `docs/data-sources.md`,
`docs/deploy.md` "The external community feed"): its places, reviews
(author pseudonym, vehicle, month), ratings and photos are collected under
its written agreement by a crawler of ours on the ops server, which keeps
its own working state there (a private repository: its retention and the
erasures applied to it are not in this repository, and the privacy page
leaves that line visibly to complete), then pushed to the backend's drop
box and imported, Lunaway a separate controller of its copy; a complete
feed removes the spots it no longer
lists, a line marked deleted removes its spot, a review or photo absent
from its spot's list goes; an author's erasure the partner forwards
deletes their reviews and photos and keeps the SHA-256 of their id
without limit (`source_erasures`); the drop box keeps a feed 4 days. Its
authors are not users of the app; the privacy page tells them how to ask
about Lunaway's copy.

Licences of what users publish: places, vending machines, edits and road
reports ODbL 1.0 (the `community` source, migration 20261006005548);
ratings, reviews and photos CC BY 4.0 (the `community-cc-by` source,
migration 20261006151000). Confirmations, answers and problem reports
are published only as counts and dates.

### When a feature ships, the answers change

| Feature | New datum | Form change |
|---|---|---|
| Map location at high accuracy (`enableHighAccuracy`, or `forceLocationManager` removed) | the store flavor switches to Google's fused provider from `play-services-location` | check Google's disclosure for that library and declare what it collects |
| Address search answered by a geocoder of our own for France too (a self-hosted BAN) | the text no longer leaves our servers | In-app search history: shared no |

## Ready to publish: what the app side delivers

The session that publishes waits for the app side to confirm every item,
each with its evidence (command output, URL, commit).

1. **Build.** `fvm flutter build appbundle --release --flavor store` from a
   tagged commit; signed with the upload key (certificate SHA-256 above);
   `versionCode` above any earlier upload; targetSdk 36 or higher;
   `PAGE_ALIGNMENT_16K`.
2. **Live URLs.** https://lunaway.net/privacy describes what this build
   actually collects; https://lunaway.net/account/delete works;
   https://api.lunaway.net serves the build (the reviewer uses production);
   contact@lunaway.net receives mail.
3. **In the app.** An account deletion path and a privacy policy link.
4. **Data inventory**, for the Data safety form: every datum that leaves the
   device, its destination host, purpose, whether it is optional, retention
   and how it is deleted.
5. **Reviewer access.** Whether trust levels hide features from a fresh
   account, and if so how a reviewer reaches them.
6. **Content rating inputs.** What users publish and who sees it (reviews,
   photos, places), how it is moderated, whether users can message each
   other, whether a user's location is visible to others.
7. **Listing material** in `fastlane/metadata/android/<locale>/` for fr-FR,
   en-US, de-DE, es-ES, it-IT and nl-NL: the full description adjusted to
   the features that ship;
   `changelogs/<versionCode>.txt`; `images/icon.png` (512 x 512, 32-bit
   PNG); `images/featureGraphic.png` (1024 x 500, no alpha);
   `images/phoneScreenshots/` (2 to 8, 9:16, 1080 px or more on the short
   side); tablet screenshots in
   `images/sevenInchScreenshots/` and `images/tenInchScreenshots/` if the
   expanded layout ships. Sizes, order and captions: `docs/screenshots.md`;
   wording rules and the source of each claim: `docs/store-listing.md`.
8. **Store preconditions**, settled on 2026-10-06 with the app side:
   - the name stays. TMview (EUIPO network) lists one mark containing
     "lunaway": LUNAWAY-ART, INPI FR 4466074, classes 35, 41 and 42,
     registered until 2028-07-02, held by a graphic artist. Its class 42
     covers personalised web pages with user profiles and photos, so we do
     not file a mark in class 42; a filing, if ever wanted, covers classes
     9 and 39 only;
   - Lunaway ingests open data (OpenStreetMap, public datasets, open
     content) and its own community's contributions, plus one proprietary
     source under a written agreement with its producer, the external
     community source (`extcom`, `docs/data-sources.md`); its values stay
     out of the ODbL places database and its dumps, and the listing calls
     it "source communautaire externe" without naming it.

## Release procedure

The full path from a green `main` to every store, tags and version numbers
included, is `docs/release.md`; the steps below are the Play part.

1. From `app/`: `fvm flutter build appbundle --release --flavor store`.
2. Check the 16 KB alignment (above) and that the bundle is signed with the
   upload key.
3. First release only:
   - fill the rest of the App content section from the answers above
     (browser), and Data safety (API);
   - upload the bundle to the internal track as a `draft` release (API),
     then roll it out in the Console (browser).
4. Push the listing and images from `fastlane/metadata/android/` (API).
5. The closed test of 12 testers over 14 days applies to personal accounts
   created after 2023-11-13
   (support.google.com/googleplay/android-developer/answer/14151465); the
   AxiomTeam account is an organization and goes straight to production.
6. Production: create the release on the production track (API), commit
   with the changes sent for review, then follow the review in the Console.

End state: the release shows "In review" or "Published" on the production
track, the listing matches `fastlane/metadata/android/` in its six locales, and
the App content section has no pending declaration.
