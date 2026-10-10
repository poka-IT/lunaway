#!/usr/bin/env bash
# Entry point on the server, run as root by infra/configure.sh: applies the
# steps of its role in order, or only the ones named.
#
#   sudo env LUNAWAY_ROLE=backend LUNAWAY_VOLUME_ID=... bash ~/infra/server/setup.sh [step...]
#   backend: harden data-volume postgres caddy tiles backups api pipeline routing
#            geocode translate ops-status ops-access
#
# ops-status comes before ops-access: it makes the status page's probe key,
# which ops-access lets in.
. "$(dirname "$0")/common.sh"
need_root
case "${LUNAWAY_ROLE:-}" in
  backend) default_steps="harden data-volume postgres caddy tiles backups api pipeline routing geocode translate ops-status ops-access" ;;
  *) die "set LUNAWAY_ROLE to backend" ;;
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
