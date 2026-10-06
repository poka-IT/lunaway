#!/usr/bin/env bash
# Publishes an APK of the fdroid flavour in Lunaway's own F-Droid repository,
# https://lunaway.net/fdroid/repo (docs/deploy.md, "F-Droid repository").
# Runs on the maintainer's Mac, the only holder of the two keys
# (infra/fdroid/keys.sh).
#
#   infra/fdroid/publish.sh APK
#
# APK is a release build of the fdroid flavour, unsigned (as Gradle leaves
# it: app-fdroid-release-unsigned.apk) or already signed with the F-Droid
# APK key; any other signature is refused. In order:
#
#   1. checks the APK: package, version, no Play Services class, 16 KB
#      alignment of its native libraries;
#   2. signs it with the APK key (apksigner) as repo/legal.p2p.lunaway_<code>.apk;
#   3. fetches the APKs already published, so the index keeps them;
#   4. writes the metadata: infra/fdroid/legal.p2p.lunaway.yml, and the
#      fastlane listing (title, descriptions, changelogs, icon, screenshots)
#      of the commit LUNAWAY_FDROID_REV (HEAD by default), never the working
#      tree;
#   5. runs `fdroid update` (fdroidserver pinned in requirements.txt, in its
#      own virtualenv), which writes and signs the index with the
#      repository key, then checks the signatures;
#   6. uploads the repository and switches the server to it in one rename
#      (infra/server/install-fdroid.sh), then reads it back over HTTPS.
#
# LUNAWAY_FDROID_DIR (default ~/.local/share/lunaway/fdroid) holds the
# working copy of the repository; the server's copy is the reference, so
# this one can be deleted at any time.
set -euo pipefail
. "$(dirname "$0")/../lib.sh"
require_host
apk_in="${1:?usage: $0 APK}"
[ -f "$apk_in" ] || die "no file $apk_in"

APP_ID=legal.p2p.lunaway
REPO_URL=https://lunaway.net/fdroid/repo
FDROIDSERVER_VERSION=2.4.5
VENV="${LUNAWAY_FDROID_VENV:-$HOME/.cache/lunaway/fdroidserver-$FDROIDSERVER_VERSION}"
WORK="${LUNAWAY_FDROID_DIR:-$HOME/.local/share/lunaway/fdroid}"
KEYS="$LUNAWAY_CONFIG_DIR/fdroid"
REV="${LUNAWAY_FDROID_REV:-HEAD}"
SDK="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
STAGING="/home/$LUNAWAY_ADMIN_USER/fdroid-staging"

for candidate in "${LUNAWAY_JAVA_HOME:-}" /opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home \
  /opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home; do
  if [ -n "$candidate" ] && [ -x "$candidate/bin/jarsigner" ]; then
    export JAVA_HOME="$candidate"
    break
  fi
done
[ -n "${JAVA_HOME:-}" ] || die "no JDK found: brew install openjdk@21, or set LUNAWAY_JAVA_HOME"
export PATH="$JAVA_HOME/bin:$PATH"
build_tools="$(find "$SDK/build-tools" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -V | tail -n 1)"
[ -x "$build_tools/apksigner" ] || die "no apksigner under $SDK/build-tools"
command -v uv >/dev/null || die "uv not found (https://docs.astral.sh/uv/)"

[ -f "$KEYS/passwords.env" ] || die "no F-Droid keys in $KEYS (infra/fdroid/keys.sh)"
# shellcheck disable=SC1091
. "$KEYS/passwords.env"
export FDROID_REPO_KEYSTORE_PASS FDROID_APP_KEYSTORE_PASS
cert_sha256() {
  keytool -exportcert -rfc -keystore "$1" -storetype PKCS12 -alias "$2" -storepass:env "$3" 2>/dev/null \
    | openssl x509 -noout -fingerprint -sha256 | sed 's/^.*=//; s/://g' | tr 'A-F' 'a-f'
}
repo_fpr="$(cert_sha256 "$KEYS/repo-keystore.p12" lunaway-repo FDROID_REPO_KEYSTORE_PASS)"
app_fpr="$(cert_sha256 "$KEYS/app-keystore.p12" lunaway-fdroid FDROID_APP_KEYSTORE_PASS)"
[[ "$repo_fpr" =~ ^[0-9a-f]{64}$ && "$app_fpr" =~ ^[0-9a-f]{64}$ ]] || die "cannot read the key certificates"

