#!/usr/bin/env bash
# Pauses the long jobs of the lunaway CLI (imports, conflation, the
# worker, the open content's refresh, the packs) while a deploy migrates
# the database, then lets them go on where they stood (docs/deploy.md,
# "Deploying the API"). Run as root by infra/server/install-release.sh.
#
#   sudo bash pause-jobs.sh pause    # every job stopped between two transactions
#   sudo bash pause-jobs.sh resume   # every job paused goes on
#   sudo bash pause-jobs.sh status   # the jobs paused, and the sessions in a transaction
#
# A migration that alters a table waits for every transaction that read or
# wrote it, and gives up after its lock_timeout: on 2026-10-08 a deploy
# failed that way behind a query of the open content's refresh
# (plan/research/82-suites-4.md). Each job is stopped (SIGSTOP to every
# process of its unit) only while none of its sessions is inside a
# transaction, read in pg_stat_activity by the session's name
# (`lunaway:<unit>`, which the CLI takes from its cgroup), and checked
# again once stopped; then no other session may hold a transaction open
# for more than a few seconds. A job keeps its process and its place in
# its work: nothing restarts, nothing is lost. A transient timer resumes
# the jobs after LUNAWAY_PAUSE_MAX seconds should the deploy never do it;
# the next deploy resumes them too.
. "$(dirname "$0")/common.sh"
need_root

STATE=/run/lunaway-paused-jobs
PROC=/proc
CGROUP=/sys/fs/cgroup
# Seconds to reach a pause before giving up, and seconds the jobs may stay
# paused at most.
wait_s="${LUNAWAY_PAUSE_WAIT:-300}"
max_s="${LUNAWAY_PAUSE_MAX:-1800}"
[[ "$wait_s" =~ ^[0-9]{1,5}$ ]] || die "LUNAWAY_PAUSE_WAIT is a number of seconds"
[[ "$max_s" =~ ^[0-9]{1,5}$ ]] || die "LUNAWAY_PAUSE_MAX is a number of seconds"
# A transaction open longer than this holds a migration back.
long_s=5
SAFETY=lunaway-resume-jobs

now() { date +%s; }

# sql NAME SQL: one number from the database, NAME bound as :'name'.
sql() {
  printf '%s\n' "$2" | runuser -u postgres -- psql -X -At -q -v ON_ERROR_STOP=1 -v "name=$1" -d lunaway -f -
}

# The sessions of unit $1 inside a transaction.
busy() {
  sql "lunaway:$1" "-- busy
SELECT count(*) FROM pg_stat_activity WHERE application_name = :'name' AND xact_start IS NOT NULL;"
}

# The other sessions that would hold a migration back, by name: a
# transaction open for more than long_s seconds, or one whose client has
# sent nothing for a second (a process stopped inside it: a job whose
# sessions carry no name, as before the CLI named them, is stopped without
# being seen in a transaction).
holding() {
  sql "" "-- holding
SELECT coalesce(string_agg(coalesce(nullif(application_name, ''), usename::text, '?') || ' ' || pid, ', '), '')
FROM pg_stat_activity
WHERE datname = current_database() AND backend_type = 'client backend'
  AND pid <> pg_backend_pid() AND xact_start IS NOT NULL
  AND (xact_start < now() - interval '$long_s seconds'
    OR (state LIKE 'idle in transaction%' AND state_change < now() - interval '1 second'));"
}

# The running units whose processes run the lunaway CLI of a release, but
# the API and the migrations.
long_jobs() {
  local unit cg pid exe
  systemctl list-units --type=service --state=active,activating,deactivating,reloading \
    --plain --no-legend 'lunaway-*' | awk '{ print $1 }' | while read -r unit; do
    [[ "$unit" =~ ^lunaway-[A-Za-z0-9@._-]{1,48}\.service$ ]] || continue
    case "$unit" in lunaway-api.service | lunaway-migrate.service) continue ;; esac
    cg="$(systemctl show -p ControlGroup --value "$unit")"
    [[ "$cg" =~ ^/[A-Za-z0-9@._/-]+$ ]] && [ -r "$CGROUP$cg/cgroup.procs" ] || continue
    while read -r pid; do
      exe="$(readlink "$PROC/$pid/exe" 2>/dev/null || true)"
      if [[ "$exe" =~ ^/opt/lunaway/releases/[0-9]{8}T[0-9]{6}Z-[0-9a-z-]+/lunaway$ ]]; then
        echo "$unit"
        break
      fi
    done < "$CGROUP$cg/cgroup.procs"
  done
}

signal() { systemctl kill --kill-whom=all --signal="$1" "$2"; }

paused() { [ -f "$STATE" ] && grep -qxF -- "$1" "$STATE"; }

forget() {
  local kept
  kept="$(grep -vxF -- "$1" "$STATE" || true)"
  printf '%s\n' "$kept" | sed '/^$/d' > "$STATE.new"
  mv -f "$STATE.new" "$STATE"
}

# pause_unit UNIT DEADLINE: stops UNIT between two of its transactions;
# fails at DEADLINE.
pause_unit() {
  local unit="$1" deadline="$2"
  while :; do
    if [ "$(busy "$unit")" = 0 ]; then
      echo "$unit" >> "$STATE"
      signal SIGSTOP "$unit"
      # A statement the job sent just before it stopped still reaches the
      # server: look once it had the time to.
      sleep 0.5
      if [ "$(busy "$unit")" = 0 ]; then
        log "paused $unit"
        return 0
      fi
      signal SIGCONT "$unit"
      forget "$unit"
    fi
    [ "$(now)" -lt "$deadline" ] || return 1
    sleep 0.2
  done
}

resume() {
  local unit
  if [ -f "$STATE" ]; then
    while read -r unit; do
      [ -n "$unit" ] || continue
      signal SIGCONT "$unit" || echo "warning: $unit could not be resumed" >&2
      log "resumed $unit"
    done < "$STATE"
    rm -f "$STATE"
  fi
  systemctl stop "$SAFETY.timer" 2>/dev/null || true
}

pause() {
  local deadline unit held=""
  deadline=$(( $(now) + wait_s ))
  # Jobs a deploy left paused go on first: each pause starts from nothing.
  resume
  : > "$STATE"
  systemctl reset-failed "$SAFETY.timer" "$SAFETY.service" 2>/dev/null || true
  systemd-run --quiet --unit="$SAFETY" --on-active="$max_s" \
    /bin/bash "$(cd "$(dirname "$0")" && pwd)/pause-jobs.sh" resume
  for unit in $(long_jobs); do
    paused "$unit" && continue
    if ! pause_unit "$unit" "$deadline"; then
      resume
      die "$unit stayed inside a transaction for ${wait_s}s; every job goes on, nothing was migrated"
    fi
  done
  while :; do
    held="$(holding)"
    [ -n "$held" ] || break
    if [ "$(now)" -ge "$deadline" ]; then
      resume
      die "a transaction stayed open for ${wait_s}s ($held); every job goes on, nothing was migrated"
    fi
    sleep 1
  done
  log "long jobs paused: $(paste -sd ' ' "$STATE")"
}

case "${1:-}" in
  pause) pause ;;
  resume) resume ;;
  status)
    echo "paused: $( [ -s "$STATE" ] && paste -sd ' ' "$STATE" || echo none)"
    echo "transactions open for more than ${long_s}s: $(holding)"
    ;;
  *) die "usage: $0 pause|resume|status" ;;
esac
