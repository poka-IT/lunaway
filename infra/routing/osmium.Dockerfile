# osmium-tool, which folds the change file of `lunaway routing prepare` into
# the OpenStreetMap extract before Valhalla reads it (`osmium apply-changes`).
# The Valhalla image ships no osmium; this one is built by
# infra/routing/build-graph.sh on the build machine, from Debian 13 pinned by
# the digest of its multi-architecture index (read with
# `docker buildx imagetools inspect debian:trixie-slim` on 2026-10-06), and
# Debian's own package (osmium-tool 1.18 in trixie, GPL-3.0; libosmium
# BSL-1.0).
FROM debian:trixie-slim@sha256:a29215f6a35e51e22adffa17f89e9d2ef06214e64a2bad10d765c46aea49f11f
RUN apt-get update \
    && apt-get install --yes --no-install-recommends osmium-tool \
    && rm -rf /var/lib/apt/lists/*
ENTRYPOINT ["osmium"]
