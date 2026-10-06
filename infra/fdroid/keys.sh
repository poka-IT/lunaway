#!/usr/bin/env bash
# The two keys of Lunaway's own F-Droid repository, on the maintainer's Mac
# only (docs/deploy.md, "F-Droid repository"):
#
#   repo-keystore.p12   alias lunaway-repo: signs the repository's index; its
#                       certificate's SHA-256 is the fingerprint users check
#                       when they add the repository
#   app-keystore.p12    alias lunaway-fdroid: signs the APK of the fdroid
#                       flavour. Android accepts an update only with the same
#                       key: losing it strands every install
#   passwords.env       the two store passwords (PKCS12: the key password is
#                       the store password), read by publish.sh, never printed
#
# all in ~/.config/lunaway/fdroid/ (0700, files 0600).
#
#   infra/fdroid/keys.sh create   generates both keys; refuses when one exists
#   infra/fdroid/keys.sh show     the two certificates' SHA-256 fingerprints
#   infra/fdroid/keys.sh backup   an age-encrypted copy of the directory into
#                                 the backup chain (backend, ops server, Mac)
set -euo pipefail
. "$(dirname "$0")/../lib.sh"
DIR="$LUNAWAY_CONFIG_DIR/fdroid"
REPO_KS="$DIR/repo-keystore.p12"
APP_KS="$DIR/app-keystore.p12"
PASSWORDS="$DIR/passwords.env"
REPO_ALIAS=lunaway-repo
APP_ALIAS=lunaway-fdroid

# A JDK for keytool: LUNAWAY_JAVA_HOME, else Homebrew's openjdk 21 or 17
# (macOS's /usr/bin/keytool is a stub without a JDK).
java_home() {
  local candidate
  for candidate in "${LUNAWAY_JAVA_HOME:-}" /opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home \
    /opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home; do
    [ -n "$candidate" ] && [ -x "$candidate/bin/keytool" ] && { echo "$candidate"; return; }
  done
  die "no JDK found: brew install openjdk@21, or set LUNAWAY_JAVA_HOME"
}
KEYTOOL="$(java_home)/bin/keytool"

# A random password of 40 characters from [A-Za-z0-9], written by the
# caller into a 0600 file, never to the terminal.
random_password() { LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 40; }

load_passwords() {
  [ -f "$PASSWORDS" ] || die "no $PASSWORDS; run $0 create first"
  # shellcheck disable=SC1090
  . "$PASSWORDS"
  export FDROID_REPO_KEYSTORE_PASS FDROID_APP_KEYSTORE_PASS
}

fingerprint() {
  "$KEYTOOL" -exportcert -rfc -keystore "$1" -storetype PKCS12 -alias "$2" -storepass:env "$3" 2>/dev/null \
    | openssl x509 -noout -fingerprint -sha256 | sed 's/^.*=//'
}

