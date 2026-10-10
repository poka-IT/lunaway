# shellcheck shell=bash
# shellcheck disable=SC2034 # read by infra/server/common.sh, infra/verify.sh, infra/tests/caddy-layout.sh and .github/workflows/caddy-release.yml
# The Caddy release the servers run, pinned. infra/server/common.sh
# installs the .deb of the official GitHub release
# (github.com/caddyserver/caddy/releases) only when it hashes to the SHA-512
# below, the value the release's checksums file gives; infra/caddy/pin.sh
# checks that file's signature with cosign before writing the values here.
# The project's apt repository on Cloudsmith has answered 402 Payment
# Required since 2026-10-09 (github.com/caddyserver/dist/issues/142), so no
# server has it as a source any more, and Caddy no longer updates itself:
# .github/workflows/caddy-release.yml goes red while a newer release is out,
# and moving to it is "Upgrading Caddy" in docs/deploy.md.
CADDY_VERSION=2.11.7
# The packages the servers install (infra/server/common.sh).
CADDY_DEB_SHA512_AMD64=47e8351c2317b427af14a103e763ca1118a3d2396a88b4c0669cdec9c4a68a957690194e2423a1633f53135741c33a41bdac2b55515b7d0f7adc8b733add50d9
CADDY_DEB_SHA512_ARM64=ac32f03f0eea04021f2d4e5d89bfd01b84ead115f2eba9d2a0d06447e86d4af932899e56f090993a566d0925dbd1063002929b395541a8c5f5e51d7039f7375a
# The tarballs infra/tests/caddy-layout.sh runs natively.
CADDY_TAR_SHA512_MAC_ARM64=68f592df8f0ec058fbdb9b137b64e9a0aa792d28c06e1e3b9ec12d0e7fb371683a54e73ef6d8e6d0dd70dc6b941a5b5d5b73faedd3f89de119ad2eb78bdc668e
CADDY_TAR_SHA512_LINUX_AMD64=a7a433a1b133efc3c8d10eb0b99d52a24b5ef5c322dc77f5282182b1c0402139ab83f3a99f0c52409df77d20123fb0b523edad8a66d8f5e49136197bf61ef0e7
