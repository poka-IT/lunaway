# Publishing on the App Store

Who reads this: whoever ships the iOS app. The listing lives in
`fastlane/metadata/ios/` (`docs/store-listing.md`), the screenshots plan in
`docs/screenshots.md`, the release order in `docs/release.md`.

State on 2026-10-10 (`main` at 0c656d30): the project builds unsigned in CI
(`.github/workflows/ci.yml`, job `ios`, `flutter build ios --release
--no-codesign`); no Apple Developer team is set (`DEVELOPMENT_TEAM` absent
from `app/ios/Runner.xcodeproj/project.pbxproj`) and this Mac has no
signing identity. Everything below is ready except what needs the
maintainer's Apple account, gathered in "What only the maintainer does".

| Field | Value | Source |
|---|---|---|
| Bundle id | `legal.p2p.lunaway` | `project.pbxproj` (`PRODUCT_BUNDLE_IDENTIFIER`) |
| Display name | Lunaway | `app/ios/Runner/Info.plist` (`CFBundleDisplayName`) |
| Version, build | `CFBundleShortVersionString` = pubspec name (`0.1.0`), `CFBundleVersion` = pubspec build number (`2`) | `Info.plist`, `app/pubspec.yaml` (`version: 0.1.0+2`) |
| Minimum iOS | 15.0 | `IPHONEOS_DEPLOYMENT_TARGET` |
| Devices | iPhone and iPad | `TARGETED_DEVICE_FAMILY = "1,2"` |
| Languages | French (primary), English, German, Spanish, Italian, Dutch | `CFBundleLocalizations`, `app/lib/i18n/`; listing in `fastlane/metadata/ios/<fr-FR,en-US,de-DE,es-ES,it,nl-NL>/` |
| Category | Travel, then Navigation | `fastlane/metadata/ios/*_category.txt` |
| Price | free, no in-app purchase | |
| URLs | support https://lunaway.net/about, marketing https://lunaway.net/, privacy https://lunaway.net/privacy (the other languages under `/en/`, `/de/`, `/es/`, `/it/`, `/nl/`) | `fastlane/metadata/ios/<locale>/*_url.txt` |

## Review guidelines that bind the app

- **Account deletion, 5.1.1(v).** The app creates an account, so it offers
  deletion inside the app: Profile, "Your account", "Delete my account",
  then "I understand this is final" and "Delete the account"
  (`app/lib/features/account/presentation/account_pages.dart`,
  `app/lib/i18n/en.i18n.json`). It needs a network and a sign-in from the
  last ten minutes, which the app performs itself with the device key
  (`account_service.dart`). The web page https://lunaway.net/account/delete
  does the same with the recovery code.
- **Sign in with Apple, 4.8: not required.** The app offers no third-party
  or social login: an account is a P-256 key pair made on the device, with
  a recovery code (`app/lib/features/account/`). Nothing to add.
- **User-generated content, 1.2.** Reviews, photos and places are public.
  The four required means exist: a filter (automatic text rules that hold
  a text for a moderator,
  `backend/crates/lunaway-domain/src/community/moderation.rs`), reporting
  (every review, photo and place, `contribution_sheets.dart`), blocking
  (mute an author, synced with the account), and published contact
  (contact@lunaway.net). Moderators act from the command line
  (`docs/deploy.md`, "lunaway-admin").
- **Privacy policy, 5.1.1(i).** In App Store Connect and inside the app:
  Profile, About, "Privacy policy" opens https://lunaway.net/privacy in
  French, or the page of the app's language under `/en/`, `/de/`, `/es/`,
  `/it/` or `/nl/` (`app/lib/features/profile/presentation/profile_screen.dart`,
  `AppConfig.sitePage`).
- **Purpose strings.** Location when in use, camera, photo library and
  photo library additions, in English in `Info.plist` and in the six
  `<language>.lproj/InfoPlist.strings` (texts in "App Privacy" below).
- **Background modes, 2.5.4.** `location` and `audio`, for the in-app
  guidance only (`Info.plist`, `UIBackgroundModes`): it starts in the
  foreground with "When In Use", shows the blue indicator while it runs
  (`app/lib/features/navigation/data/location_feed.dart`,
  `showBackgroundLocationIndicator: true`) and stops both at the arrival
  or the end. See "Guidance" below.
