# Releasing Lunaway

Who reads this: whoever takes a green `main` to the stores. Each store has
its own file for the details: `docs/play-store.md`, `docs/app-store.md`,
`docs/store-listing.md`, `docs/screenshots.md`, and `docs/deploy.md` for
the servers. This file gives the order and the checks.

Nothing is automatic. No workflow runs on a tag (`.github/workflows/ci.yml`
runs on pushes to `main` and on pull requests): every store build,
signature, upload and deploy below is made by hand, on the maintainer's Mac.

## 1. Before the version

1. `main` is green on GitHub for the commit to release:
   `gh run list --workflow ci.yml --branch main --limit 3` shows
   `completed success` for that sha.
2. Locally, `tool/check.sh` (the full run, test suites included) is green,
   and the pre-PR audit of the changes since the last release is done
   (`.claude/skills/pre-pr-audit/SKILL.md`).
3. The text matches the build:
   - the store text (`fastlane/metadata/`) claims only what ships
     (`docs/store-listing.md`, "Rules");
   - the Data safety inventory (`docs/play-store.md`), the App Store label
     and `app/ios/Runner/PrivacyInfo.xcprivacy` (`docs/app-store.md`) match
     the data the build sends;
   - the privacy and deletion pages (`tool/site/src/pages/*/privacy.html`,
     `delete.html`) say the same, then `python3 tool/site/build.py`.
4. Screenshots are made from this build (`docs/screenshots.md`).

## 2. Version and build numbers

`app/pubspec.yaml` carries `version: X.Y.Z+N`:

| Number | Becomes | Rule |
|---|---|---|
| `X.Y.Z` | Android `versionName` (`flutter.versionName`, `app/android/app/build.gradle.kts`; the same in both flavors), iOS `CFBundleShortVersionString` | semantic version of the release |
| `N` | Android `versionCode` (`flutter.versionCode`), iOS `CFBundleVersion` | one more than any build ever uploaded anywhere (Play, App Store, F-Droid); never reused, also across betas |

Each `N` uploaded to Play has its notes in
`fastlane/metadata/android/<locale>/changelogs/<N>.txt` (six locales, 500
characters), and each App Store version its
`fastlane/metadata/ios/<locale>/release_notes.txt`. On 2026-10-06 the
F-Droid repository already carries versionCode 1 (`docs/deploy.md`): the
first store release is `0.1.0+2` or above, and `changelogs/1.txt` moves to
`changelogs/2.txt`.

Commit the bump alone: `chore(release) : version X.Y.Z+N`.

## 3. Tags

- `vX.Y.Z-beta.N` for a pre-release (internal Play track, TestFlight, the
  F-Droid repository as a beta): `git tag -a vX.Y.Z-beta.N -m "..."`, then
  `git push origin vX.Y.Z-beta.N`. The beta number counts the betas of
  `X.Y.Z`; it is not the build number.
- `vX.Y.Z` for a release to the public. The pre-push hook refuses it
  without the acknowledgement (`.githooks/pre-push`, also the agent bash
  guard): `LUNAWAY_PROD_TAG_ACK=1 git push origin vX.Y.Z`. `git push
  --tags` is refused too; push one tag at a time.
- The tag goes on the version commit, and is pushed only once the
  artifacts of section 5 pass their checks. A tag never moves once pushed.

## 4. Backend first

The stores' reviewers use production, so the API must serve what the app
asks before any upload. If the backend changed since the last deploy:

```bash
LUNAWAY_DEPLOY_REV=<sha> infra/deploy-api.sh    # builds the sha, migrates, checks /health and { apiVersion }
```

