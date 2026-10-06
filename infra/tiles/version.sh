# shellcheck shell=bash
# shellcheck disable=SC2034 # read by infra/server/tiles.sh and infra/tests/caddy-layout.sh
# What the basemap host runs and serves, pinned. infra/server/tiles.sh
# installs nothing whose hash differs from the values below.
#
# go-pmtiles (BSD-3-Clause, github.com/protomaps/go-pmtiles): the tile server
# and the archive tools. The hashes are those of the release tarballs, the
# same as the "digest" GitHub records for each asset (gh release view
# v1.31.2 -R protomaps/go-pmtiles --json assets), checked again here after a
# download on 2026-10-06. To move to another release: read the new digests,
# download both tarballs, compare with shasum -a 256, update the four lines.
PMTILES_VERSION=1.31.2
PMTILES_URL_AMD64=https://github.com/protomaps/go-pmtiles/releases/download/v1.31.2/go-pmtiles_1.31.2_Linux_x86_64.tar.gz
PMTILES_SHA256_AMD64=3ed7dbf4ec2e6dfe5e25b6f70d1ffc932729f93c86db353bf514dd71010a312f
PMTILES_URL_ARM64=https://github.com/protomaps/go-pmtiles/releases/download/v1.31.2/go-pmtiles_1.31.2_Linux_arm64.tar.gz
PMTILES_SHA256_ARM64=f8bd47e7ea866863489cad588fbaf2f31f42e5821f7a03f009b3769f05801cb1
# macOS on Apple silicon, for infra/tests/caddy-layout.sh without Docker.
PMTILES_URL_DARWIN_ARM64=https://github.com/protomaps/go-pmtiles/releases/download/v1.31.2/go-pmtiles-1.31.2_Darwin_arm64.zip
PMTILES_SHA256_DARWIN_ARM64=40528f7f616fcbf91207cd48c8fc023d213f6d86c0cbf1f748732803d1880f3d

# Fonts and sprites from github.com/protomaps/basemaps-assets at one commit:
# the Noto Sans glyph ranges the Protomaps styles name (SIL Open Font
# License 1.1, fonts/OFL.txt) and the v4 sprites (derived from the
# MIT-licensed tangrams/icons). GitHub may regenerate its tarballs, so the
# pin is a hash of the files themselves, computed by infra/tiles/assets-hash.py
# over the subset installed. To move to another commit: download its tarball,
# extract it, run assets-hash.py on it, update both lines.
BASEMAPS_ASSETS_COMMIT=028c18f713baecad011301ff7a69acc39bcc2ae7
BASEMAPS_ASSETS_TREE_SHA256=e45a689f8e2e96788b1bdfd502a23e7739b4b9697de7f5709d541d494b8a8c64

# The tile schema major version the refresh accepts. Protomaps publishes
# daily planet builds of schema 4, which the @protomaps/basemaps styles from
# 4.0.0 on read; a schema 5 would need new styles in the app first, so the
# refresh never moves to it by itself.
PROTOMAPS_SCHEMA_MAJOR=4

# A tiny archive from the go-pmtiles test suite (one z0 tile), used by
# infra/tests/caddy-layout.sh to exercise the tile routes without the planet.
PMTILES_TEST_FIXTURE_URL=https://raw.githubusercontent.com/protomaps/go-pmtiles/v1.31.2/pmtiles/fixtures/test_fixture_1.pmtiles
PMTILES_TEST_FIXTURE_SHA256=f3f65093582c81625cdfab11b3d1a27c2fb6aadcf8bd9802b2ad694d4d7cdca5
