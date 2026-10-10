# Store screenshots

Who reads this: whoever produces the store images, and the agent that
extends `app/tool/screens/` to make them. The listing text and its rules
are in `docs/store-listing.md`.

## What each store takes

Read on 2026-10-06: Google Play, "Add preview assets" (support.google.com/googleplay/android-developer/answer/9866151);
App Store Connect, "Screenshot specifications"
(developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications).

| Store, slot | Count | Accepted | We produce |
|---|---|---|---|
| Play, phone | 2 to 8 | JPEG or 24-bit PNG without alpha, each side 320 to 3840 px, long side at most twice the short; at least 4 of 1080 px or more in 9:16 to be eligible for promotion | 8, portrait 1080 x 1920 |
| Play, 7-inch tablet | up to 8 (4 recommended) | each side 1080 to 7680 px, 9:16 or 16:9 | 6, portrait 1080 x 1920 in the medium layout |
| Play, 10-inch tablet | up to 8 (4 recommended) | same | 6, landscape 2560 x 1440 in the expanded layout |
| App Store, iPhone 6.9-inch | 1 to 10 | 1260 x 2736, 1290 x 2796 or 1320 x 2868 (portrait), JPEG or PNG, no alpha | 10, portrait 1320 x 2868 |
| App Store, iPhone 6.5-inch | 1 to 10 | 1284 x 2778 or 1242 x 2688; required only when 6.9-inch images are missing | none by default; 1284 x 2778 if the 6.9-inch set is ever dropped |
| App Store, iPad 13-inch | 1 to 10 | 2064 x 2752 or 2048 x 2732 (portrait), landscape too; required because the app runs on iPad (`TARGETED_DEVICE_FAMILY = "1,2"`, `app/ios/Runner.xcodeproj/project.pbxproj`) | 8, portrait 2064 x 2752 in the expanded layout |

Play also asks for the icon (512 x 512, 32-bit PNG) and the feature graphic
(1024 x 500, no alpha), already made by `tool/brand/generate.sh` in
`fastlane/metadata/android/<locale>/images/`.

Composition rules, from the Play page: the interface first, especially in
the first three images; a caption only when it says something the image
does not, on 20 % of the height at most; no device frame; no ranking,
award, price or call to action; no third-party logo or brand. The App
Store has no caption rule; the same images serve both.

## The story, in order

The scenes are those of `app/integration_test/store_tour_test.dart`, as
rebuilt on 2026-10-10 for the release images (report 105). The tour stands
on the lake shore at Annecy and prints `SHOT <tag>-<scene>` for each:

| Scene | What the frame shows | Caption fr | Caption en |
|---|---|---|---|
| `01-map` | the map around Annecy and the lake with the user's dot, the places where the night is allowed or tolerated (one filter), the nearest first in the list | Aires, parkings et campings sur une carte | Motorhome areas, car parks and campsites on one map |
| `02-france` | the same filter over France and its neighbours | La France et vingt autres pays d'Europe | France and twenty other European countries |
| `03-place` | the page of Le Belvédère (Annecy): overnight card, rating of the external community source, the photo strip moved to its Wikimedia Commons photos | Une fiche par lieu : nuit, photos et avis | A page per place: overnight, photos and reviews |
| `04-reviews` | the same page further down: a review of another language translated, "Voir l'original" | Les avis des voyageurs, traduits d'un geste | Travellers' reviews, translated with one tap |
| `05-search` | "fromagerie Annecy" in the language of the run: the cheese shops of the town | Un lieu, une adresse ou un commerce | A place, an address or a shop |
| `06-filters` | the filters with "Nuit autorisée" and "Eau" chosen | Filtrez par type, nuit, services et hauteur | Filter by kind, overnight, services and height |
| `07-route` | the preview for the low-profile motorhome to Camping International du Lac d'Annecy (Saint-Jorioz), the places along it drawn as pictograms | Un itinéraire pour votre gabarit | A route that fits your vehicle |
| `08-on-the-way` | "Sur le trajet" of the route to Aire de Camping Car Doussard, "Dormir" chosen: the campsites on the way, detour and Add | Sur le trajet : dormir, eau, courses, carburant | On the way: sleep, water, groceries, fuel |
| `09-guidance` | guidance on the N201 at Chambéry: "Zone de danger" 360 m ahead with the list's source and date, the limit beside the speed | Un guidage qui prévient, zones de danger en France | Guidance that warns you, danger zones in France |
| `10-camera` | guidance on Padua's ring road: "Radar fixe" ahead, its limit and source | Radars fixes là où la loi les autorise | Fixed speed cameras where the law allows them |
| `11-stops` | "Tout le trajet" of the route to Doussard through Sevrier and Duingt, after the first kilometre | Tout le trajet et ses étapes | The whole route and its stops |
| `12-voice` | the profile's guidance settings: the voice's three modes, the limit, "Position exacte des radars en France" off | Voix complète, alertes seulement ou coupée | Full voice, alerts only or off |
| `13-offline` | the offline maps from the top: the places of Auvergne-Rhône-Alpes kept on the device (count, size, updated today), updates over mobile data, then the maps (on the taller iPhone: none kept yet, the region where the user stands suggested) | Cartes hors ligne par région | Offline maps by region |
| `14-regions` | "Quels lieux garder sur cet appareil ?", France unfolded | Choisissez les régions à garder | Choose the regions to keep |
| `15-favorites` | the favourites: a viewpoint saved from the map with a note, the cheese shop of the search, three campsites, a trip list ("Alpes 2027") | Lieux, commerces et points en listes | Places, shops and points in lists |
| `16-vehicle` | the vehicle editor | Le profil de votre véhicule | Your vehicle's profile |

