#!/usr/bin/env bash
# Pauses the long jobs of the lunaway CLI (imports, conflation, the
# worker, the open content's refresh, the packs) while a deploy migrates
# the database, then lets them go on where they stood (docs/deploy.md,
# "Deploying the API"). Installed as /usr/local/sbin/lunaway-pause-jobs
# and run as root by infra/server/install-release.sh.
#
#   sudo lunaway-pause-jobs pause    # every job stopped between two transactions
#   sudo lunaway-pause-jobs resume   # every job paused goes on
#   sudo lunaway-pause-jobs status   # the jobs paused, and what holds a pause back
#
# A migration that alters a table waits for every transaction that read or
# wrote it, and gives up after its lock_timeout: on 2026-10-08 a deploy
# failed that way behind a query of the open content's refresh
# (plan/research/82-suites-4.md). Each job is stopped (SIGSTOP to every
# process of its unit) only while none of its sessions is inside a
# transaction, read in pg_stat_activity by the session's name
# (`lunaway:<unit>`, which the CLI takes from its cgroup), and checked
# again once stopped; a job none of whose sessions carries its name (a CLI
# from before the names, or one not connected) is left running. Then no
# other session may hold a transaction open for more than a few seconds,
# or stay idle inside one. A job keeps its process and its place in its
# work: nothing restarts, nothing is lost. Whatever stops the pause
# halfway lets the jobs go on; a transient timer resumes them after
# LUNAWAY_PAUSE_MAX seconds should the deploy never do it, and the next
# pause resumes them first.
set -Eeuo pipefail
umask 022

die() { echo "error: $*" >&2; exit 1; }
log() { echo "==> $*"; }
need_root() { [ "$(id -u)" -eq 0 ] || die "run as root (sudo)"; }
need_root

STATE=/run/lunaway-paused-jobs
PROC=/proc
CGROUP=/sys/fs/cgroup
SELF=/usr/local/sbin/lunaway-pause-jobs
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

# sql NAME SQL: one line from the database, NAME bound as :'name'.
sql() {
  printf '%s\n' "$2" | runuser -u postgres -- psql -X -At -q -v ON_ERROR_STOP=1 -v "name=$1" -d lunaway -f -
}

# The sessions named after unit $1, and those of them inside a transaction.
sessions() {
  sql "lunaway:$1" "-- sessions
SELECT count(*) || ' ' || count(*) FILTER (WHERE xact_start IS NOT NULL)
FROM pg_stat_activity WHERE application_name = :'name';"
}

# The other sessions that would hold a migration back, by name: a
# transaction open for more than long_s seconds, or one whose client has
# sent nothing for a second (a process stopped inside it).
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
# the API and the migrations. A name the CLI would not give its sessions
# (more than 55 characters, lunaway_db::session_name) is left out.
long_jobs() {
  local unit cg pid exe
  systemctl list-units --type=service --state=active,activating,deactivating,reloading \
    --plain --no-legend 'lunaway-*' | awk '{ print $1 }' | while read -r unit; do
    [[ "$unit" =~ ^lunaway-[A-Za-z0-9@._-]{1,39}\.service$ ]] || continue
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
# leaves it running when none of its sessions carries its name; fails at
# DEADLINE.
pause_unit() {
  local unit="$1" deadline="$2" seen named open
  while :; do
    seen="$(sessions "$unit")"
    named="${seen% *}"
    open="${seen#* }"
    if [ "$named" = 0 ]; then
      log "not paused: no session of $unit carries its name"
      return 0
    fi
    if [ "$open" = 0 ]; then
      echo "$unit" >> "$STATE"
      signal SIGSTOP "$unit"
      # A statement the job sent just before it stopped still reaches the
      # server: look once it had the time to.
      sleep 0.5
      seen="$(sessions "$unit")"
      if [ "${seen#* }" = 0 ]; then
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
    rm -f "$STATE" "$STATE.new"
  fi
  systemctl stop "$SAFETY.timer" 2>/dev/null || true
}

pause() {
  local deadline unit held=""
  deadline=$(( $(now) + wait_s ))
  # Jobs a deploy left paused go on first: each pause starts from nothing.
  resume
  # Whatever stops the pause halfway (an error, the deploy interrupted)
  # lets the jobs go on.
  trap 'resume' ERR
  trap 'resume; exit 130' INT TERM HUP
  : > "$STATE"
  systemctl reset-failed "$SAFETY.timer" "$SAFETY.service" 2>/dev/null || true
  systemd-run --quiet --unit="$SAFETY" --on-active="$max_s" "$SELF" resume
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
  trap - ERR INT TERM HUP
  log "long jobs paused: $( [ -s "$STATE" ] && paste -sd ' ' "$STATE" || echo none)"
}

case "${1:-}" in
  pause) pause ;;
  resume) resume ;;
  status)
    echo "paused: $( [ -s "$STATE" ] && paste -sd ' ' "$STATE" || echo none)"
    echo "transactions holding a pause back: $(holding)"
    ;;
  *) die "usage: $0 pause|resume|status" ;;
esac
