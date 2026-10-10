#!/usr/bin/env bash
# Pins a Caddy release in infra/caddy/version.sh, run here (the Mac).
# Downloads the release's checksums file with its signature, checks the
# signature with cosign, then writes the version and the SHA-512 the file
# gives for the four files Lunaway installs or tests. The signature is
# keyless: a certificate GitHub's OIDC issuer obtained for the release
# workflow of caddyserver/caddy at that very tag, which cosign checks
# against the Sigstore roots and the Rekor log. Nothing is installed; the
# servers get the release from `infra/configure.sh <role> caddy|ops-status`
# (docs/deploy.md, "Upgrading Caddy").
#
# Cosign 3 deprecates `verify-blob --certificate` and `--signature` ("please
# use --bundle"); its help calls a Sigstore bundle "the preferred way to
# provide verification material". Caddy's releases publish the signature
# and the certificate apart, without a bundle, so `cosign bundle create`
# makes one from them and the entry Rekor holds for them, the conversion
# docs.sigstore.dev/cosign/verifying/verify/ gives ("You can take existing
# signed material and make a new protobuf bundle with `cosign bundle
# create ...`"). `verify-blob --bundle` then checks the same identity and
# OIDC issuer as before, the chain to the Sigstore roots, and the log
# entry's inclusion proof, tied to the file, its signature and its
# certificate.
#
#   infra/caddy/pin.sh 2.11.8
set -euo pipefail
INFRA="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$INFRA/.." && pwd)"
version="${1:?usage: infra/caddy/pin.sh VERSION, such as 2.11.8}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "unexpected version $version" >&2; exit 1; }
command -v cosign >/dev/null || { echo "cosign not found (brew install cosign)" >&2; exit 1; }
# Cosign 3.1.3 or later. From 3, the bundle `bundle create` writes (the
# protobuf format) is read by default; until 3.1.3, a file that fails to
# parse as one falls back to the legacy format, whose identity check
# GHSA-fx35-mq7g-6g98 bypassed.
cosign_version="$(cosign version --json | sed -n 's/.*"gitVersion": *"v\([0-9]*\.[0-9]*\.[0-9]*\).*/\1/p')"
IFS=. read -r major minor patch <<< "$cosign_version"
if ! [[ "$cosign_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || (( major * 1000000 + minor * 1000 + patch < 3001003 )); then
  echo "cosign 3.1.3 or later needed, not '$cosign_version' (brew upgrade cosign)" >&2
  exit 1
fi
dir="${LUNAWAY_SCRATCH_DIR:-$REPO/data/tmp/infra}/caddy-pin/$version"
mkdir -p "$dir"
sums="caddy_${version}_checksums.txt"
for file in "$sums" "$sums.pem" "$sums.sig"; do
  curl -fsSL --retry 3 -m 120 -A "Lunaway infra (+https://lunaway.net)" -o "$dir/$file" \
    "https://github.com/caddyserver/caddy/releases/download/v$version/$file"
done
cosign bundle create --artifact "$dir/$sums" --signature "$dir/$sums.sig" \
  --certificate "$dir/$sums.pem" --out "$dir/$sums.sigstore.json"
cosign verify-blob --bundle "$dir/$sums.sigstore.json" \
  --certificate-identity "https://github.com/caddyserver/caddy/.github/workflows/release.yml@refs/tags/v$version" \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com "$dir/$sums"

# sha512_of NAME: the value the checksums file gives for NAME, refused
# unless there is exactly one and it is a SHA-512.
sha512_of() {
  local value
  value="$(awk -v name="$1" '$2 == name { print $1 }' "$dir/$sums")"
  [[ "$value" =~ ^[0-9a-f]{128}$ ]] || { echo "no single SHA-512 for $1 in $sums" >&2; exit 1; }
  printf '%s' "$value"
}
deb_amd64="$(sha512_of "caddy_${version}_linux_amd64.deb")"
deb_arm64="$(sha512_of "caddy_${version}_linux_arm64.deb")"
tar_mac="$(sha512_of "caddy_${version}_mac_arm64.tar.gz")"
tar_linux="$(sha512_of "caddy_${version}_linux_amd64.tar.gz")"

pins="$INFRA/caddy/version.sh"
awk -v version="$version" -v deb_amd64="$deb_amd64" -v deb_arm64="$deb_arm64" \
  -v tar_mac="$tar_mac" -v tar_linux="$tar_linux" '
  /^CADDY_VERSION=/ { print "CADDY_VERSION=" version; seen++; next }
  /^CADDY_DEB_SHA512_AMD64=/ { print "CADDY_DEB_SHA512_AMD64=" deb_amd64; seen++; next }
  /^CADDY_DEB_SHA512_ARM64=/ { print "CADDY_DEB_SHA512_ARM64=" deb_arm64; seen++; next }
  /^CADDY_TAR_SHA512_MAC_ARM64=/ { print "CADDY_TAR_SHA512_MAC_ARM64=" tar_mac; seen++; next }
  /^CADDY_TAR_SHA512_LINUX_AMD64=/ { print "CADDY_TAR_SHA512_LINUX_AMD64=" tar_linux; seen++; next }
  { print }
  END { if (seen != 5) exit 1 }' "$pins" > "$pins.new" \
  || { rm -f -- "$pins.new"; echo "$pins does not hold the five pinned lines" >&2; exit 1; }
mv "$pins.new" "$pins"
echo "pinned Caddy $version in infra/caddy/version.sh; next: infra/tests/caddy-layout.sh, then docs/deploy.md, \"Upgrading Caddy\""
