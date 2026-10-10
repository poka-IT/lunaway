#!/usr/bin/env bash
# Checks install_caddy_package and fetch_sha512 (infra/server/common.sh),
# which install Caddy from the .deb of its GitHub release, on a copy of
# common.sh whose staging directory and infra/ tree are scratch ones, with
# stand-ins for curl, dpkg and dpkg-query that serve a fixture and record
# what would be installed. A package that does not hash to the pin is
# refused and removed, and dpkg never sees it, whether it was just
# downloaded or left from an earlier run; a missing or malformed pin, an
# architecture without a pin and a failed download are refused too; the
# right package is installed once, and not downloaded again while the
# pinned version is installed. Needs no network and no root.
#
#   infra/tests/caddy-package.sh
set -euo pipefail
INFRA="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$INFRA/.." && pwd)"
SCRATCH="${LUNAWAY_SCRATCH_DIR:-$REPO/data/tmp/infra}/caddy-package-test"
command -v sha512sum >/dev/null || { echo "sha512sum not found (coreutils)" >&2; exit 1; }

mkdir -p "$SCRATCH/infra/server" "$SCRATCH/infra/caddy" "$SCRATCH/bin" "$SCRATCH/staging"
# clean: every file a case may leave, by literal name.
clean() {
  for f in "$SCRATCH/staging/caddy_9.9.9_linux_amd64.deb" "$SCRATCH/staging/caddy_9.9.9_linux_amd64.deb.download" \
    "$SCRATCH/staging/caddy_9.9.9_linux_arm64.deb" "$SCRATCH/curl.log" "$SCRATCH/dpkg.log" "$SCRATCH/out"; do
    if [ -e "$f" ] || [ -L "$f" ]; then rm -f -- "$f"; fi
  done
}
clean

# The production copy stages in /var/lib/lunaway-setup and reads the pins
# from infra/caddy/version.sh beside it; this one does both in the scratch
# directory.
grep -q '^STAGING=/var/lib/lunaway-setup$' "$INFRA/server/common.sh" \
  || { echo "FAIL common.sh no longer stages in /var/lib/lunaway-setup"; exit 1; }
sed "s|^STAGING=/var/lib/lunaway-setup\$|STAGING=$SCRATCH/staging|" "$INFRA/server/common.sh" > "$SCRATCH/infra/server/common.sh"

# The package the stand-in release serves, and a copy with one byte changed.
head -c 4096 /dev/urandom > "$SCRATCH/good.deb"
cp "$SCRATCH/good.deb" "$SCRATCH/bad.deb"
printf 'X' | dd of="$SCRATCH/bad.deb" bs=1 seek=2048 conv=notrunc 2>/dev/null
cmp -s "$SCRATCH/good.deb" "$SCRATCH/bad.deb" && printf 'Y' | dd of="$SCRATCH/bad.deb" bs=1 seek=2048 conv=notrunc 2>/dev/null
good_sha512="$(sha512sum "$SCRATCH/good.deb" | awk '{ print $1 }')"

# pins AMD64_PIN: writes the scratch version.sh.
pins() {
  printf 'CADDY_VERSION=9.9.9\nCADDY_DEB_SHA512_AMD64=%s\nCADDY_DEB_SHA512_ARM64=%s\n' "$1" "$good_sha512" \
    > "$SCRATCH/infra/caddy/version.sh"
}

# Stand-ins: curl writes $SCRATCH/served (absent: the download fails) to
# its -o file; dpkg prints $SCRATCH/arch and records an installation;
# dpkg-query prints $SCRATCH/installed.
cat > "$SCRATCH/bin/curl" <<'EOF'
#!/usr/bin/env bash
out="" url=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    -A|-m|--retry) shift 2 ;;
    -*) shift ;;
    *) url="$1"; shift ;;
  esac
done
echo "$url" >> "$SCRATCH/curl.log"
[ -f "$SCRATCH/served" ] || exit 22
cp "$SCRATCH/served" "$out"
EOF
cat > "$SCRATCH/bin/dpkg" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = --print-architecture ]; then cat "$SCRATCH/arch"; exit 0; fi
for arg in "$@"; do last="$arg"; done
{ echo "$*"; sha512sum "$last" | awk '{ print $1 }'; } >> "$SCRATCH/dpkg.log"
EOF
cat > "$SCRATCH/bin/dpkg-query" <<'EOF'
#!/usr/bin/env bash
cat "$SCRATCH/installed"
EOF
chmod +x "$SCRATCH/bin/curl" "$SCRATCH/bin/dpkg" "$SCRATCH/bin/dpkg-query"