log "fdroidserver $FDROIDSERVER_VERSION"
if [ "$("$VENV/bin/fdroid" --version 2>/dev/null || true)" != "$FDROIDSERVER_VERSION" ]; then
  uv venv -q --python 3.12 "$VENV"
  uv pip sync -q --python "$VENV/bin/python" --require-hashes "$LUNAWAY_INFRA_DIR/fdroid/requirements.txt"
fi
[ "$("$VENV/bin/fdroid" --version)" = "$FDROIDSERVER_VERSION" ] || die "fdroidserver is not $FDROIDSERVER_VERSION in $VENV"

log "checking $apk_in"
badging="$("$build_tools/aapt2" dump badging "$apk_in")"
package="$(sed -nE "s/^package: name='([^']+)'.*/\1/p" <<<"$badging")"
code="$(sed -nE "s/^package: .* versionCode='([0-9]+)'.*/\1/p" <<<"$badging")"
name="$(sed -nE "s/^package: .* versionName='([^']+)'.*/\1/p" <<<"$badging")"
[ "$package" = "$APP_ID" ] || die "the APK is $package, not $APP_ID"
[[ "$code" =~ ^[0-9]+$ ]] || die "no versionCode in the APK"
[[ "$name" == *-fdroid ]] || die "versionName $name: not a build of the fdroid flavour"
python3 "$LUNAWAY_REPO_DIR/app/tool/android/check_gms.py" "$apk_in" | tail -n 1 | grep -q '^0 Play Services' \
  || die "the APK defines Play Services classes"
"$build_tools/zipalign" -c -P 16 4 "$apk_in" || die "the APK's native libraries are not 16 KB aligned"
log "$APP_ID $name, versionCode $code"

install -d -m 0700 "$WORK"
install -d -m 0755 "$WORK/repo" "$WORK/archive" "$WORK/metadata" "$WORK/tmp"
target="$WORK/repo/${APP_ID}_$code.apk"
if "$build_tools/apksigner" verify "$apk_in" >/dev/null 2>&1; then
  signer="$("$build_tools/apksigner" verify --print-certs "$apk_in" | sed -nE 's/^Signer #1 certificate SHA-256 digest: ([0-9a-f]{64})$/\1/p')"
  [ "$signer" = "$app_fpr" ] || die "the APK is signed by $signer, not by the F-Droid APK key $app_fpr"
  signed="$apk_in"
else
  signed="$WORK/tmp/${APP_ID}_$code.apk"
  rm -f "$signed"
  # --alignment-preserved: Gradle already aligned the uncompressed native
  # libraries on 16 KB pages; apksigner must not move them.
  "$build_tools/apksigner" sign --alignment-preserved \
    --ks "$KEYS/app-keystore.p12" --ks-type PKCS12 --ks-key-alias lunaway-fdroid \
    --ks-pass env:FDROID_APP_KEYSTORE_PASS --key-pass env:FDROID_APP_KEYSTORE_PASS \
    --in "$apk_in" --out "$signed"
  rm -f "$signed.idsig"
fi
"$build_tools/apksigner" verify --print-certs "$signed" | grep -q "SHA-256 digest: $app_fpr" || die "signature check failed"
"$build_tools/zipalign" -c -P 16 4 "$signed" || die "signing broke the 16 KB alignment"

log "published APKs from the server"
if lunaway_ssh 'test -d /srv/lunaway/fdroid/repo'; then
  rsync -rt --ignore-existing --include='*.apk' --exclude='*' -e "ssh -F $LUNAWAY_SSH_CONFIG" \
    lunaway:/srv/lunaway/fdroid/repo/ "$WORK/repo/"
  rsync -rt --ignore-existing --include='*.apk' --exclude='*' -e "ssh -F $LUNAWAY_SSH_CONFIG" \
    lunaway:/srv/lunaway/fdroid/archive/ "$WORK/archive/" 2>/dev/null || true
