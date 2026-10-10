# shellcheck shell=bash
# shellcheck disable=SC2034 # read by the scripts that source this file
# The pins of the geocoders (docs/deploy.md, "Geocoding"): Photon's
# release and the databases it serves. Sourced by infra/server/geocode.sh on
# the server and by lunaway-photon-refresh.
#
# Photon (Apache 2.0, https://github.com/komoot/photon), the jar of the
# GitHub release, checked by its SHA-256 (computed on 2026-10-07 from the
# release asset).
PHOTON_VERSION="1.3.0"
PHOTON_JAR_URL="https://github.com/komoot/photon/releases/download/$PHOTON_VERSION/photon-$PHOTON_VERSION.jar"
PHOTON_JAR_SHA256="a89707c0045e4807b2a1180e132e68e108d998709f48b6c94b98a6e281f571a5"
# The database: GraphHopper's Europe dump for Photon 1.x, built from
# OpenStreetMap (ODbL), English, German, French, Italian and the local
# names. About 32 GB to download and 44 GB unpacked in October 2026,
# rebuilt by GraphHopper about weekly; a published MD5 beside it.
PHOTON_DUMP_URL="https://download1.graphhopper.com/public/europe/photon-db-europe-1.0-latest.tar.bz2"
# Morocco is not in it: imported on the server from GraphHopper's Africa
# dump (about 600 MB), with its MD5 too; 160 439 places in 168 s on the
# test server of 2026-10-07.
PHOTON_MOROCCO_DUMP_URL="https://download1.graphhopper.com/public/africa/photon-dump-africa-1.0-latest.jsonl.zst"
