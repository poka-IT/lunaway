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

The release `signingConfig` reads `key.properties` and falls back to the
debug key when the file is absent, so CI and fresh clones still build. Back
up the keystore and its password together. A lost upload key is replaced
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
- **Account deletion.** The app creates an account at first launch, so it
  must offer an in-app path to delete the account and its data, and a public
  web page to request it (support.google.com/googleplay/android-developer/answer/13327111).
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
safety form up to step 4 (precise location collected, ephemeral,
optional; name, user IDs,
photos, other user-generated content and other actions collected,
optional; account and data deletion URL https://lunaway.net/account/delete).
Both are submitted at release, once the build confirms these answers.

Decisions from the app side (2026-10-06) behind those answers:

- Users can hide every contribution of an author (a mute synced with the
  account) and report a review, a photo or a place.
- Place and town search run on the device in the Android app, with no
  third-party geocoder: no "search history".
- The release build uses the self-hosted basemap on lunaway.net;
  tiles.openfreemap.org serves development builds only.
- The pseudonym starts generated, the user can edit it, and it is public on
  their contributions: declared as "name".
- A user can delete any single review, photo, place edit or confirmation of
  their own without deleting the account. The deletion page explains both
  paths.

- **App access** ("Informations de connexion"): filed as "no restricted
  part", because the Console requires it before the target audience. At
  release, switch it to restricted: browsing needs no account, but a fresh
  account starts at trust level 0 (favourites, ratings, confirmations);
  written reviews need level 1 and new places level 2. The app side
  provides a demo account at level 2 and its recovery code for the
  reviewer instructions.
- **Content rating:** users publish reviews, ratings, photos and places,
  all public to every user; moderation by an automated classifier, a human
  queue and in-app reporting; users can hide an author; no user to user
  messaging; users are
  pseudonymous; no user location is visible to others (only the places they
  add); no purchases.
- **Data safety.** Inventory given by the app side on 2026-10-06 for the
  release feature set; every datum goes to api.lunaway.net unless stated.
  - Account: device public key (P-256), an editable public pseudonym,
    later a passkey credential id. Needed only to contribute; kept until
    deletion. Form: Name and User IDs, collected, optional.
  - Contributions: reviews (text, rating), photos (EXIF location stripped
    on the server), new places and edits, "still open" confirmations;
    public under CC BY 4.0. Favourites are stored on the server too. On
    account deletion, photos and favourites are deleted, reviews and place
    edits are kept and anonymised (author removed), which the deletion page
    discloses. Form: Photos, Other user-generated content, App activity;
    collected, optional.
  - Precise location: used on the device for distance and "locate me". A
    presence check sends the coordinates with a contribution; the server
    keeps only the verdict. Form: Precise location, collected, processed
    ephemerally, optional, purposes app functionality and fraud prevention.
  - Open data sources (OpenStreetMap, French public datasets) are
    ingested by the server; the app talks only to our hosts. Nothing is
    shared.
  - Server logs keep truncated IPs; rate limiting is in memory. No ads, no
    analytics, no crash reporting SDK.
  - Security: encrypted in transit; accounts are created in the app
    (device key, "other" authentication); deletion at
    https://lunaway.net/account/delete and in the app.

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
   expanded layout ships.
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