then the follow-up steps the change needs (`docs/deploy.md`, "Deploying
the API": imports, worker, routing). The app's operations are checked
against `schema/lunaway.graphql` by `app/test/contract/graphql_contract_test.dart`;
the deployed schema must be the one of the release commit.

## 5. Builds and their checks

Build from a clean checkout of the version commit, never from a tree
that holds other work in progress:

```bash
git worktree add data/tmp/release-vX.Y.Z <sha>
cd data/tmp/release-vX.Y.Z/app && fvm flutter pub get
```

The signed Play bundle needs `app/android/key.properties`. The agents'
permissions deny reading that file (`.claude/settings.json`), and Claude
Code applies the rule to a `cp` as well, so an agent cannot copy it into
the worktree. Two ways, either one:

- the maintainer copies it, never printing it:
  `cp app/android/key.properties data/tmp/release-vX.Y.Z/app/android/`;
- the bundle is built in the main tree, where Gradle reads the file itself
  and no agent reads its content, once three facts are checked and pasted
  in the release report: `git status --porcelain` prints nothing, `git
  rev-parse HEAD` is the version commit, `pgrep -f deploy-web.sh` finds
  nothing; nobody works in the main tree until the build ends. The bundle
  is then copied to `data/tmp/release-artifacts/vX.Y.Z/`.

The F-Droid APK is unsigned and needs neither (below).

Tools: `bundletool` (`brew install bundletool`), `apksigner`, `zipalign`
and `aapt2` from `~/Library/Android/sdk/build-tools/<version>/`,
`apkanalyzer` from `~/Library/Android/sdk/cmdline-tools/latest/bin/`.

### Play bundle (store flavor)

```bash
fvm flutter build appbundle --release --flavor store
AAB=build/app/outputs/bundle/storeRelease/app-store-release.aab       # the path flutter prints
bundletool dump manifest --bundle="$AAB" --xpath /manifest/@android:versionCode    # N
bundletool dump manifest --bundle="$AAB" --xpath /manifest/uses-sdk/@android:targetSdkVersion   # 36 or more
bundletool dump config --bundle="$AAB" | grep -i alignment                         # PAGE_ALIGNMENT_16K
python3 tool/android/check_16k.py "$AAB"                                           # exit 0: every .so aligned on 16 KB
keytool -printcert -jarfile "$AAB" | grep SHA256                                    # the upload certificate of docs/play-store.md
shasum -a 256 "$AAB"                                                               # for the release signal
```

A version name ending in `-debugsigned` means the build fell back to the
debug key (`-PallowDebugSigning`): never upload it.

### F-Droid APK (fdroid flavor)

Built from the same commit as `docs/deploy.md`, "F-Droid repository",
"Publishing a version" does it (a `git archive` copy under
`data/tmp/fdroid/src`, JDK 21). The release build of this flavor is
unsigned: `infra/fdroid/publish.sh` checks it (package, the flavor,
no Play Services class, 16 KB alignment) and signs it with the
F-Droid APK key. The two flavors share one version name; the fdroid one
carries the meta-data `legal.p2p.lunaway.DISTRIBUTION` = `fdroid` in its
manifest. Before that, from the build directory:

```bash
APK=build/app/outputs/apk/fdroid/release/app-fdroid-release-unsigned.apk
aapt2 dump xmltree --file AndroidManifest.xml "$APK" | grep -c 'com.google.android.gms'   # 0
aapt2 dump permissions "$APK"                    # INTERNET, location; nothing unexpected
aapt2 dump xmltree --file AndroidManifest.xml "$APK" | grep -A1 'lunaway.DISTRIBUTION'   # fdroid
```

Preconditions in the commit: `app/android/app/src/fdroid/AndroidManifest.xml`
(it removes the Play Services module service that `image_picker` declares;
untracked on 2026-10-06) is committed, otherwise a clean checkout builds an
fdroid APK that still declares it.

### Both Android artifacts

```bash
for f in "$AAB" "$APK"; do unzip -p "$f" '*arm64-v8a/libapp.so' | strings | grep -c 'Synthetic places generated by Lunaway'; done   # 0 and 0: no demo data in a release
```

The phrase is the attribution of the demo source
(`app/lib/features/places/data/demo/demo_places.dart`), in ASCII so that
`strings` finds it; the demo mode only exists with
`--dart-define=LUNAWAY_DEMO=true` (`app/lib/core/config/app_config.dart`).

### iOS

`fvm flutter build ipa --release` needs the Apple team (`docs/app-store.md`,
"What only the maintainer does"). Until then CI's unsigned build is the
only iOS check.

### Web

```bash
infra/deploy-web.sh app --build     # build_web.sh, fvm flutter build web --base-href /app/ --no-web-resources-cdn, then deploy
```

Built from the main tree by the script: run it from the release worktree,
or check that `app/` has no uncommitted change first.

Before it, the journeys of the map screen on the same code, in the three
browsers, as a phone and as a computer (from `app/`, about 25 minutes):

```bash
sh packages/lunaway_nav/tool/build_web.sh
fvm flutter build web --release --wasm --base-href /app/ --no-web-resources-cdn \
    --dart-define=LUNAWAY_API_URL=http://127.0.0.1:18793 --output build/web-journeys
python3 tool/web/serve_csp.py --port 18793 --root build/web-journeys --api https://api.lunaway.net/graphql &
python3 tool/web/journeys.py --url http://127.0.0.1:18793/app/
```

A failed journey stops the deploy: `build/journeys/report.json` and the
screenshots beside it say at which step. The tool sends a phone's late
mouse events after each tap (`--late-click`), the condition a phone's
browser creates and a desktop never does. `--url https://lunaway.net/app/`
plays them on production.

### Desktop

- Windows: CI builds it unsigned (`ci.yml`, job `windows`) and keeps no
  artifact. A GitHub Release of it needs either an upload step on tags in
  a workflow (to add) or a build on a Windows machine.
- macOS: a signed and notarised build needs a Developer ID certificate,
  which only the maintainer can obtain. Until then, the web app is the
  desktop path.

## 6. Domain, site and web app (first release, then on change)

DNS comes last among the infrastructure steps, and before any store
submission: reviewers open the privacy URL and the app talks to
api.lunaway.net.

1. Site placeholders filled, in the six languages: legal notice
   (maintainer: publication director, postal address, phone, legal form);
   the privacy page's row on the working copy of the external community
   source's collector is written from the collector's code (its private
   repository's README, "Erasures and what the state keeps"): check it
   again when the collector changes; the `/fdroid/` page shows
   the repository address, fingerprint and QR code of `docs/deploy.md`,
   "F-Droid repository"; real screenshots in `infra/web/site/img/screens/`.
   `grep -rl 'data-placeholder' infra/web/site` lists what is left.
2. Records in the Cloudflare zone, all DNS only (not proxied), so that
   Caddy's HTTP-01 challenge reaches the backend (`docs/deploy.md`, "The
   domain"):

   | Name | Type | Value |
   |---|---|---|
   | `lunaway.net` | A, AAAA | backend IPv4, IPv6 |
   | `www.lunaway.net` | A, AAAA | backend |
   | `api.lunaway.net` | A, AAAA | backend |
   | `tiles.lunaway.net` | A, AAAA | backend |
   | `status.lunaway.net` | A, AAAA | backend (on the ops server until it moves: `docs/deploy.md`, "Moving the status page's name") |
   | `lunaway.net` | CAA | `0 issue "letsencrypt.org"` |

   The Infomaniak mail records (MX, SPF, DMARC, autoconfig) stay as they
   are. Proposed, not required: CAA `0 issuewild ";"` (no wildcard
   certificate is used).
3. `infra/enable-domain.sh` checks the records from 1.1.1.1 and 8.8.8.8,
   enables the sites, and the status page once its record points at the
   backend, and waits for the certificates. Then the settings of
   `docs/deploy.md` ("The domain"): `LUNAWAY_API_HOST`, `LUNAWAY_TILES_URL`,
   `LUNAWAY_WEB_URL`, `LUNAWAY_MEDIA_BASE_URL`, and the two `configure.sh`
   runs it names.
4. Site and web app:

   ```bash
   python3 tool/site/build.py
   infra/deploy-web.sh site infra/web/site
   infra/deploy-web.sh app --build
   ```

   The site deploy replaces the whole site directory; the F-Droid
   repository must live outside it (section 8).
5. DNSSEC: enable it on the zone in Cloudflare, which shows the DS record
   (key tag, algorithm 13, digest type 2, digest). The maintainer enters it
   at Infomaniak, the registrar (domain, DNSSEC): no agent has access
   there. Check afterwards with `dig +dnssec lunaway.net SOA` (flag `ad`
   from a validating resolver) or dnsviz.net.
6. Live checks, from two networks (the Mac, and a phone on mobile data;
   the external probe also checks the site, the API, the basemap, a search
   and a route from GitHub's machines every 15 minutes, `docs/deploy.md`,
   "The external probe"):

   ```bash
   curl -s https://api.lunaway.net/health                       # ok
   curl -s https://api.lunaway.net/graphql -H 'content-type: application/json' -d '{"query":"{ apiVersion }"}'
   for p in / /en/ /de/ /es/ /it/ /nl/ /privacy /en/privacy /de/privacy /es/privacy /it/privacy /nl/privacy /account/delete /en/account/delete /de/account/delete /es/account/delete /it/account/delete /nl/account/delete /app/; do curl -s -o /dev/null -w "%{http_code} $p\n" "https://lunaway.net$p"; done   # 200 each
   ```

   And a test mail to contact@lunaway.net, read in the mailbox (Play
   requires a working contact address).

## 7. Google Play: the release signal

A separate Claude Code session drives the Play Console
(`docs/play-store.md`, "Access and tools") and waits for this message. It
carries every item of the "Ready to publish" checklist with its evidence:

```
Lunaway release signal
Tag: vX.Y.Z (commit <sha>), pushed
AAB: <absolute path>/app-store-release.aab, SHA-256 <sum>
versionCode N, versionName X.Y.Z, targetSdk <n>
Track: production (internal for a beta tag)

1. Build: bundletool versionCode N, targetSdk <n>, PAGE_ALIGNMENT_16K;
   check_16k.py exit 0; signer SHA-256 <keytool line>, equal to the upload certificate.
2. Live URLs: /privacy 200, /account/delete 200, api.lunaway.net/health ok
   (outputs pasted), contact@lunaway.net received a test mail on <date>.
3. In the app: deletion at Profile, Your account, Delete my account;
   privacy link at Profile, About, Privacy policy (commit <sha>).
4. Data inventory: docs/play-store.md "Data safety inventory" at <sha>;
   form answers in "Form answers".
5. Reviewer access: demo account at level 2 created on <date> with
   lunaway-admin accounts create-demo; recovery code: <code> (for the
   App access field only, never written to a file).
6. Content rating inputs: docs/play-store.md "App content answers" at <sha>.
7. Listing: fastlane/metadata/android at <sha>: <n> phone, <n> 7-inch,
   <n> 10-inch screenshots, changelogs/N.txt in the six locales.
8. Store preconditions: docs/play-store.md "Ready to publish", item 8 (name; open data plus the external community source under its written agreement).
```

The Play session then follows "Release procedure" of `docs/play-store.md`.

## 8. F-Droid: our own repository

The repository, its keys, its publish script and its Caddy route are
described in `docs/deploy.md`, "F-Droid repository" (written by the infra
side on 2026-10-06, `infra/fdroid/`). It already serves Lunaway
0.1.0-fdroid, versionCode 1, built from 69f9c98: the next release takes
`N = 2` at least, and Play's `changelogs/<N>.txt` follows.

For a release:

1. `LUNAWAY_FDROID_REV=<tag> infra/fdroid/publish.sh <unsigned APK of
   section 5>`: checks, signature with the APK key, metadata and listing
   from `fastlane/metadata/android/` at the tag, signed index, upload to
   `/srv/lunaway/fdroid` (outside the site directory, so a site deploy
   leaves it), read back over HTTPS.
2. On a phone: the F-Droid app with the repository link and fingerprint of
   `docs/deploy.md`, install, then update from the previous version.

Play and F-Droid builds carry different signatures: an install from one
cannot update from the other (the site's F-Droid page says so). Official
inclusion in F-Droid is the maintainer's merge request to fdroiddata, from
the draft `infra/fdroid/fdroiddata/metadata/legal.p2p.lunaway.yml`
(`docs/deploy.md`, "Official F-Droid").

## 9. App Store: the handoff

The maintainer, with `docs/app-store.md`:

1. Team, App ID, app record, signing (section "What only the maintainer
   does"), once.
2. `fvm flutter build ipa --release` from the release worktree, upload
   (Transporter, Xcode Organizer, or `fastlane ios beta`).
3. Export compliance, App Privacy, age rating, content rights, review
   information with a fresh demo account code.
4. `fastlane ios metadata` (or the forms by hand), then submit.

What the orchestrator hands over: the tag, the commit, the state of the
checks of section 5, the demo account code (out of band), and any
`Info.plist` change of `docs/app-store.md` still to apply.

## 10. Last check: nothing banned in public history

The local `.leak-denylist` (untracked, one term per line, matched without
case as a plain substring) guards edits and commits only
(`tool/harness/git/check_leaks.sh`, `edit_guard.py`). Nothing scans what
is already public, so before announcing a release:

```bash
git fetch origin --tags
git log -p --no-color --remotes=origin --tags | grep -ciF -f .leak-denylist          # 0
git log --remotes=origin --tags --format='%B' | grep -ciF -f .leak-denylist          # 0, commit messages
git log --remotes=origin --tags --name-only --format= | grep -ciF -f .leak-denylist  # 0, file names
git for-each-ref refs/tags --format='%(contents)' | grep -ciF -f .leak-denylist      # 0, tag messages
gh release list --limit 100 --json name,tagName | grep -ciF -f .leak-denylist     # 0
gh pr list --state all --limit 500 --json title,body | grep -ciF -f .leak-denylist # 0
gh issue list --state all --limit 500 --json title,body | grep -ciF -f .leak-denylist # 0
gh repo view --json description,homepageUrl,repositoryTopics | grep -ciF -f .leak-denylist  # 0
```

Every command prints a count, never a term. A count above zero is located
without printing the term, for instance `git grep -l -i -F -f
.leak-denylist $(git rev-list --remotes=origin --tags)` (commit and path
only). Removing a
term from published history rewrites it and needs a forced push, which the
harness refuses to agents: that decision and that push are the
maintainer's.

## 11. After

- `git worktree remove data/tmp/release-vX.Y.Z` once the uploads are done
  (a `key.properties` copied there goes with it).
- Watch the reviews in the Play Console and App Store Connect; answer a
  rejection from the guideline it cites, in the files named here.
- The next version starts at section 1 with `N + 1`.
