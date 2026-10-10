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
| App Store, iPad 13-inch | 1 to 10 | 2064 x 2752 or 2048 x 2732 (portrait), landscape too; required because the app runs on iPad (`TARGETED_DEVICE_FAMILY = "1,2"`, `app/ios/Runner.xcodeproj/project.pbxproj`) | 8, landscape 2752 x 2064 |

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
the app's pass 7 left it on 2026-10-07 (fourteen scenes; 93ba876 has the
first ten). The tour stands on the lake shore at Annecy, opens the page of
a motorhome area on the lake (Aire de Camping Car Doussard,
`01a10f0e-2a68-7650-bd10-132ddc5c7e20`), computes a route for a
low-profile motorhome on diesel, then drives a simulated position on the
N201 at Chambéry into a danger zone of the French list. It prints
`SHOT <tag>-<nn>-<scene>` in this order: 01, 02, 03, 04, 05, 11, 06, 12,
07, 08, 13, 09, 10, 14. Captions sit in the top band; the French text
follows the app's own words.

| # | Scene (`SHOT` name) | What the frame shows | Caption fr | Caption en |
|---|---|---|---|---|
| 1 | `01-map` | the map around the lake shore with the user's dot (Android), the chips under the search, the places nearby | Aires, parkings et campings sur une carte | Motorhome areas, car parks and campsites on one map |
| 2 | `02-place` | the area's page: its overnight card, actions | La nuit indiquée sur chaque fiche | The overnight status on every page |
| 3 | `03-place-around` | the same page further down: what is around, the coordinates | Commerces, services et coordonnées du lieu | Shops, services and coordinates |
| 4 | `04-filters` | the filters sheet | Filtrez par type, nuit, services et hauteur | Filter by kind, overnight, services and height |
| 5 | `05-route` | the route preview for the low-profile motorhome, alternatives, Fuel button | Un itinéraire pour votre gabarit | A route that fits your vehicle |
| 6 | `06-fuel` | "Moins cher autour de moi", diesel prices | Le carburant le moins cher autour de vous | The cheapest fuel around you |
| 7 | `07-favorites` | four real places of the area and a trip list ("Alpes 2027" / "Alps 2027") | Vos lieux rangés en listes | Your places, in lists |
| 8 | `08-offline` | the offline maps | Cartes hors ligne par région | Offline maps by region |
| 9 | `09-profile` | the profile without an account | Réglages, véhicule, compte sans e-mail | Settings, vehicle, an account without e-mail |
| 10 | `10-vehicle` | the vehicle editor | Le profil de votre véhicule | Your vehicle's profile |
| 11 | `11-fuel-route` | fuel along the route: price, detour, price with the detour, Add | Les stations sur le trajet, détour compris | Stations along the route, detour included |
| 12 | `12-fuel-trend` | a station's page: the diesel prices of the last days | L'évolution des prix d'une station | A station's price trend |
| 13 | `13-regions` | "Quels lieux garder sur cet appareil ?", regions of France | Choisissez les régions à garder | Choose the regions to keep |
| 14 | `14-guidance` | guidance: "Zone de danger dans 360 m" with the list's source and date, the 70 limit beside the speed | Un guidage qui prévient, zones de danger en France | Guidance that warns you, danger zones in France |

Play takes 8 phone images: 1, 2, 5, 14, 11, 4, 13, 7 is the order that
puts the shipped novelties first. The App Store takes ten: the same, then
6 and 10. Tablets take 1, 2, 4, 5 and 11 in the expanded layout.

The final images are in `plan/screenshots/final/` (maintainer's copy,
index in its `README.md`): `android-phone/` (fr light, fr dark, en
light), `android-tablet/` (fr light), `ios/` (fr light, 1320x2868, no
blue dot: the simulator's permission prompt cannot be closed by a test),
`web/`. The site (`tool/site/build.py`, `SHOTS`, `SCREENS`,
`SHOT_SOURCES`) reads scenes 1, 2, 5, 14 and 4 from `android-phone/` in
light, fr and en; its German, Spanish, Italian and Dutch pages show the
English set (`SHOT_LANG`) until their own are captured.

**Six locales, two captured.** The listing ships in fr-FR, en-US, de-DE,
es-ES, it-IT (`it` on the App Store) and nl-NL, and the store images of
2026-10-07 exist in French and English only, taken before the guidance
gained its notices, maneuver icons, voice modes, "On the way" and road
reports. Before an upload: the tour again on the release build, in the
six languages (`LUNAWAY_TOUR_LOCALE`), with the captions of
`store_captions.json` in each; the shots of `plan/screenshots/langues/`
come from the demo mode and serve none of the stores.

**Brands in the frames.** Scenes 3, 6, 11 and 12 show shop and fuel
station names and a station's website as the data gives them (read on
the fr light set on 2026-10-07). The Play rule above forbids a
third-party brand in listing images: leave these scenes out of the Play
and App Store sets, or blur the names, before upload.

