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
category Travel and Local, contact details. The store listing text of both
locales is pushed. The rest is a draft, to confirm against the MVP before
the first submission.

Saved as drafts in the Console, not submitted: the content rating
questionnaire (category "all other app types", answers below) and the Data
safety form up to step 4. The Data safety draft predates the inventory
below and differs from it: it declares precise location as ephemeral (it
is now kept, with a new place) and lacks Device or other IDs and App
interactions. Correct it from the inventory before submitting. Both forms
are submitted at release, once the build confirms these answers.

Decisions from the app side (2026-10-06) behind those answers:

- Users can hide every contribution of an author (a mute synced with the
  account) and report a review, a photo or a place.
- Place and town search run on the device, with no third-party geocoder:
  no "search history".
- Every build uses the self-hosted basemap on tiles.lunaway.net; the app
  has no other tile host (`app/lib/core/config/app_config.dart`,
  `tool/allowed_hosts.txt`).
- The pseudonym starts generated, the user can edit it, and it is public on
  their contributions: declared as "name".
- A user can delete any single review, photo, place edit or confirmation of
  their own without deleting the account. The deletion page explains both
  paths.

- **App access** ("Informations de connexion"): filed as "no restricted
  part", because the Console requires it before the target audience. At
  release, switch it to restricted: browsing needs no account, but a fresh
  account starts at trust level 0 (favourites, ratings, confirmations);
  written reviews and photos need level 1 and new places level 2
  (`backend/crates/lunaway-domain/src/community/trust.rs`). The demo
  account comes from `sudo lunaway-admin accounts create-demo --level 2`
  on the backend (`docs/deploy.md`, "lunaway-admin"), which prints a
  recovery code; the reviewer enters it in Profile, "Recover my account".
  The code goes into the Console field only, never into the repository.
- **Content rating:** users publish reviews, ratings, photos and places,
  all public to every user. Moderation: automatic text rules (links,
  contact details, repetition, a word list;
  `backend/crates/lunaway-domain/src/community/moderation.rs`) hold a text
  for a moderator; a review or photo reported by three trusted accounts is
  hidden until a moderator decides; moderators work the queue from the
  command line; users can report content and hide an author. No user to
  user messaging; users are pseudonymous; no device location is shown to
  others, but the places an author reviewed, photographed or added are
  public under their pseudonym, with the visit date they chose to give
  (`app/lib/features/places/data/graphql/operations.dart`: `authorId`,
  `visitedAt`); no purchases.
- **Data safety:** the answers are in "Data safety inventory" below.

## Data safety inventory

Rewritten on 2026-10-06 from the code in the working tree: the backend at
69f9c98, and the app with its account, community and favourites sync code
not yet committed at that date (`app/lib/features/account/`,
`app/lib/features/community/`,
`app/lib/features/favorites/data/favorites_sync.dart`). Check it again
against the tagged build before submitting: the table at the end lists
what changes when a feature ships. `docs/app-store.md` derives the App
Store privacy label and `app/ios/Runner/PrivacyInfo.xcprivacy` from this
section; the privacy page (`tool/site/src/pages/*/privacy.html`) describes
the same facts. Change them together.

### What leaves the device

The app talks only to our hosts, over HTTPS
(`app/lib/core/config/app_config.dart`, `tool/allowed_hosts.txt`). It has
no third-party SDK for analytics, crash reports or ads.