- **Metadata, 2.3.** No other app or brand named in the name, subtitle,
  keywords or images (`docs/store-listing.md`).

## App Privacy (the label)

Derived from the Data safety inventory in `docs/play-store.md`, with
Apple's definitions (developer.apple.com/app-store/app-privacy-details,
read 2026-10-06): data is "collected" when it leaves the device and stays
accessible, to the developer or to a third party it goes to, longer than
needed to serve the request in real time. Checked against `main` at
0c656d30 on 2026-10-10.

| Answer | Data types | Purpose |
|---|---|---|
| Data used to track you | none | |
| Data linked to you | Identifiers: User ID (account id and pseudonym, a "screen name"), Device ID (the public key generated per device) | App Functionality |
| | User Content: Photos or Videos; Other User Content (ratings, reviews, "Still there?" confirmations of places, answers about shops and services and about road events, problem, road and content reports, new places, vending machines and edits, favourite lists, mutes) | App Functionality |
| | Usage Data: Product Interaction (days of use, last-use dates of sessions and devices, which feed the trust level) | App Functionality (Apple's definition includes fraud prevention and security) |
| | Location: Precise Location (the position of a new place or vending machine, kept with the account; the coordinates of the points saved in the favourite lists, kept with the account once there is one: `app/lib/features/favorites/data/favorites_sync.dart`; after "Show my position", or when the map opens on the user, the map centre is the device's own position: `app/lib/features/map/presentation/locate_flow.dart`, `map_screen.dart`; the position and heading of a road report, kept 14 days with the account: `app/lib/features/navigation/presentation/road_report_sheet.dart`, `backend/crates/lunaway-db/src/road_events.rs`) | App Functionality |
| Data not linked to you | Search History (the text of an address search) and Coarse Location (the map centre rounded to 0.05 degree sent with it, which is the device position rounded when the map follows the user): our server passes both to IGN's Géoplateforme geocoder, without the client's address or any identifier (`backend/crates/lunaway-api/src/geocode.rs`). Declared because IGN answers under its own terms and its log retention is not known to us; our servers keep nothing of them | App Functionality |

Not collected, apart from the address search above, with the reason:

- Coarse Location on our servers: processed for the request only. The cheapest fuel
  list sends the position or the map centre rounded to 0.05 degree
  (`app/lib/features/poi/application/fuel_feed_providers.dart`), and so
  does the list of places beside the map, which ranks from the position
  when the map shows it (`app/lib/features/map/application/map_state.dart`);
  the fuel layer sends the visible area widened to a 0.05 degree grid
  (`poi_providers.dart`), and so do the list of places beside the map
  (`app/lib/features/map/application/listed_places.dart`), the count of
  the filters and the places along a route on a device without places
  (`app/lib/features/places/data/online_places.dart`); the first region
  synced is chosen from the position, at region scale
  (`app/lib/features/regions/`), and the guidance asks the photos of the
  places drawn near the vehicle by their ids
  (`app/lib/features/navigation/data/place_thumbs.dart`). Nothing is
  stored, the access log keeps no query content and masks pack names
  (`infra/caddy/Caddyfile`, `access_log`).
- Precise Location for routes: the start of each route, the reroutes of a
  guidance and the route line sent for "On the way" (from 2 km past the
  start or ahead of the vehicle, the server dropping 2 km more at each
  end) reach the server and are used for that request only; nothing is
  stored, the API logs per route its timings and outcome, never a
  coordinate (`backend/crates/lunaway-api/src/routing_query.rs`), and the
  routing engine's journal holds none (14 days of `journalctl -u
  valhalla` read on 2026-10-07: no coordinate, no request body). Under
  Apple's definition this adds no type.
- Search History, apart from addresses: online, the search of places,
  towns and shops sends the text and the map centre rounded to 0.05
  degree in one request (offline, a device with regions searches its
  own); neither is stored nor logged, and neither leaves our servers.
- Translations: the request names a published review or description and
  the target language, never the text nor a session
  (`app/lib/features/translation/`); the translation kept belongs to the
  item and serves every reader.
- Contact Info (no e-mail, phone or real name is asked), Diagnostics and
  crash data (none), Browsing History (none), Audio (no microphone).
- Speed cameras and road events: asked by country and by cursor, without
  any position; with the setting of exact positions in France on, the
  request also names France (`exactIn`), which the server neither logs
  nor keeps.

The optional-disclosure exemption is not used: reviews, photos, new
places and road reports are part of the app's main use.

Location purpose strings (`app/ios/Runner/Info.plist` and the six
`app/ios/Runner/<language>.lproj/InfoPlist.strings`; the same two keys,
`NSLocationWhenInUseUsageDescription` and `NSLocationUsageDescription`):

- en: "Lunaway shows your position on the map, sorts the places around
  you and guides you along a route you start, also with the screen off
  while it guides. Your position goes to Lunaway's server to compute a
  route, which keeps nothing of it; rounded to about 5 km, to look for the
  cheapest fuel around you or, when the map follows you, to rank a search;
  and when you add a place where you stand or report a problem on the
  road."
- fr : « Lunaway affiche votre position sur la carte, trie les lieux
  autour de vous et vous guide sur l'itinéraire que vous lancez, écran
  éteint compris pendant le guidage. Votre position part vers le serveur
  de Lunaway pour calculer un itinéraire, qui n'en garde rien ; arrondie à
  environ 5 km, pour chercher le carburant le moins cher autour de vous
  ou, quand la carte vous suit, classer une recherche ; et quand vous
  ajoutez un lieu là où vous êtes ou signalez un problème sur la route. »
- de, es, it, nl: the same sentence in each language, in its
  `InfoPlist.strings`.

macOS (`app/macos/Runner/Info.plist` and its six `InfoPlist.strings`)
guides too, with the window open (no background mode on the Mac): "guides
you along a route you start" / « vous guide sur l'itinéraire que vous
lancez », without the clause about the screen off, the rest the same. The
other strings (iOS only; the Mac app offers no camera):

- camera: "Lunaway uses the camera when you take a photo of a place, or
  of your recovery card to read its code."
- photo library: "Lunaway opens your photos when you choose one to add to
  a place, or the image of your recovery card."
- photo library additions: "Lunaway saves the image of your recovery card
  to your photos when you choose Save Image." (the share sheet's "Save
  Image", `recovery_screens.dart`)

## Privacy manifest

`app/ios/Runner/PrivacyInfo.xcprivacy`, added to the Runner target's
resources in `project.pbxproj` (four lines: file reference, group, build
file, resources phase), and its macOS twin
`app/macos/Runner/PrivacyInfo.xcprivacy`, in the macOS Runner target's
resources. `plutil -lint` passes on both.

- `NSPrivacyTracking` false, no tracking domain.
- `NSPrivacyCollectedDataTypes`: the eight types of the label above, not
  tracking, App Functionality; six linked, Search History and Coarse
  Location not linked. If the API stops sending the point to IGN
  (`geocode.rs`, `ask_ban`), Coarse Location leaves the label and the
  manifests; if the address search of France stops leaving our servers,
  Search History leaves them too.
- `NSPrivacyAccessedAPITypes`, what the app's binaries reach without a
  manifest that declares it (iOS; the macOS manifest declares the first
  two rows, no plugin of the macOS build using the user defaults):

| Category, reason | Who calls it | Evidence |
|---|---|---|
| File timestamp, C617.1 (files inside the app container) | `sqlite3.framework`, built by package:sqlite3 from `app/third_party/sqlite/sqlite3.c`, ships no manifest; `package_info_plus` 10.2.2 reads the creation and modification dates of the app's bundle and ships an empty manifest; the guidance engine of `lunaway_nav` (Rust) links `fstat` (assumption: called on files inside the container only; read in the symbols of a build, not in its code) | `nm -u` on the framework lists `_stat`, `_fstat`, `_lstat`; `FPPPackageInfoPlusPlugin.m` (`NSFileCreationDate`, `fileModificationDate`) |
| Disk space, E174.1 | the same framework: `statfs` and `fstatfs` read whether the volume is read-only and its file system type before SQLite writes a database (`sqlite3.c`, the locking style probe and `unixOpen`, always compiled on Apple platforms); the app reads the free space before an offline download (`AppDelegate.swift`, `volumeAvailableCapacityForImportantUsageKey`) | `nm -u` lists `_statfs`, `_fstatfs` |
| User defaults, CA92.1 | `permission_handler_apple` keeps one flag (`LocationPermissionStrategy.m`; its manifest declares 1C8F.1, the App Group reason); the maplibre_gl plugin, which ships no manifest, keeps a map setting (`MapLibreMapController.swift`) | both linked into the app binary |

E174.1 ("check whether there is sufficient disk space to write files") is
the approved reason closest to SQLite's use; none describes a file system
type check. If App Review questions it, the other way out is a request for
a new reason through Apple's form, since SQLite calls `fstatfs` on every
Apple build whatever its compile options.

Manifests already shipped by the components (read in the pub cache and the
build on 2026-10-06, versions of `app/pubspec.lock`; no hosted iOS or
macOS plugin changed between 93ba876 and 0c656d30):

| Component | Accessed APIs declared |
|---|---|
| Flutter engine (`Flutter.xcframework`, 3.47.6) | file timestamp 0A2A.1 and C617.1, system boot time 35F9.1 |
| MapLibre 6.28.0 (the framework, a Swift package pulled by maplibre_gl) | file timestamp C617.1, system boot time 35F9.1, user defaults CA92.1 |
| maplibre_gl 0.27.1 (the Flutter plugin) | no manifest |
| permission_handler_apple 9.6.2 | user defaults 1C8F.1 |
| flutter_secure_storage_darwin 0.4.3, geolocator_apple 2.3.14, image_picker_ios 0.8.13+9, package_info_plus 10.2.2, pointer_interceptor_ios 0.10.1+1, share_plus 13.3.1, url_launcher_ios 6.4.2, lunaway_nav (local) | none (empty manifests) |
| `objective_c.framework` (package:objective_c 9.6.2) | no manifest; `nm -u` shows no required-reason symbol |

None of them declares collected data or tracking. After any plugin or
Flutter upgrade, rerun the check: build for the simulator, then
`nm -u` on each framework under `Runner.app/Frameworks` and on the app
binary, looking for `stat`, `fstat`, `lstat`, `fstatat`, `getattrlist*`,
`statfs`, `fstatfs`, `statvfs`, `mach_absolute_time`, and the strings
`NSUserDefaults`, `systemUptime`, `NSFileSystemFreeSize`. App Store Connect
reports a missing declaration by e-mail after upload (ITMS-91053).

## Export compliance

What the app does with cryptography:

- HTTPS for every request to our hosts, through `package:http` on
  `dart:io` (`app/lib/core/providers.dart`), whose TLS is the BoringSSL
  inside the Flutter engine, not Apple's TLS. The map tiles go through
  MapLibre's loader, which runs on `NSURLSession`, Apple's TLS (`nm -u` on
  `MapLibre.framework` lists `NSURLSession` and no TLS library).
- ECDSA P-256 signatures over SHA-256, to sign in with the device key,
  computed in Dart (`app/lib/features/account/data/p256.dart`,
  pointycastle): authentication only.
- Secrets at rest in the Keychain (`flutter_secure_storage`), Apple's
  encryption.
- No encryption of user content, no messaging, no VPN, no proprietary
  algorithm.

Apple's table (App Store Connect help, "Export compliance documentation for
encryption", read 2026-10-06): encryption limited to Apple's operating
system needs no documentation; a standard algorithm outside it needs the
French encryption declaration when the app is distributed in France;
proprietary algorithms need a CCATS as well. Before that table, App Store
Connect asks whether the app qualifies for an exemption of Category 5,
Part 2 of the US EAR.

Decision for the maintainer, who answers in App Store Connect:

1. **Exempt (proposed).** The app's encryption serves authentication and
   the protection of its own traffic, and its function is a map, not
   information security. Under that reading the answer is "qualifies for
   an exemption", nothing is uploaded, and `Info.plist` declares it so
   that each build skips the questions. This reading is an assumption on
   the EAR, not legal advice.
2. **Conservative.** TLS runs in BoringSSL, a standard algorithm outside
   Apple's OS: file the French encryption declaration (ANSSI) and upload
   it in App Store Connect; `ITSAppUsesNonExemptEncryption` is then true.

Option 1 is in the code: `app/ios/Runner/Info.plist` and
`app/macos/Runner/Info.plist` declare it after the `CFBundleVersion`
entry (option 2 means turning both to `<true/>`):

```xml
	<key>ITSAppUsesNonExemptEncryption</key>
	<false/>
```

## Age rating

Answers for the questionnaire (App Store Connect, "Age ratings values and
definitions", read 2026-10-06):

| Section | Answer |
|---|---|
| In-app controls: parental controls, age assurance | no, no |
| Capabilities: unrestricted web access | no (links open in the browser; no web view on iOS) |
| Capabilities: user-generated content | yes (reviews, photos, places, all public) |
| Capabilities: social media, messaging and chat | no (no feed, no follow, no message between users) |
| Capabilities: advertising | no |
| Mature themes, medical or wellness, sexuality or nudity, violence | none |
| Chance-based activities (gambling, contests, loot boxes) | none |

App Store Connect computes the rating from these answers. The privacy
page says "Lunaway is meant for adults" and Play declares an audience of
18 and over; the App Store rating describes content, not audience, so the
two do not conflict. Made for Kids: no.

Content rights: the app shows third-party content (open data under ODbL,
Licence Ouverte, CC0, CC BY, NLOD, the French speed camera map reused under
the CRPA; open content under each item's licence: Wikimedia Commons,
Wikipedia under CC BY-SA 4.0, Panoramax, DATAtourisme, Mangrove Reviews;
the external community source's places, reviews and photos under its
written agreement; `docs/data-sources.md`; user content under ODbL and
CC BY 4.0) and has the rights to it: answer yes to "contains third-party
content" and confirm the rights. The agreement's text is kept outside the
repository; whether it covers the translations of its reviews is for the
maintainer to confirm (`docs/data-sources.md`, "Machine translation").

## Review notes and demo account

`fastlane/metadata/ios/review_information/notes.txt` (English, under
4000 characters, measured on 2026-10-10 in `plan/research/95-textes-publication.md`): what the app is, account creation,
trust levels, the demo account steps, deletion path, moderation, location
(routes, guidance in the background, the rounded fuel search, new places,
road reports), speed cameras and limits, voice modes, search and
translation, camera and photos, production servers.

The demo account:

1. On the backend: `sudo lunaway-admin accounts create-demo --level 2`
   (`docs/deploy.md`, "lunaway-admin"). It prints the account id, the
   pseudonym, the level and the recovery code
   (`backend/crates/lunaway-cli/src/main.rs`).
2. In App Store Connect, App Review Information, Sign-in information:
   user name `Recovery code (Profile, Recover my account)`, password the
   printed code. The code never enters the repository or a commit; with
   fastlane, pass it through the environment (`LUNAWAY_REVIEW_CODE`).
3. The same account can serve Play's App access instructions.
4. The code stays valid until a new card is made for that account; make a
   new demo account for each review cycle if one was shared.

Contact fields (first name, last name, phone, e-mail) are the maintainer's
and stay out of the repository except `email_address.txt`
(contact@lunaway.net).

## Guidance

In-app guidance ships in 0.1.0+2 (`app/lib/features/navigation/`), on
every platform: iPhone, iPad, macOS, Windows and the web
(`ferrostar_engine.dart`); only iPhone and iPad guide in the background.

- `Info.plist` (iOS), `UIBackgroundModes`: `location` and `audio`.
- No "Always" authorization and no
  `NSLocationAlwaysAndWhenInUseUsageDescription`: guidance starts in the
  foreground with "When In Use", the location settings ask for
  `automotiveNavigation` and the background indicator
  (`location_feed.dart`, `AppleSettings`), and the feed stops at the
  arrival or the end. The audio session uses ducking for spoken
  instructions and the chime before an alert only
  (`LunawayNavPlugin.swift`); only voices installed on the device speak.
- Review notes: the paragraphs on location and on speed cameras in
  `notes.txt`. Guideline 1.4.4 asks an app never to encourage excessive
  speed: the excess shows as a warning only, no feature ranks speeds, and
  the spoken reminder of the limit is off by default
  (`app/lib/features/navigation/domain/driving_aids.dart`); a danger zone
  coming is a safety alert, said unless the voice is off. The voice has
  three modes, full, alerts only and off
  (`app/lib/features/navigation/domain/route_settings.dart`, `VoiceMode`).
- What the app shows of speed cameras, on the map of a route and during
  guidance, never on the main map: the countries that allow camera
  positions, the camera with its limit; the zone countries, danger zones
  (a stretch of road, never a camera's position or type); France, danger
  zones by default, and the cameras' positions only once the user turns on
  "Position exacte des radars en France" in the settings, whose sentence
  cites R413-15 (decision of the product owner, 2026-10-09, with its
  legal reading in `docs/speed-cameras.md`); nothing in Switzerland,
  Germany, Morocco, Liechtenstein, Monaco, San Marino, the Vatican or a
  country the table does not name. No police check is ever reported.
- Road reports, from the guidance or a point of the map (France, Spain,
  the Netherlands): a
  precise position and heading, kept 14 days with the account, under
  Precise Location and Other User Content in the label above; no police
  check can be reported (`roadReport.intro`).

## What only the maintainer does

1. **Apple Developer Program** membership for AxiomTeam as an organization
   (D-U-N-S number), or as an individual; note the Team ID.
2. **EU trader status** (Digital Services Act) in App Store Connect,
   Business: an organization distributing in the EU declares itself a
   trader, and its address, phone and e-mail then show on the product
   page. Without it the app does not appear in EU storefronts.
3. **Identifier**: register the App ID `legal.p2p.lunaway` (no capability
   needed: no push, no iCloud, no app group).
4. **App record** in App Store Connect: name "Lunaway : aires camping-car"
   (or the English name if the French one is taken), primary language
   French, bundle id above, SKU `lunaway-ios`.
5. **Signing**, the simplest way: open `app/ios/Runner.xcworkspace` in
   Xcode, target Runner, Signing and Capabilities, tick "Automatically
   manage signing", choose the team. Xcode writes `DEVELOPMENT_TEAM` into
   `project.pbxproj`: commit that line (a team id is not a secret).
6. **Build and upload**: from `app/`, `fvm flutter build ipa --release`
   (archive in `build/ios/archive/`, IPA in `build/ios/ipa/`), then upload
   with the Transporter app, or open the archive in Xcode, Organizer,
   Distribute App, App Store Connect. The build appears in TestFlight
   after processing.
7. **App Store Connect API key**, for fastlane: Users and Access,
   Integrations, App Store Connect API, a team key with the App Manager
   role. The `.p8` downloads once: keep it outside the repository (for
   instance `~/.config/lunaway/`, mode 0600; `.gitignore` refuses `*.p8`),
   with its key id and issuer id.
8. **Export compliance** (above), **App Privacy** label, **age rating**,
   **content rights**: answered once in App Store Connect from this file.
9. **Submit** the version for review with the build, the demo account and
   the notes.

## Fastlane, to cut the maintainer's part to two commands

Proposal, not in the repository: `fastlane/Fastfile` and a `Gemfile`
pinning fastlane. Codemagic would add a hosted Mac and a second place
holding the API key; with a Mac at hand it brings nothing.

```ruby
default_platform(:ios)

platform :ios do
  before_all do
    app_store_connect_api_key(
      key_id: ENV.fetch("ASC_KEY_ID"),
      issuer_id: ENV.fetch("ASC_ISSUER_ID"),
      key_filepath: ENV.fetch("ASC_KEY_PATH"),
    )
  end

  # Listing, screenshots, review information; no binary, no submission.
  lane :metadata do
    deliver(
      app_identifier: "legal.p2p.lunaway",
      metadata_path: "./fastlane/metadata/ios",
      screenshots_path: "./fastlane/screenshots/ios",
      skip_binary_upload: true,
      submit_for_review: false,
      force: true,
      app_review_information: {
        demo_user: "Recovery code (Profile, Recover my account)",
        demo_password: ENV.fetch("LUNAWAY_REVIEW_CODE"),
      },
    )
  end

  # The IPA built by `fvm flutter build ipa --release` in app/.
  lane :beta do
    upload_to_testflight(
      ipa: Dir["app/build/ios/ipa/*.ipa"].first,
      skip_waiting_for_build_processing: true,
    )
  end
end
```

Then a release is `fvm flutter build ipa --release` in `app/`,
`fastlane ios beta`, `fastlane ios metadata`, and the submission in App
Store Connect. On the first version App Store Connect has no "What's New"
field; if `deliver` refuses `release_notes.txt` there, move the two files
aside for that upload (assumption, not tried).
