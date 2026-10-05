#!/bin/sh
# One-time setup of a clone, idempotent. The session preflight runs the same
# checks for Claude Code and Cursor sessions; any other agent or human runs
# this once after cloning:
#
#   sh tool/setup.sh
#
# It activates the tracked git hooks and says what is still missing.
set -u
cd "$(dirname "$0")/.." || exit 2

if [ "$(git config --local core.hooksPath 2>/dev/null)" != ".githooks" ]; then
  git config core.hooksPath .githooks && echo "setup: git hooks activated (.githooks)"
fi

pinned=$(sed -n 's/.*"flutter": "\([^"]*\)".*/\1/p' .fvmrc)
if command -v fvm >/dev/null 2>&1; then
  fvm list 2>/dev/null | grep -q "$pinned" || echo "setup: Flutter $pinned is not installed yet: run \`fvm install\`"
else
  echo "setup: fvm is not installed (https://fvm.app); the repo pins Flutter $pinned"
fi

rust=$(sed -n 's/^channel = "\([^"]*\)".*/\1/p' backend/rust-toolchain.toml)
if command -v rustup >/dev/null 2>&1; then
  rustup toolchain list | grep -q "^$rust" \
    || echo "setup: Rust $rust is not installed yet: \`rustup toolchain install $rust --profile minimal -c rustfmt -c clippy\`"
else
  echo "setup: rustup is not installed (https://rustup.rs); the backend pins Rust $rust"
fi
for tool in cargo-nextest cargo-deny; do
  command -v "$tool" >/dev/null 2>&1 || echo "setup: $tool is missing: \`cargo install $tool --locked\`"
done
exit 0
