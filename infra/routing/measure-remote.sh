#!/bin/bash
# Measures the France graph build where it would really run: an ephemeral
# Hetzner server of the Lunaway project (x86, cpx42: 8 vCPU, 16 GB, 320 GB,
# about 0.11 EUR an hour excl. VAT), never the maintainer's Mac nor the
# production backend. The server exists only for the measurement.
#
#   infra/routing/measure-remote.sh create     server and firewall (SSH from LUNAWAY_SSH_ALLOW only)
#   infra/routing/measure-remote.sh run        copies the sources and starts measure-remote-run.sh
#   infra/routing/measure-remote.sh pipeline   the same, the whole pipeline only
#   infra/routing/measure-remote.sh status     the run's last lines
#   infra/routing/measure-remote.sh collect    the results into data/tmp/routing/remote/
#   infra/routing/measure-remote.sh delete     server and firewall, gone
#
# Both resources are named lunaway-routing-measure and labelled
# project=lunaway,purpose=routing-measure,managed-by=claude.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
. infra/lib.sh
require_hcloud

NAME=lunaway-routing-measure
LABELS=(--label project=lunaway --label purpose=routing-measure --label managed-by=claude)
KNOWN=data/tmp/routing/remote/known_hosts
mkdir -p data/tmp/routing/remote

ip() { hcloud server ip "$NAME"; }
remote() {
  ssh -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$KNOWN" \
    -o IdentitiesOnly=yes -i "$LUNAWAY_SSH_IDENTITY" -o ConnectTimeout=15 "root@$(ip)" "$@"
}

case "${1:-}" in
  create)
    [ -n "${LUNAWAY_SSH_ALLOW:-}" ] || die "set LUNAWAY_SSH_ALLOW"
    rules="["
    sep=""
    for cidr in $LUNAWAY_SSH_ALLOW; do
      rules="$rules$sep{\"direction\":\"in\",\"protocol\":\"tcp\",\"port\":\"22\",\"source_ips\":[\"$cidr\"]}"
      sep=","
    done
    rules="$rules]"
    if ! hcloud firewall describe "$NAME" >/dev/null 2>&1; then
      printf '%s' "$rules" | hcloud firewall create --name "$NAME" --rules-file - "${LABELS[@]}" >/dev/null
    fi
    hcloud server create --name "$NAME" --type cpx42 --location fsn1 --image docker-ce \
      --ssh-key "$LUNAWAY_SSH_KEY_NAME" --firewall "$NAME" "${LABELS[@]}" >/dev/null
    log "server $NAME created at $(ip); waiting for SSH"
    for _ in $(seq 1 60); do
      remote true 2>/dev/null && break
      sleep 5
    done
    remote 'uname -m; nproc; free -g | head -2; df -h / | tail -1'
    ;;
  run | pipeline)
    # The sources the run needs, nothing else: the routing scripts, the
    # backend without its build directory, and IGN's cached sections.
    # COPYFILE_DISABLE keeps macOS's tar from adding AppleDouble files
    # (`._name`), which the migrations directory must not hold.
    dest="/root/src-$(date -u +%H%M%S)"
    COPYFILE_DISABLE=1 tar -cf - --exclude backend/target infra/routing backend data/raw/ign-bdtopo \
      | remote "mkdir -p $dest && tar -xf - -C $dest && ln -sfn $dest /root/lunaway"
    phase=all
    [ "$1" = pipeline ] && phase=pipeline
    remote "nohup /root/lunaway/infra/routing/measure-remote-run.sh $phase >/root/run.log 2>&1 </dev/null &"
    log "started ($phase); follow with: infra/routing/measure-remote.sh status"
    ;;
  status)
    remote 'tail -n 15 /root/run.log; uptime'
    ;;
  collect)
    remote 'cd /root/lunaway && tar -cf - run.done data/tmp/routing/measure-france-x86/summary.txt data/tmp/routing/measure-france-x86/memory.csv data/tmp/routing/measure-france-x86/disk.csv data/tmp/routing/measure-france-x86/build.log data/tmp/routing/pipeline 2>/dev/null; cat /root/run.log >&2' \
      2>data/tmp/routing/remote/run.log | tar -xf - -C data/tmp/routing/remote
    ls -R data/tmp/routing/remote | head -40
    ;;
  delete)
    hcloud server delete "$NAME" || true
    hcloud firewall delete "$NAME" || true
    hcloud server list -l purpose=routing-measure
    hcloud firewall list -l purpose=routing-measure
    ;;
  *)
    die "usage: $0 create|run|pipeline|status|collect|delete"
    ;;
esac
