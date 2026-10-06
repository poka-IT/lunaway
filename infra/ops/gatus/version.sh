# shellcheck shell=bash
# shellcheck disable=SC2034 # read by infra/deploy-gatus.sh
# The Gatus release the ops server runs. Gatus publishes no binaries, only
# images; infra/deploy-gatus.sh copies the static binary out of the official
# image, pulled by the digest of its multi-architecture index (the same
# digest on docker.io/twinproduction/gatus and ghcr.io/twin/gatus on
# 2026-10-06), and the server installs it only when its SHA-256 is the one
# below. To move to another release: inspect the new tag
# (docker buildx imagetools inspect twinproduction/gatus:vX.Y.Z), put its
# index digest here, extract both binaries once to record their hashes, and
# run infra/deploy-gatus.sh.
GATUS_VERSION=5.37.0
GATUS_IMAGE=docker.io/twinproduction/gatus@sha256:094eb186e55235db367e90e9d56140e5897b7044c41de23cde4cc18e6da1242e
GATUS_SHA256_AMD64=bcc8030a927c1370206b44b63680f5efe6e921160bbccc42c80f49c5ea482540
GATUS_SHA256_ARM64=dac0f1d71e674ba25400dd362e779c2df088e4d2396c5be14a67eace99094a4f