# run: install_caddy_package from the scratch copy, the system files it
# also touches (the former apt source, the apt preferences) left out.
run() {
  (
    export SCRATCH
    PATH="$SCRATCH/bin:$PATH"
    # shellcheck source=../server/common.sh
    . "$SCRATCH/infra/server/common.sh"
    remove_caddy_apt_source() { :; }
    install_file() { return 1; }
    install_caddy_package
  ) > "$SCRATCH/out" 2>&1
}

failures=0
# expect NAME WANTED_STATUS INSTALLED DOWNLOADS: the exit status, the hash
# dpkg was handed ("none" when it was not called) and the number of
# downloads asked.
expect() {
  local name="$1" want="$2" want_installed="$3" want_downloads="$4" got=0 installed=none downloads=0
  run || got=$?
  [ -f "$SCRATCH/dpkg.log" ] && installed="$(sed -n 2p "$SCRATCH/dpkg.log")"
  [ "$installed" = "$good_sha512" ] && installed=good
  [ -f "$SCRATCH/curl.log" ] && downloads="$(wc -l < "$SCRATCH/curl.log" | tr -d ' ')"
  if [ "$got" = "$want" ] && [ "$installed" = "$want_installed" ] && [ "$downloads" = "$want_downloads" ]; then
    echo "ok   $name"
  else
    echo "FAIL $name: exit $got (want $want), installed $installed (want $want_installed), $downloads download(s) (want $want_downloads): $(head -c 300 "$SCRATCH/out" | tr '\n' ' ')"
    failures=$((failures + 1))
  fi
}
# left NAME: nothing of a refused package stays in the staging directory.
left() {
  if [ -e "$SCRATCH/staging/caddy_9.9.9_linux_amd64.deb" ] || [ -e "$SCRATCH/staging/caddy_9.9.9_linux_amd64.deb.download" ]; then
    echo "FAIL $1: a refused package stayed in the staging directory"
    failures=$((failures + 1))
  else
    echo "ok   $1"
  fi
}

echo amd64 > "$SCRATCH/arch"
echo "install ok installed 9.9.8" > "$SCRATCH/installed"

pins "$good_sha512"
cp "$SCRATCH/bad.deb" "$SCRATCH/served"
expect "a package that does not hash to the pin is refused" 1 none 1
grep -q "the pin says $good_sha512" "$SCRATCH/out" || { echo "FAIL the refusal does not name the pin"; failures=$((failures + 1)); }
left "the refused download is removed"

clean
cp "$SCRATCH/bad.deb" "$SCRATCH/staging/caddy_9.9.9_linux_amd64.deb"
expect "a package left from an earlier run with another hash is refused" 1 none 1
left "the stale package is removed"

clean
cp "$SCRATCH/bad.deb" "$SCRATCH/staging/caddy_9.9.9_linux_amd64.deb"
cp "$SCRATCH/good.deb" "$SCRATCH/served"
expect "a stale package is downloaded again, then installed" 0 good 1

clean
rm -f -- "$SCRATCH/served"
expect "a failed download is refused" 1 none 1
left "nothing stays of a failed download"

clean
cp "$SCRATCH/good.deb" "$SCRATCH/served"
pins ""
expect "an empty pin is refused before any download" 1 none 0
pins "${good_sha512:0:64}"
expect "a SHA-256 in place of the SHA-512 is refused" 1 none 0
pins "$(echo "$good_sha512" | tr a-f A-F)"
expect "a pin in capitals is refused" 1 none 0

pins "$good_sha512"
echo armhf > "$SCRATCH/arch"
expect "an architecture without a pin is refused" 1 none 0
echo amd64 > "$SCRATCH/arch"

clean
expect "the package that hashes to the pin is installed" 0 good 1
grep -q -- "--force-confold -i $SCRATCH/staging/caddy_9.9.9_linux_amd64.deb" "$SCRATCH/dpkg.log" \
  || { echo "FAIL dpkg was not asked to keep the local Caddyfile"; failures=$((failures + 1)); }
left "the installed package is not kept"

clean
echo "install ok installed 9.9.9" > "$SCRATCH/installed"
expect "the pinned version installed: nothing downloaded" 0 none 0
echo "deinstall ok config-files 9.9.9" > "$SCRATCH/installed"
expect "the pinned version removed, its configuration left: installed again" 0 good 1

clean
if [ "$failures" -gt 0 ]; then
  echo "$failures check(s) failed"
  exit 1
fi
echo "all checks passed"