The captions of the six languages are in
`app/tool/screens/store_captions.json`; each uses the app's own words in
its language (`docs/translation-glossary.md`).

Each store takes a set (`PROFILES` in `app/tool/screens/compose.py`):

| Set | Scenes, in order |
|---|---|
| Play, phone (8) | 01, 03, 07, 09, 08, 11, 05, 13 |
| Play, 7-inch (6) | 01, 03, 07, 09, 08, 06 |
| Play, 10-inch (6) | 01, 03, 07, 10, 11, 15 |
| App Store, iPhone 6.9-inch (10) | 01, 03, 07, 09, 08, 11, 05, 13, 15, 12 |
| App Store, iPad 13-inch (8) | 01, 03, 07, 09, 10, 08, 11, 06 |
| Site (raw phone shots) | 01, 03, 07, 09, 06 |

Scenes 02, 04, 14 and 16 stand in no store set. In 02, over France, the
list sorted by distance opens on places of Vesdun (Cher), near the map's
centre, 294 km from the user whom the map shows near Annecy (shots of
2026-10-10; the cause is not traced). In 04 the review cards carry their
authors' pseudonyms ("Content of the frames"). 14 and 16 show screens the
other scenes already cover (the regions kept, the vehicle); they serve the
site and the docs.

The six languages are captured, in the light theme. The images of a
release go to `fastlane/metadata/android/<locale>/images/` and
`fastlane/screenshots/ios/<locale>/`; the raw shots, the review sheets and
the index stay in the maintainer's `plan/screenshots/publication/`.

## Content of the frames

- **Real data from production** (`--api https://api.lunaway.net`), never
  the demo mode: demo places carry "(démo)" in their names
  (`app/lib/features/places/data/demo/demo_places.dart`).
- **No account.** The tour sends no contribution and stops, before any
  change, on a device with an account: its favourites would go to the
  account's lists. What it adds to the favourites is taken out at its end.
- **Community content.** The store sets show a place's rating and its
  count of reviews (public content of the external community source),
  never a review card: a card carries its author's pseudonym, so scene
  04 stays out of every set. The external source's photos are
  recognisable by their badge: the place's scene moves the photo strip to
  the photos of an open source (Wikimedia Commons), and the route and
  guidance maps draw the places as pictograms (`GuidanceLook.pictograms`),
  whose photos would be the external source's. The list of the places,
  on the map scene of the large layouts (10-inch, iPad), shows under each
  place the first words of its description by the external source
  ("Externe · ..."), as the app does.
- **No third-party brand.** The search is a kind of shop whose results
  carry no brand (cheese shops of Annecy); fuel stations, whose names are
  brands, are left out of every scene. The directions sheet, which names
  other navigation apps, is never shown.
- **Speed cameras.** In France, zones only: the tour turns "Position
  exacte des radars en France" off (the default) and puts the user's
  choice back at the end. Camera points show in Italy, where the law
  allows them (`docs/speed-cameras.md`).