| Datum | Sent when | Kept on the server | Source |
|---|---|---|---|
| Region of the place sync | at launch and on resume, with or without account | nothing: a fixed box around metropolitan France, never a position | `app/lib/features/places/data/sync/sync_service.dart`, `app/lib/core/geo/geo.dart` |
| Map area viewed | basemap tiles from tiles.lunaway.net | nothing; the access log masks tile coordinates | `infra/caddy/Caddyfile` (`access_log`) |
| Place viewed | opening a place sheet loads its photos and reviews; with an account the request carries the session token (to show the user's own review) | nothing about the place; the session's last-use date moves at most once an hour, and the account's days of use count the day | `app/lib/features/places/application/places_providers.dart`, `backend/crates/lunaway-api/src/auth.rs`, `backend/crates/lunaway-db/src/accounts.rs` |
| Device public key (P-256) and signatures | first contribution or favourites sync, then each sign-in | the public key, its RFC 7638 thumbprint, creation and last-use dates (`device_keys`) | `app/lib/features/account/data/account_service.dart`; `backend/migrations/20261006005548_accounts_and_contributions.sql` |
| Pseudonym | drawn by the server at account creation, editable, public | `accounts.pseudonym` | same migration; `backend/crates/lunaway-auth/src/pseudonym.rs` |
| Account record | derived by the server | id, trust level, granted level, days of use, last active day, creation date, moderation removals, ban date and reason | same migration; `20261006005551_moderation_removals_and_reporters.sql` |
| Session | each sign-in | SHA-256 of the token and its dates; expires 60 days after last use, purged every hour | `backend/crates/lunaway-api/src/config.rs`, `src/main.rs` |
| Recovery code | the user makes a recovery card | the argon2id hash only | `backend/crates/lunaway-api/src/mutation.rs` |
| Rating, review (text, visit date, vehicle kind, language) | the user rates or writes | `reviews` | `app/lib/features/community/data/community_operations.dart` |
| Photo | the user adds one | two WebP files re-encoded from the pixels (2048 and 512 px), no metadata; the original is not kept | app: `app/lib/features/community/data/photo_prepare_io.dart` resizes to 2560 px and clears EXIF before upload; server: `backend/crates/lunaway-media/src/pipeline.rs` |
| "Still there?" confirmation | the user answers | `confirmations`: status and an optional note for moderators; no position sent or kept | `community_operations.dart`; `backend/migrations/20261006090000_confirmations_without_presence.sql` |
| Problem report, content report | the user reports | `issue_reports`, `content_reports`: kind or reason, optional note | 20261006005548 |
| Route request: start, destination, stops, the vehicle's dimensions, heading | the user asks for a route, and during guidance each new route (off the route, a closure ahead, a stop added or removed) and the route through a stop priced before it is confirmed | nothing: a POST body, and the access log keeps the method and path only | `app/lib/features/navigation/data/route_operations.dart`, `route_service.dart`; `backend/crates/lunaway-api/src/lib.rs` |
| Points of a route, for its fuel stations | the user opens the fuel list of a route | nothing; five points of the route ahead, each rounded to a hundredth of a degree (about a kilometre) | `app/lib/features/navigation/data/fuel_stations_api.dart` |
| Road events of the guidance | during guidance, at the start and every three minutes | nothing; the request carries no position | `app/lib/features/navigation/data/road_events_api.dart` |
| New place, place edit | the user submits | `place_submissions`: the payload, with the position the user confirms in the form (a long press, or the map centre, which after "locate me" is the device's own position), linked to the account and device key | `app/lib/features/map/presentation/map_screen.dart`, `locate_flow.dart`, `app/lib/features/community/presentation/place_form.dart`, `backend/crates/lunaway-db/src/submissions.rs` |
| Favourite lists | after the first sync | list names and place ids (`favorite_lists`, `favorite_items`) | `favorites_sync.dart` |
| Muted authors, sponsorships | the user mutes (sponsoring exists in the API only, the app has no action for it yet) | `muted_authors`, `account_endorsements` | 20261006005548 |
| Client address | every request | not stored: rate limits count per IPv4 address or IPv6 /64 in memory, reset by a restart | `backend/crates/lunaway-api/src/{rate,quota,client}.rs` |
| Request line and headers | every request | access log: date, method, path without query string, status, User-Agent and Accept-Language, IP truncated to /16 (IPv4) or /32 (IPv6), photo paths and tile coordinates masked; the file rolls at 50 MiB and rolled files go after 14 days, so the live file can hold older lines; system journal, one month at most; both also sit in Hetzner's 7 daily images of the root disk | `infra/caddy/Caddyfile` (`roll_size`, `roll_keep_for`), `infra/files/etc/systemd/journald.conf.d/lunaway.conf`, `docs/deploy.md` |

The device position reaches the server in one case only: as the position
of a new place, when the user centres the map on themselves ("locate me")
and adds a place there. No other request carries it: no directions,
"around me" or server search request exists in the app (search runs on
the device, `app/lib/features/places/data/drift_places_repository.dart`),
and a confirmation carries none. Not sent either: search text, contacts,
e-mail, phone number, crash data. The position also goes, on the device,
to another app the user opens for directions when that app takes a start
point (`app/lib/core/navigation_apps.dart`).

### Form answers

Data collection and security:

- Collects or shares required user data: yes.
- Encrypted in transit: yes (HTTPS only; the debug build alone allows
  cleartext, to the emulator host).
- Users can request deletion: yes.
- Account creation: yes, method "other" (a key pair on the device, no
  user name, password or e-mail); deletion URL
  https://lunaway.net/account/delete.
- Shared with third parties: nothing. Hetzner hosts the servers as a
  service provider, which the form does not count as sharing.

| Category, type | Collected | Ephemeral | Optional | Purposes |
|---|---|---|---|---|
| Personal info, Name (the pseudonym, a nickname) | yes | no | yes | App functionality, Account management |
| Personal info, User IDs (account id) | yes | no | yes | App functionality, Account management, Fraud prevention, security and compliance |
| Device or other IDs (the device public key, one per installation) | yes | no | yes | Account management, Fraud prevention, security and compliance |
| Photos and videos, Photos | yes | no | yes | App functionality |
| App activity, Other user-generated content (reviews, new places and edits, report notes, list names) | yes | no | yes | App functionality |
| App activity, Other actions (ratings, confirmations, places saved in synced lists, mutes, sponsorships) | yes | no | yes | App functionality |
| App activity, App interactions (days of use, last-use dates of sessions and devices) | yes | no | yes | App functionality (trust levels), Fraud prevention, security and compliance |
| Location, Precise location (the position of a new place, which can be the device's own) | yes | no | yes | App functionality |

Optional: the app works without any of it, since browsing needs no account
and none of these data exist before the first contribution or favourites
sync. Not declared, with the reason:

- Location, Approximate location: the basemap tiles requested after
  "locate me" cover the area around the device (zoom 12); nothing is
  stored and the access log keeps the zoom level only. Read as a map
  view; declare Approximate location, processed ephemerally, if Google
  reads it otherwise.
- Location through Play Services: the store flavor carries
  `play-services-location` through maplibre_gl, which creates Google's
  provider only at high accuracy; the app asks for none (`gl_map.dart`,
  default `enableHighAccuracy: false`), so Android's own LocationManager
  runs. See "When a feature ships".
- In-app search history: search runs on the device.
- Crash logs, Diagnostics: none collected.
- Web browsing: none.
- Android Backup (favourites, settings, vehicle, the account id of synced
  favourites, contributions waiting to be sent; `app/android/app/src/main/res/xml/`):
  it goes to the user's own Google backup (end-to-end encrypted from
  Android 9; on Android 7 and 8, which ignore that condition, the ordinary
  cloud backup, `backup_rules.xml`) and never reaches us. Assumption: the
  Google page read on 2026-10-06
  (answer/10787469) does not say whether it counts; the privacy page
  discloses it.

Data deletion:

- Whole account: in the app (Profile, Your account, Delete my account,
  `app/lib/features/account/presentation/account_pages.dart`) or with the
  recovery code on https://lunaway.net/account/delete
  (`deleteAccountWithRecoveryCode`).
- Some data without deleting the account: yes, in the app (Profile, My
  contributions: reviews, ratings, photos, confirmations, problem reports,
  place submissions; `contributions_screen.dart`), described on the same
  page.

### Retention and deletion

`delete_account` (`backend/crates/lunaway-db/src/accounts.rs`), in one
transaction:

- deleted: the account, device keys, sessions, recovery code, favourite
  lists, mutes in both directions, sponsorships, every photo and its files,
  ratings without text, unpublished reviews, problem reports, content
  reports filed, pending proposals, point-of-interest confirmations, road
  event reports (cascade, migration 20261006120000, not committed on
  2026-10-06); moderation queue entries about content that stays keep it
  with the author set to null;
- kept without author: published reviews with text (text, rating, visit
  date, vehicle), confirmations (note erased), processed submissions
  (applied, accepted, rejected, withdrawn; applied ones are part of the
  ODbL places database).

Single items (`backend/crates/lunaway-db/src/community.rs`,
`submissions.rs`): a deleted review or photo is gone, unless it was held
or reported, in which case its text or files go and a row stays for the
moderators; a withdrawn proposal stays in the revision history, linked to
the account until the account is deleted.

Backups (`docs/deploy.md`, "Backups and restore"): nightly database dumps,
plaintext on the backend (7 on the data volume, 3 on the root disk inside
Hetzner's 7 daily images), age-encrypted copies on the ops server (14
days) and on the maintainer's Mac (29 days); a deleted photo leaves every
copy within 29 days. A deleted account therefore survives in backups 30
days at most. Open point: a restored dump brings back the accounts deleted
after it (no deletion journal yet).

Licences of what users publish: places and edits ODbL 1.0 (the `community`
source, migration 20261006005548); reviews CC BY 4.0 (doc of `review` in
`mutation.rs`); photos CC BY 4.0 on the site only. Open point: the API
reports reviews and photos under the `community` source, whose licence is
ODbL. Confirmations and problem reports are published only as counts and
dates.

### When a feature ships, the answers change

| Feature | New datum | Form change |
|---|---|---|
| In-app directions (`route`) | origin (often the GPS fix), destination, stops, heading, vehicle dimensions; nothing stored, the API logs no position (`backend/crates/lunaway-api/src/routing_query.rs`); Valhalla's own log of slow requests is not checked yet (`infra/routing/valhalla.json` has no logging settings; look at `journalctl -u valhalla` after a slow route) | Location, Precise location: also processed ephemerally for this use |
| Map location at high accuracy (`enableHighAccuracy` or a high priority in `gl_map.dart`) | the store flavor switches to Google's fused provider from `play-services-location` | check Google's disclosure for that library and declare what it collects |
| "Around me" layer (`nearbyPois(at:)`, `searchPois(near:)`) | the device position when a query is centred on it, not stored | same as directions |
| Point confirmations (`confirmPoi`), vending machines (`addVendingMachine`) | answers kept one year; machines kept like new places | already covered by Other actions and Other user-generated content |
| Server search in the web app | text and map centre, not stored | none for the Play form (the web app is not in it) |
| Road event reports (`reportRoadEvent`, `clearRoadEvent`: in the API of the working tree, not called by the app) | a precise position, heading and measured value, linked to the account, kept 14 days | already covered by Precise location; add the 14 days to the privacy page |

### Corrections to the first draft

The first inventory (2026-10-06, before the code) had nine gaps, listed by
the site report. Each is fixed above:

1. Presence: dropped from `confirm` and from the database; confirmations carry no position.
2. Positions sent: only the position of a new place, which can be the device's own (declared as precise location). Directions and the web search come later; photo GPS is cleared on the device before upload.
3. Licences: ODbL for places and edits, CC BY 4.0 for reviews and photos; confirmations are not published one by one.
4. Account deletion: the full list of `delete_account`.
5. Missing data: reports, mutes, sponsorships, days of use, device and session dates, recovery code hash, ban reason.
6. Account creation: at the first contribution or favourites sync, never at launch.
7. Photos: every metadatum goes, on the device and on the server; the original is not kept.
8. Logs: 14 days for the access log, a month at most for the journal, User-Agent and language kept.
9. Android backup: the user database only, end-to-end encrypted from Android 9 (Android 7 and 8 follow their own settings); disclosed on the privacy page.

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
7. **Listing material** in `fastlane/metadata/android/<locale>/` for fr-FR and
   en-US: the full description adjusted to the features that ship;
   `changelogs/<versionCode>.txt`; `images/icon.png` (512 x 512, 32-bit
   PNG); `images/featureGraphic.png` (1024 x 500, no alpha);
   `images/phoneScreenshots/` (2 to 8, 9:16, 1080 px or more on the short
   side); tablet screenshots in
   `images/sevenInchScreenshots/` and `images/tenInchScreenshots/` if the
   expanded layout ships. Sizes, order and captions: `docs/screenshots.md`;
   wording rules and the variants for features not shipped yet:
   `docs/store-listing.md`.
8. **Store preconditions**, settled on 2026-10-06 with the app side:
   - the name stays. TMview (EUIPO network) lists one mark containing
     "lunaway": LUNAWAY-ART, INPI FR 4466074, classes 35, 41 and 42,
     registered until 2028-07-02, held by a graphic artist. Its class 42
     covers personalised web pages with user profiles and photos, so we do
     not file a mark in class 42; a filing, if ever wanted, covers classes
     9 and 39 only;
   - Lunaway ingests open data only (OpenStreetMap, French public
     datasets) plus its own community's contributions; no proprietary
     database is crawled (decision of 2026-10-06).

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
track, the listing matches `fastlane/metadata/android/` in both locales, and
the App content section has no pending declaration.
