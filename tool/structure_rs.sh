#!/bin/sh
# The backend invariants of AGENTS.md that a grep can hold.
#
#   sh tool/structure_rs.sh      # from anywhere in the repository; exits 1 on a breach
#
#   - the domain crate stays pure: no runtime, database, HTTP or GraphQL crate;
#   - cargo-deny and cargo-audit ignore the same advisories.
set -u
cd "$(git rev-parse --show-toplevel)" || exit 2
fail=0

domain=backend/crates/lunaway-domain/Cargo.toml
if [ -f "$domain" ]; then
  impure=$(awk '/^\[/{section=$0} section ~ /^\[(dev-)?dependencies\]$/ && section !~ /dev-/' "$domain" \
    | grep -E '^(tokio|sqlx|axum|reqwest|async-graphql|hyper|tower)[ =.]' || true)
  if [ -n "$impure" ]; then
    echo "structure_rs [domain-pure]: lunaway-domain depends on an I/O crate:" >&2
    echo "$impure" | sed 's/^/  /' >&2
    echo "  Fix: keep I/O in lunaway-api or a service crate; the domain holds types and rules only." >&2
    fail=1
  fi
fi

deny_ids=$(grep -oE 'RUSTSEC-[0-9]{4}-[0-9]{4}' backend/deny.toml 2>/dev/null | sort -u)
audit_ids=$(grep -oE 'RUSTSEC-[0-9]{4}-[0-9]{4}' backend/.cargo/audit.toml 2>/dev/null | sort -u)
if [ "$deny_ids" != "$audit_ids" ]; then
  echo "structure_rs [advisory-parity]: backend/deny.toml and backend/.cargo/audit.toml ignore different advisories:" >&2
  echo "  deny.toml:  $(echo $deny_ids)" >&2
  echo "  audit.toml: $(echo $audit_ids)" >&2
  echo "  Fix: keep the two lists identical, each ignore with its reachability argument." >&2
  fail=1
fi

[ "$fail" -eq 0 ] && echo "structure_rs: OK"
exit $fail