- **Voice.** The tour's voice is a silent one every language has, so the
  guidance shows its full mode without the notice of a voice to install
  (an emulator has few voices).
- **Position.** The simulated position is a public spot (the lake shore
  at Annecy), never a home; the emulator gets it through a test provider,
  the simulator through `simctl location`, and the permission is granted
  by the host (`pm grant`, `simctl privacy`).
- **Status bar.** Full battery, full Wi-Fi, no notification icon, and the
  clock of the moment of each shot, so that an arrival time or a stop's
  time in the frame agrees with it (a fixed 09:41 would not), in 12 hours
  in English and 24 in the other languages: Android demo mode set after
  the screen size (set before, a tablet draws its Wi-Fi twice) and the
  device's hour format for the run, `simctl status_bar` on iOS
  (`capture.py --status`). The iPhone may show the arrow of a position in
  use beside the clock.
- **Theme.** Forced light through the profile setting, whatever the hour.
- **Vehicle profile**: a low-profile motorhome on diesel (the preset of
  `backend/crates/lunaway-domain/src/routing/vehicle.rs`).

## How the images are made

1. **Tour.** `app/integration_test/store_tour_test.dart` reads
   `LUNAWAY_TOUR_LOCALE`, `LUNAWAY_TOUR_THEME`, `LUNAWAY_TOUR_TAG` and
   `LUNAWAY_TOUR_ONLY` (a comma-separated list of scenes to take again).
   A scene that fails prints `SCENE FAILED <name>` and the tour goes on
   from the map; the last line says `TOUR DONE all scenes` or names the
   failures. It keeps Auvergne-Rhône-Alpes on the device for the run;
   at the end it takes out the favourites it added and puts the vehicle,
   filters, language, theme, guidance settings, driving aids and regions
   kept back, each on its own, so that one failing leaves the others.
2. **Build of the release.** `tool/screens/capture.py --release` builds
   the tour as the app's entry point and launches it like the app: on
   Android a release build (`flutter build apk --release --flavor store
   -t`, application id `legal.p2p.lunaway.shots`, debug key) read from
   logcat; on the iOS simulator, which runs no release build, a debug
   build read from the simulator's log. `--app` reuses a build for
   another device of the same platform and language.
3. **Devices.**

   | Profile | Device | Screen for the run |
   |---|---|---|
   | `play-phone` | Android 15 emulator (API 35, google_apis arm64) | `--size 1080x1920 --density 420` (compact layout) |
   | `play-7in` | same emulator | `--size 1080x1920 --density 270` (640 dp wide, medium layout) |
   | `play-10in` | same emulator | `--size 2560x1440 --density 320` (1280 dp wide, expanded layout) |
   | `ios-6.9` | simulator iPhone 17 Pro Max (iOS 26.5) | native 1320 x 2868 |
   | `ipad-13` | simulator iPad Pro 13-inch (M5) | native portrait 2064 x 2752, the expanded layout (1032 points wide); the simulator stayed upright when the tour asked for landscape (`SystemChrome.setPreferredOrientations`, 2026-10-10) and `simctl` has no rotation, so the iPad set is portrait |

4. **Captions and destinations.** `app/tool/screens/compose.py
   --profile <profile> --lang <lang> --raw <shots>` takes the raw shots of
   one run, adds the caption in a band of 16 % of the height (Minuit
   `#061F43`, Fraunces 600 in Clair de lune, two lines at most), scales
   the shot to the rest, and writes the store's set:
   `fastlane/metadata/android/<locale>/images/{phone,sevenInch,tenInch}Screenshots/<nn>-<scene>.jpg`
   and `fastlane/screenshots/ios/<locale>/<nn>_<profile>_<scene>.jpg`
   (the `screenshots_path` of the `deliver` lane, `docs/app-store.md`).
   It checks the size, the absence of alpha, the 8 MB limit and the count,
   and exits non-zero otherwise.
5. **Review.** Every image is read before an upload: a cut text, a
   loading state, an absurd value, the status bar, a brand, someone
   else's content.

The feature graphic of each locale (1024 x 500, the tagline in its
language) and the 512 px icon come from `tool/brand/build_sources.py` and
`tool/brand/generate.sh`.

The site (`tool/site/build.py`) takes scenes 01, 03, 07, 09 and 06 of the
phone in each of the six languages (`SHOT_SOURCES`, `LUNAWAY_SHOTS_DIR`).
