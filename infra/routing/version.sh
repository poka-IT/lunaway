# Pins of the routing engine, sourced by the scripts of infra/routing/ and
# named by the server's container unit (infra/routing/valhalla.container,
# which cannot source a file: keep its Image= line equal to VALHALLA_IMAGE).
#
# Valhalla 3.9.1 (MIT), the official image, pinned by the digest of its
# multi-architecture index (amd64 and arm64), read from the registry's
# manifest of ghcr.io/valhalla/valhalla:3.9.1 on 2026-10-11 (the same
# reading gives 3.9.0's pinned digest, sha256:511c095b...a5a63c). A graph is
# served by the same version that built it: a new version means a new
# build, its route tests, then a new unit. 3.9.1 changes what the build
# writes (nodes sorted along a Hilbert curve, valhalla/valhalla#6342) and
# how a route crosses destination-only edges (#6364): it came with a graph
# of its own (plan/research/127-routage-serveur.md).
VALHALLA_VERSION=3.9.1
VALHALLA_IMAGE=ghcr.io/valhalla/valhalla@sha256:4fd114eb1d26b8fc2f43bcb3df234c1b63a0bf13c277405e5943d5361dc575de