case "${1:-}" in
  create)
    for f in "$REPO_KS" "$APP_KS" "$PASSWORDS"; do
      [ ! -e "$f" ] || die "$f exists: the keys are created once; restore them from a backup instead"
    done
    install -d -m 0700 "$DIR"
    (
      umask 077
      printf 'FDROID_REPO_KEYSTORE_PASS=%s\nFDROID_APP_KEYSTORE_PASS=%s\n' "$(random_password)" "$(random_password)" > "$PASSWORDS"
    )
    load_passwords
    # RSA 4096, valid 10 000 days (until 2054): the APK key cannot be
    # replaced without every user reinstalling.
    "$KEYTOOL" -genkeypair -keystore "$REPO_KS" -storetype PKCS12 -alias "$REPO_ALIAS" \
      -keyalg RSA -keysize 4096 -sigalg SHA256withRSA -validity 10000 \
      -dname "CN=Lunaway F-Droid repository, O=Lunaway" \
      -storepass:env FDROID_REPO_KEYSTORE_PASS -keypass:env FDROID_REPO_KEYSTORE_PASS >/dev/null 2>&1
    "$KEYTOOL" -genkeypair -keystore "$APP_KS" -storetype PKCS12 -alias "$APP_ALIAS" \
      -keyalg RSA -keysize 4096 -sigalg SHA256withRSA -validity 10000 \
      -dname "CN=Lunaway, O=Lunaway" \
      -storepass:env FDROID_APP_KEYSTORE_PASS -keypass:env FDROID_APP_KEYSTORE_PASS >/dev/null 2>&1
    chmod 0600 "$REPO_KS" "$APP_KS" "$PASSWORDS"
    log "created in $DIR; back them up now: $0 backup"
    "$0" show
    ;;
  show)
    load_passwords
    echo "repository key ($REPO_ALIAS), SHA-256: $(fingerprint "$REPO_KS" "$REPO_ALIAS" FDROID_REPO_KEYSTORE_PASS)"
    echo "APK signing key ($APP_ALIAS), SHA-256: $(fingerprint "$APP_KS" "$APP_ALIAS" FDROID_APP_KEYSTORE_PASS)"
    ;;
  backup)
    # Encrypted here to the backup recipient (the age identity exists only on
    # this Mac and in the maintainer's offline copy), then written at the top
    # of the backend's off-site directory, which the ops server and this Mac
    # pull every night and prune by the dumps' names only, so the copy stays.
    # Not in a subdirectory: the ops server's pull cannot copy a setgid
    # directory (RestrictSUIDSGID of lunaway-replica.service). The plaintext
    # never leaves this machine.
    recipient="${LUNAWAY_BACKUP_RECIPIENT:-}"
    [[ "$recipient" =~ ^age1[02-9ac-hj-np-z]{58}$ ]] || die "LUNAWAY_BACKUP_RECIPIENT is not an age recipient"
    for f in "$REPO_KS" "$APP_KS" "$PASSWORDS"; do [ -f "$f" ] || die "missing $f"; done
    require_host
    stamp="$(date -u +%Y%m%dT%H%M%SZ)"
    name="fdroid-keys-$stamp.tar.age"
    out="$LUNAWAY_REPO_DIR/data/tmp/fdroid/$name"
    install -d -m 0700 "$LUNAWAY_REPO_DIR/data/tmp/fdroid"
    COPYFILE_DISABLE=1 tar -C "$LUNAWAY_CONFIG_DIR" --no-xattrs --no-mac-metadata -cf - \
      fdroid/repo-keystore.p12 fdroid/app-keystore.p12 fdroid/passwords.env | age -r "$recipient" -o "$out"
    # The copy must open with the identity before it counts as a backup.
    listed="$(age --decrypt --identity "$LUNAWAY_CONFIG_DIR/backup-age.key" "$out" | tar -tf - | sort | tr '\n' ' ')"
    [ "$listed" = "fdroid/app-keystore.p12 fdroid/passwords.env fdroid/repo-keystore.p12 " ] \
      || die "the encrypted copy does not list the three files: $listed"
    local_sum="$(shasum -a 256 "$out" | awk '{ print $1 }')"
    lunaway_ssh "sudo tee /srv/data/backups/offsite/$name >/dev/null \
      && sudo chown root:lunaway-pull /srv/data/backups/offsite/$name \
      && sudo chmod 0640 /srv/data/backups/offsite/$name" < "$out"
    remote_sum="$(lunaway_ssh "sudo sha256sum /srv/data/backups/offsite/$name" | awk '{ print $1 }')"
    [ "$remote_sum" = "$local_sum" ] || die "the copy on the backend differs from the one encrypted here"
    rm -f "$out"
    log "backend:/srv/data/backups/offsite/$name ($local_sum); the ops server pulls it at 01:15 UTC, this Mac at 04:30"
    ;;
  *)
    die "usage: $0 create | show | backup"
    ;;
esac