The tour sends no contribution: a review or photo shown on a page is
already on the place; check it is ours (the demo account's) or crop it
out.

## Content of the frames

- **Real data from production** (`capture.py --api`), never the demo mode:
  demo places carry "(démo)" in their names
  (`app/lib/features/places/data/demo/demo_places.dart`).
- **Community content.** The tour writes none; a review or photo shown in
  scenes 2 and 3 must be the store demo account's
  (`lunaway-admin accounts create-demo --level 2`, `docs/deploy.md`), with
  photos we took, or be cropped out. No other user's pseudonym, text or
  photo appears in an image.
- **Position.** The simulated position is a public spot near the chosen
  place (the lake shore at Annecy), never a home.
- **No third-party brand.** Scenes where the basemap shows a shop or
  fuel brand at street zoom are reframed; the directions sheet, which names
  other navigation apps, is never shown.
- **Status bar.** Clock 09:41, full battery, full signal: Android demo
  mode (`adb shell settings put global sysui_demo_allowed 1`, then the
  `com.android.systemui.demo` broadcasts `clock -e hhmm 0941`, `battery -e
  level 100 -e plugged false`, `network -e wifi show -e level 4`, and for
  scene 6 `network -e airplane show`); iOS `xcrun simctl status_bar
  <udid> override --time 9:41 --batteryState charged --batteryLevel 100
  --wifiBars 3 --cellularBars 4`.
- **Theme and clock.** The automatic theme follows the sun at the last
  position (`app/lib/core/sun/sun_times.dart`): force light or dark per
  scene through the profile setting, not by the hour of the run.
- **Vehicle profile**: a low-profile motorhome, 2.90 m high, 2.35 m wide,
  7.20 m long (the low-profile preset of
  `backend/crates/lunaway-domain/src/routing/vehicle.rs`); 3.30 m high for
  the directions scene, so the 3.20 m bridge is avoided.

## Script spec for `app/tool/screens/`

Goal: one command per store and locale writes the final images where
fastlane reads them, with exact sizes and no manual retouching.

1. **Tour.** `app/integration_test/store_tour_test.dart` exists: it
   prints `SHOT <tag>-<nn>-<scene>` for the scenes above,
   reads `LUNAWAY_TOUR_LOCALE`, `LUNAWAY_TOUR_THEME` and `LUNAWAY_TOUR_TAG`,
   sets the vehicle, the filters and the favourite lists, asks the host
   for the location permission (`GRANT LOCATION`), runs without an
   account, and puts the device's vehicle, filters, language and theme
   back at the end. Not built yet: a subset of scenes, the network cut for
   an offline scene, the demo account.
2. **Devices**, added to `capture.py` as named profiles (`--profile`):

   | Profile | Device | Screen for the run |
   |---|---|---|
   | `play-phone` | Android emulator | `wm size 1080x1920`, `wm density 420` (compact layout) |
   | `play-7in` | same emulator | `wm size 1080x1920`, `wm density 270` (640 dp wide, medium layout) |
   | `play-10in` | same emulator | `wm size 2560x1440`, `wm density 320` (1280 dp wide, expanded layout) |
   | `ios-6.9` | simulator "iPhone 17 Pro Max" or "iPhone 16 Pro Max" | native; the run checks the image is 1320 x 2868 |
   | `ios-6.5` | simulator "iPhone 14 Plus" | native, 1284 x 2778 |
   | `ipad-13` | simulator "iPad Pro 13-inch (M4)" in landscape | native, 2752 x 2064 |

   The Android store flavor is used (`--flavor store`), as the existing
   Android path does.
3. **Captions.** `app/tool/screens/compose.py` (Pillow) takes a raw shot
   and its caption and writes the final image at the exact store size:
   a band of 16 % of the height at the top in Minuit `#061F43` (light
   scenes) or Clair de lune `#FDF1DB` (dark scenes), the caption centred in
   Fraunces 600 from `app/assets/fonts/fraunces/`, at most two lines; the
   shot scaled to the remaining height, centred, on the band colour. The
   captions come from `app/tool/screens/store_captions.json` (`{"fr":
   {"01-map": "..."}, "en": {...}}`), the table above, so a wording change
   is one file. Output in RGB (no alpha), PNG.
4. **Destinations.**
   - Play: `fastlane/metadata/android/<locale>/images/phoneScreenshots/`,
     `sevenInchScreenshots/`, `tenInchScreenshots/`, named `01-map.png` and
     so on (upload order is the name order).
   - App Store: `fastlane/screenshots/ios/<locale>/`, named
     `<nn>_<profile>_<scene>.png`; `deliver` sorts by name and recognises
     the device class from the size.
5. **Checks the script runs before it exits non-zero:** each image has the
   exact size of its profile; no alpha channel (`PIL.Image.mode == "RGB"`);
   under 8 MB; the count per folder within the store's limits; the run was
   made with `--api`. A last manual pass reads every image for a demo
   name, a third-party brand or someone else's content.

Raw shots go to `data/tmp/screens/` (gitignored); only the composed images
are committed.