fi
for dir in repo archive; do
  if [ -f "$WORK/$dir/${APP_ID}_$code.apk" ] && [ "$WORK/$dir/${APP_ID}_$code.apk" != "$signed" ]; then
    cmp -s "$WORK/$dir/${APP_ID}_$code.apk" "$signed" \
      || die "versionCode $code is already published with other content; build a new versionCode"
  fi
done
if [ "$signed" != "$target" ]; then
  cp "$signed" "$target"
  [ "$signed" = "$WORK/tmp/${APP_ID}_$code.apk" ] && rm -f "$signed"
fi

# The index signed here vouches for every APK it lists, the ones fetched
# back from the server included: each must carry the APK key's signature
# and no other, or a server that was tampered with would get its own APK
# into the signed index. (The metadata's AllowedAPKSigningKeys makes
# fdroid update drop such an APK too; this stops the publication instead.)
for f in "$WORK"/repo/*.apk "$WORK"/archive/*.apk; do
  [ -f "$f" ] || continue
  certs="$("$build_tools/apksigner" verify --print-certs "$f" 2>/dev/null)" || die "$f does not verify"
  if [ "$(grep -c '^Signer #[0-9]* certificate SHA-256 digest: ' <<<"$certs")" != 1 ] \
    || ! grep -q "^Signer #1 certificate SHA-256 digest: $app_fpr\$" <<<"$certs"; then
    die "$f is not signed by the F-Droid APK key alone; nothing published"
  fi
done

log "metadata from $REV"
commit="$(git -C "$LUNAWAY_REPO_DIR" rev-parse --verify "$REV^{commit}")"
listing="$WORK/tmp/fastlane-$commit"
if [ ! -d "$listing" ]; then
  install -d -m 0755 "$listing"
  git -C "$LUNAWAY_REPO_DIR" archive "$commit" fastlane/metadata/android | tar -x -C "$listing"
fi
[ -f "$listing/fastlane/metadata/android/en-US/title.txt" ] || die "no fastlane listing in $commit"
install -d -m 0755 "$WORK/metadata/$APP_ID"
rsync -rt --delete "$listing/fastlane/metadata/android/" "$WORK/metadata/$APP_ID/"
cp "$LUNAWAY_INFRA_DIR/fdroid/$APP_ID.yml" "$WORK/metadata/$APP_ID.yml"
# fdroid update copies the repository's icon, named relative to $WORK, into
# repo/icons/ and archive/icons/.
cp "$listing/fastlane/metadata/android/en-US/images/icon.png" "$WORK/lunaway.png"

# The repository's settings, written on each run. The passwords stay in the
# environment ({env: ...}), never in this file.
umask 077
cat > "$WORK/config.yml" <<EOF
repo_url: $REPO_URL
repo_name: Lunaway
repo_icon: lunaway.png
repo_description: >-
  Lunaway's own repository: the map of motorhome and van spots, built
  without any Google service. Source code: https://github.com/poka-IT/lunaway
archive_older: 3
archive_url: https://lunaway.net/fdroid/archive
archive_name: Lunaway archive
archive_icon: lunaway.png
archive_description: >-
  Older versions of Lunaway.
keystore: $KEYS/repo-keystore.p12
keystorepass: {env: FDROID_REPO_KEYSTORE_PASS}
keypass: {env: FDROID_REPO_KEYSTORE_PASS}
repo_keyalias: lunaway-repo
keydname: CN=Lunaway F-Droid repository, O=Lunaway
sdk_path: $SDK
java_paths:
  '21': $JAVA_HOME
EOF
umask 022

log "fdroid update"
( cd "$WORK" && "$VENV/bin/fdroid" update --verbose ) > "$WORK/tmp/update.log" 2>&1 \
  || { tail -n 20 "$WORK/tmp/update.log" >&2; die "fdroid update failed (log: $WORK/tmp/update.log)"; }
grep -E ' (WARNING|ERROR|CRITICAL): ' "$WORK/tmp/update.log" | head -n 10 || true

# The index must be signed by the repository key: the fingerprint users
# check. index-v1.jar is signed with SHA-1 digests too, for old clients, as
# fdroidserver does on purpose; the JDK refuses SHA-1 by default, so the
# check allows it through a security properties file, as fdroidserver's own
# check does. Tool output in English.
echo 'jdk.jar.disabledAlgorithms=MD2, RSA keySize < 1024' > "$WORK/tmp/java.security"
jdk_opts=(-J-Duser.language=en "-J-Djava.security.properties=$WORK/tmp/java.security")
for jar in entry.jar index-v1.jar; do
  [ -f "$WORK/repo/$jar" ] || die "fdroid update wrote no repo/$jar"
  jarsigner "${jdk_opts[@]}" -verify "$WORK/repo/$jar" | grep -q '^jar verified\.' || die "repo/$jar does not verify"
  got="$(keytool "${jdk_opts[@]}" -printcert -jarfile "$WORK/repo/$jar" | sed -nE 's/^[[:space:]]*SHA256: ([0-9A-F:]+)$/\1/p' | head -n 1 | tr -d ':' | tr 'A-F' 'a-f')"
  [ "$got" = "$repo_fpr" ] || die "repo/$jar is signed by $got, not by the repository key"
done
python3 - "$WORK/repo/index-v2.json" "$APP_ID" "$code" <<'EOF'
import json, sys
index, app, code = sys.argv[1], sys.argv[2], int(sys.argv[3])
data = json.load(open(index))
versions = data["packages"][app]["versions"].values()
if not any(v["manifest"]["versionCode"] == code for v in versions):
    sys.exit("index-v2.json does not list versionCode %d" % code)
EOF

log "uploading to the server"
release="$(date -u +%Y%m%dT%H%M%SZ)-$code"
lunaway_ssh "mkdir -p ~/infra/server $STAGING"
lunaway_scp "$LUNAWAY_INFRA_DIR/server/common.sh" "$LUNAWAY_INFRA_DIR/server/install-fdroid.sh" "lunaway:infra/server/"
# status/ holds the build machine's details (fdroidserver's run reports):
# never published. Nor is the page fdroid writes for browsers (index.html,
# its stylesheet and QR code): https://lunaway.net/fdroid/ is that page.
rsync -rt --delete --delete-excluded --exclude='/repo/status/' --exclude='/archive/status/' \
  --exclude='/*/index.html' --exclude='/*/index.css' --exclude='/*/index.png' \
  --include='/repo/***' --include='/archive/***' --exclude='*' \
  -e "ssh -F $LUNAWAY_SSH_CONFIG" "$WORK/" "lunaway:$STAGING/"
lunaway_ssh "sudo bash ~/infra/server/install-fdroid.sh $release"

log "reading it back"
base="https://$LUNAWAY_HOSTNAME/fdroid/repo"
for file in entry.jar index-v1.jar index-v2.json "${APP_ID}_$code.apk"; do
  remote="$(curl -fsS -m 120 "$base/$file" | shasum -a 256 | awk '{ print $1 }')"
  local_sum="$(shasum -a 256 "$WORK/repo/$file" | awk '{ print $1 }')"
  [ "$remote" = "$local_sum" ] || die "$base/$file differs from the local repository"
done
log "published $APP_ID $name (versionCode $code) as release $release"
echo "repository: $REPO_URL"
# Upper case, as fdroid writes it in repo/index.html and F-Droid shows it.
echo "fingerprint: $(tr 'a-f' 'A-F' <<<"$repo_fpr")"
echo "link: $REPO_URL?fingerprint=$(tr 'a-f' 'A-F' <<<"$repo_fpr")"
echo "APK signing certificate SHA-256: $app_fpr"
