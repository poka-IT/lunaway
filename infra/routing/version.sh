# Pins of the routing engine, sourced by the scripts of infra/routing/ and
# named by the server's container unit (infra/routing/valhalla.container,
# which cannot source a file: keep its Image= line equal to VALHALLA_IMAGE).
#
# Valhalla 3.9.0 (MIT), the official image, pinned by the digest of its
# multi-architecture index (amd64 and arm64), read with
# `docker buildx imagetools inspect ghcr.io/valhalla/valhalla:3.9.0` on
# 2026-10-06. A graph is served by the same version that built it: a new
# version means a new build, its route tests, then a new unit.
VALHALLA_VERSION=3.9.0
VALHALLA_IMAGE=ghcr.io/valhalla/valhalla@sha256:511c095b8caf393dccceb8b519ec96b6f85a0166b2288ba014a8a748acc5a63c
