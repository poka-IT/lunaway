#!/usr/bin/env bash
# Entry point on a server, run as root by infra/configure.sh: applies the
# steps of its role in order, or only the ones named.
#
#   sudo env LUNAWAY_ROLE=backend LUNAWAY_VOLUME_ID=... bash ~/infra/server/setup.sh [step...]
#   backend: harden data-volume postgres caddy tiles backups api pipeline ops-access
#   ops:     harden data-volume ops-replica ops-status
. "$(dirname "$0")/common.sh"
need_root
case "${LUNAWAY_ROLE:-}" in
  backend) default_steps="harden data-volume postgres caddy tiles backups api pipeline ops-access" ;;
  ops) default_steps="harden data-volume ops-replica ops-status" ;;
  *) die "set LUNAWAY_ROLE to backend or ops" ;;
esac
steps="${*:-$default_steps}"
for step in $steps; do
  case " $default_steps " in
    *" $step "*) ;;
    *) die "$step is not a step of the $LUNAWAY_ROLE role ($default_steps)" ;;
  esac
  echo
  echo "######## $step"
  bash "$INFRA/server/$step.sh"
done
