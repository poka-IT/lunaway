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

Eight scenes for the build of 2026-10-06, then two that replace scenes 4
and 5 when directions and the "around me" layer ship. Captions sit in the
top band; the French text follows the app's own words.

| # | Scene | What the frame shows | Caption fr | Caption en |
|---|---|---|---|---|
| 1 | Map | phone layout, light theme, a region with clustered and single pins (Annecy and its lake at zoom 11), quick filters visible, the user's dot | Aires, parkings et campings sur une carte | Motorhome areas, car parks and campsites on one map |
| 2 | Place page | an aire with "Nuit autorisée" and its moon, services, hours, price, coordinates row | La nuit indiquée sur chaque fiche | The overnight status on every page |
| 3 | Filters | the filters sheet: kinds, "Nuit possible", services, "Mon véhicule passe" set to the vehicle's height | Filtrez par service, nuit et hauteur | Filter by service, overnight and height |
| 4 | Coordinates | the copy menu with the five formats open, the toast "Copié" | Coordonnées GPS copiées en un geste | GPS coordinates in one tap |
| 5 | Favourites | two or three named lists, one open with its places and distances | Vos lieux rangés en listes | Your places, in lists |
| 6 | Without a network | the list and a search result, system airplane icon in the status bar | Liste, recherche et fiches sans réseau | List, search and pages without a network |
| 7 | Community | a place page scrolled to its photos, reviews and "Toujours là ?" | Avis, photos et confirmations de la communauté | Reviews, photos and confirmations from the community |
| 8 | Account | Profile: pseudonym, trust level, recovery card, delete account | Un compte sans e-mail, une carte de secours | An account without e-mail, a recovery card |
| 9 | Night (App Store only) | scene 1 in the dark theme | Thème sombre après le coucher du soleil | Dark theme after sunset |
| 10 | Vehicle (App Store only) | the vehicle editor with type, trailer and dimensions | Le profil de votre véhicule | Your vehicle's profile |

When the feature ships, in place of scene 4 and 5:

| # | Scene | What the frame shows | Caption fr | Caption en |
|---|---|---|---|---|
| 4 | Directions | the route preview for a 3.30 m vehicle with the warning of a low bridge ("pont 3,20 m"), avoided; route summary | Un itinéraire qui évite les ponts trop bas | A route that avoids bridges too low |
| 5 | Around me | the "around me" chips on a place page, water, groceries and fuel with open or closed and LPG price | Eau, courses, carburant : ce qui est ouvert autour | Water, groceries, fuel: what is open nearby |

Tablets take scenes 1, 2, 3, 5, 7 and 8 (Play) and 1, 2, 3, 5, 6, 7, 8 and
9 (iPad), in the medium and expanded layouts, where list and place page
sit beside the map.

## Content of the frames

- **Real data from production** (`capture.py --api`), never the demo mode:
  demo places carry "(démo)" in their names
  (`app/lib/features/places/data/demo/demo_places.dart`).
- **Community content from our own account.** The reviews, photos and
  confirmation in scenes 2 and 7 are written by the store demo account
  (`lunaway-admin accounts create-demo --level 2`, `docs/deploy.md`) on the
  chosen place, with photos we took. No other user's pseudonym, text or
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

1. **Tour.** A new integration test,
   `app/integration_test/store_tour_test.dart`, modelled on
   `screens_tour_test.dart`, prints `SHOT <nn>-<scene>` for the scenes
   above, in order. It reads `--dart-define=LUNAWAY_STORE_SCENES=1,2,3,...`
   to run a subset, `LUNAWAY_STORE_PLACE=<uuid>` for the place of scenes 2
   and 7, and the existing locale and theme defines. It sets the vehicle
   profile, the theme of each scene and the favourite lists before the
   first shot, and recovers the demo account with
   `LUNAWAY_TOUR_RECOVERY_CODE` (as `community_tour_test.dart` does) for
   scenes 7 and 8. Scene 6 needs the network off: on Android, `capture.py`
   runs `adb shell cmd connectivity airplane-mode enable` when the test
   prints `NETWORK off`, and enables it back after the next shot; on iOS
   the simulator has no switch, so the tour shows the cached list and
   search and only the status bar is not overridden.
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
   - Play: `fastlane/metadata/android/<fr-FR|en-US>/images/phoneScreenshots/`,
     `sevenInchScreenshots/`, `tenInchScreenshots/`, named `01-map.png` and
     so on (upload order is the name order).
   - App Store: `fastlane/screenshots/ios/<fr-FR|en-US>/`, named
     `<nn>_<profile>_<scene>.png`; `deliver` sorts by name and recognises
     the device class from the size.
5. **Checks the script runs before it exits non-zero:** each image has the
   exact size of its profile; no alpha channel (`PIL.Image.mode == "RGB"`);
   under 8 MB; the count per folder within the store's limits; the run was
   made with `--api`. A last manual pass reads every image for a demo
   name, a third-party brand or someone else's content.

Raw shots go to `data/tmp/screens/` (gitignored); only the composed images
are committed.
