#!/opt/homebrew/bin/bash
# The weekly Europe routing graph, orchestrated from the maintainer's Mac
# (docs/deploy.md, "Routing"). Run by launchd (legal.p2p.lunaway.routing-build,
# Sundays; legal.p2p.lunaway.routing-sweep, hourly) and installed by
# infra/ops/mac-routing/install.sh.
#
#   lunaway-routing-build.sh run [--force] [--overlay DIR] [--dry-run]
#       waits until every Geofabrik extract carries the same date, creates a
#       throwaway build server (ccx33), runs infra/routing/europe-build.sh
#       there from a commit of the public repository, brings the bundle
#       back, deletes the server (also on failure or past the time budget),
#       checks the bundle, signs its sums with the Mac's routing key and
#       publishes it as the release `routing-graph`, which the backend pulls
#       (lunaway-routing-refresh). Nothing is built when the published graph
#       already has the extracts' date, unless --force. --overlay DIR puts
#       DIR/infra/routing over the commit (a change not pushed yet).
#       --dry-run stops before creating anything, after the sweep, the
#       disk check, the extracts' date and the published graph.
#   lunaway-routing-build.sh sweep
#       deletes every server and firewall labelled purpose=routing-build
#       created more than 8 hours ago: what a run killed with the Mac
#       (power cut, reboot) could not delete itself.
#
# Why the Mac: the build needs 16.5 GiB of anonymous memory and 171 GB of
# disk (plan/research/31-routage-europe.md), beyond a GitHub-hosted runner
# and the backend. The Mac already holds the Hetzner context of the project
# and the GitHub login; neither goes anywhere else. The build server runs the
# build's third-party code (crates, images, parsers) and receives no key and
# no token: the Mac pulls its result over SSH, with the server's host key
# generated here and pinned before the first connection.
#
# The Mac signs, with ~/.config/lunaway/routing-signing_ed25519, whose public
# half is a line of infra/routing/routing-signers. It recomputes every sum
# from the files received and checks build.json as the old publish job did:
# the server is not trusted to name its graph or its sums.
#
# State for the nightly job (infra/ops/mac/lunaway-ops.sh), in
# ~/Library/Application Support/Lunaway/routing/state: digits and plain
# words only, `last_success=<epoch>`, `last_run=<epoch> <ok|nothing|failed>`,
# `swept=<epoch> <count>`.
set -u -o pipefail
umask 077
PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
export PATH

conf="$HOME/.config/lunaway"
# shellcheck disable=SC1091 # the private settings, written by infra/ scripts
. "$conf/env"
support="$HOME/Library/Application Support/Lunaway/routing"
state_file="$support/state"
signers="$support/routing-signers"
signing_key="$conf/routing-signing_ed25519"
bundles="$HOME/Library/Caches/lunaway-routing"
logs="$HOME/Library/Logs/lunaway-routing"
ctx="${LUNAWAY_HCLOUD_CONTEXT:?set LUNAWAY_HCLOUD_CONTEXT in $conf/env}"
ssh_identity="${LUNAWAY_SSH_IDENTITY:?set LUNAWAY_SSH_IDENTITY in $conf/env}"
ssh_key_name="${LUNAWAY_SSH_KEY_NAME:?set LUNAWAY_SSH_KEY_NAME in $conf/env}"
repo="${LUNAWAY_ROUTING_REPO:-poka-IT/lunaway}"
gh_user="${LUNAWAY_ALERT_GH_USER:-poka-IT}"
release=routing-graph
geofabrik=https://download.geofabrik.de
ua="Lunaway routing graph build (+https://lunaway.net)"
# The server's whole life, from creation to deletion: the build took 3 h 26
# on 2026-10-06, the extracts may wait up to 3 h for one date, the copy back
# takes minutes.
budget_s=$((7 * 3600))
# The sweep's threshold: past it, a server is a leftover whatever its state.
# LUNAWAY_ROUTING_SWEEP_S lowers it for a test, when no build runs.
sweep_s=${LUNAWAY_ROUTING_SWEEP_S:-$((8 * 3600))}
[[ "$sweep_s" =~ ^[0-9]+$ ]] || { echo "LUNAWAY_ROUTING_SWEEP_S: seconds" >&2; exit 2; }
# How long the run waits, before creating anything, for Geofabrik's extracts
# to agree on one date (state.txt).
dates_wait_s=$((12 * 3600))
# The Mac keeps 50 GB free (the nightly job alerts below it); a bundle is
# 8.3 GB.
min_free_gb=60
labels=(--label project=lunaway --label purpose=routing-build --label managed-by=lunaway-mac)

say() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $*"; }
die() {
  say "FAIL $*"
  [ "${dry:-no}" = yes ] || record_run failed
  exit 1
}
hc() { hcloud --context "$ctx" "$@"; }
# What the build server says goes to the log as printable text only.
printable() { LC_ALL=C tr -cd '[:print:]\n\t'; }

# Rewrites one key of the state file (key=value lines).
state_set() {
  local key=$1 value=$2
  mkdir -p "$support"
  touch "$state_file"
  grep -v "^$key=" "$state_file" >"$state_file.new" || true
  echo "$key=$value" >>"$state_file.new"
  mv "$state_file.new" "$state_file"
}
recorded=no
record_run() {
  state_set last_run "$(date -u +%s) $1"
  recorded=yes
}

# Deletes the servers, then the firewalls, labelled purpose=routing-build
# and older than the threshold given (0: all of them).
sweep() {
  local older=$1 now count=0 name created
  now=$(date -u +%s)
  while IFS=$'\t' read -r name created; do
    [ -n "$name" ] || continue
    case "$name" in lunaway-routing-build-*) ;; *) continue ;; esac
    if [ $((now - created)) -ge "$older" ]; then
      if hc server delete "$name" >&2; then count=$((count + 1)); else say "could not delete server $name" >&2; fi
    fi
  done < <(hc server list -l purpose=routing-build -o json | jq -r '.[] | [.name, (.created | sub("\\+00:00$"; "Z") | fromdateiso8601)] | @tsv')
  while IFS=$'\t' read -r name created; do
    [ -n "$name" ] || continue
    case "$name" in lunaway-routing-build-*) ;; *) continue ;; esac
    # A firewall goes once no server uses it.
    if [ $((now - created)) -ge "$older" ] && [ "$(hc firewall describe "$name" -o json | jq '.applied_to | length')" = 0 ]; then
      if hc firewall delete "$name" >&2; then count=$((count + 1)); else say "could not delete firewall $name" >&2; fi
    fi
  done < <(hc firewall list -l purpose=routing-build -o json | jq -r '.[] | [.name, (.created | sub("\\+00:00$"; "Z") | fromdateiso8601)] | @tsv')
  echo "$count"
}

# The replication date Geofabrik publishes for each extract, one per line.
published_dates() {
  local path
  grep -E '^[a-z-]+/[a-z-]+$' "$support/europe-extracts.txt" | while read -r path; do
    curl --proto "=https" -fsS -m 30 --connect-timeout 10 --retry 3 -A "$ua" "$geofabrik/$path-updates/state.txt" \
      | sed -n 's/^timestamp=//p' | tr -d '\\' | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$' || echo "missing $path"
  done
}

# The extracts whose dated file of day $1 (YYMMDD) Geofabrik does not serve.
missing_files() {
  local path
  grep -E '^[a-z-]+/[a-z-]+$' "$support/europe-extracts.txt" | while read -r path; do
    curl --proto "=https" -fsS -I -m 30 --connect-timeout 10 --retry 3 -A "$ua" -o /dev/null "$geofabrik/$path-$1.osm.pbf" 2>/dev/null \
      || printf '%s ' "$path"
  done
}

cmd=${1:-}
case "$cmd" in
  sweep)
    swept=$(sweep "$sweep_s")
    if [ "${swept:-0}" -gt 0 ]; then
      say "swept $swept leftover resource(s) labelled purpose=routing-build"
      state_set swept "$(date -u +%s) $swept"
    fi
    exit 0
    ;;
  run) shift ;;
  *)
    echo "usage: $0 run [--force] [--overlay DIR] [--dry-run] | sweep" >&2
    exit 2
    ;;
esac

force=no
overlay=""
dry=no
while [ $# -gt 0 ]; do
  case "$1" in
    --force) force=yes; shift ;;
    --overlay) overlay=${2:?}; shift 2 ;;
    --dry-run) dry=yes; shift ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
done

mkdir -p "$support" "$bundles" "$logs"
# One run at a time; a lock left by a dead run is taken over.
lock="$support/run.lock"
if ! mkdir "$lock" 2>/dev/null; then
  if kill -0 "$(cat "$lock/pid" 2>/dev/null || echo 0)" 2>/dev/null; then
    say "another run is going on (pid $(cat "$lock/pid"))"
    exit 0
  fi
  say "taking over the lock of a dead run"
fi
echo $$ >"$lock/pid"

server=""
fw=""
# No space in this path: ssh splits UserKnownHostsFile on spaces.
scratch="$bundles/scratch"
cleanup() {
  local rc=$?
  # A run killed by a signal still counts as failed for the nightly job; a
  # dry run records nothing.
  [ "$rc" = 0 ] || [ "$recorded" = yes ] || [ "${dry:-no}" = yes ] || record_run failed
  if [ -n "$server" ] && hc server describe "$server" >/dev/null 2>&1; then
    hc server delete "$server" && say "server $server deleted"
  fi
  if [ -n "$fw" ] && hc firewall describe "$fw" >/dev/null 2>&1; then
    # The server's deletion releases the firewall a few seconds later.
    for _ in 1 2 3 4 5 6; do
      hc firewall delete "$fw" 2>/dev/null && { say "firewall $fw deleted"; break; }
      sleep 10
    done
  fi
  rm -f "$scratch/host_ed25519" "$scratch/host_ed25519.pub" "$scratch/known_hosts" \
    "$scratch/user-data.yaml" "$scratch/rules.json" "$scratch/overlay.tar"
  rm -f "$lock/pid"
  rmdir "$lock" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP

say "start"
for tool in hcloud gh jq ssh scp ssh-keygen shasum curl git; do
  command -v "$tool" >/dev/null || die "$tool is missing"
done
[ -f "$signing_key" ] || die "no signing key $signing_key (infra/ops/mac-routing/install.sh keys)"
[ -f "$signers" ] && [ -f "$support/europe-extracts.txt" ] || die "the support files are missing (infra/ops/mac-routing/install.sh)"

if [ "$dry" = yes ]; then
  say "dry run: routing-build resources now (the sweep deletes those older than 8 hours): $(hc server list -l purpose=routing-build -o json | jq -r '[.[].name] | join(" ")') $(hc firewall list -l purpose=routing-build -o json | jq -r '[.[].name] | join(" ")')"
else
  swept=$(sweep "$sweep_s")
  [ "${swept:-0}" = 0 ] || { say "swept $swept leftover resource(s)"; state_set swept "$(date -u +%s) $swept"; }
fi

free_gb=$(df -g "$HOME" | awk 'NR == 2 { print $4 }')
[ "${free_gb:-0}" -ge "$min_free_gb" ] || die "only ${free_gb} GB free on the Mac, $min_free_gb needed"

# 1. One date for every extract, before anything costs money.
waited=0
while :; do
  dates=$(published_dates)
  if printf '%s\n' "$dates" | grep -q '^missing'; then
    say "state.txt unreadable for: $(printf '%s\n' "$dates" | sed -n 's/^missing //p' | tr '\n' ' ')"
  elif [ "$(printf '%s\n' "$dates" | sort -u | wc -l | tr -d ' ')" = 1 ]; then
    # The dated files the build downloads must all be there too.
    day=$(printf '%s\n' "$dates" | head -n 1 | sed -E 's/^20([0-9]{2})-([0-9]{2})-([0-9]{2})T.*/\1\2\3/')
    missing=$(missing_files "$day")
    [ -n "$missing" ] || break
    say "dated files of $day missing for: $missing"
  else
    say "extracts range from $(printf '%s\n' "$dates" | sort | head -n 1) to $(printf '%s\n' "$dates" | sort | tail -n 1)"
  fi
  if [ "$dry" = yes ]; then
    say "dry run: the extracts do not agree yet; a run would wait for them (12 hours at most)"
    exit 0
  fi
  [ "$waited" -lt "$dates_wait_s" ] || die "the extracts did not agree on one date within $((dates_wait_s / 3600)) hours"
  # In the background and waited for, so a signal runs the exit trap at
  # once instead of after the sleep.
  sleep 1800 &
  wait $!
  waited=$((waited + 1800))
done
osm_date=$(printf '%s\n' "$dates" | head -n 1)
[[ "$day" =~ ^[0-9]{6}$ ]] || die "no day in $osm_date"
say "every extract at $osm_date, files of $day"

published=$(curl --proto "=https" -fsSL -m 60 --max-filesize 65536 -A "$ua" \
  "https://github.com/$repo/releases/download/$release/build.json" 2>/dev/null || true)
published_id=$(printf '%s' "$published" | jq -r '.id // empty' 2>/dev/null || true)
published_osm=$(printf '%s' "$published" | jq -r '.osm_data_at // empty' 2>/dev/null || true)
if [ "$force" = no ] && [[ "$published_id" == *-eu ]] && [ "$published_osm" = "$osm_date" ]; then
  say "the published graph $published_id already has the data of $osm_date: nothing to build"
  [ "$dry" = yes ] || record_run nothing
  exit 0
fi

# The commit of the public repository the server builds.
commit=$(git ls-remote "https://github.com/$repo.git" refs/heads/main | cut -f1)
[[ "$commit" =~ ^[0-9a-f]{40}$ ]] || die "cannot read the head of main"
say "source: $repo@$commit${overlay:+, infra/routing from $overlay}"
if [ "$dry" = yes ]; then
  say "dry run: would build the extracts of $day from $commit (published: ${published_id:-none}, data of ${published_osm:-none}); nothing created"
  exit 0
fi

# 2. The server: a firewall that lets SSH in from the admin sources only and
# lets out DNS, NTP, HTTP and HTTPS only (packages, crates, images,
# Geofabrik, IGN); no private network.
stamp=$(date -u +%Y%m%d%H%M)
server="lunaway-routing-build-$stamp"
fw="$server"
install -d -m 0700 "$scratch"
# No source wider than /16 or /48: after `infra/ssh-access.sh open`,
# 0.0.0.0/0 is no admin source (the floor of infra/server/ops-replica.sh).
python3 - "${LUNAWAY_SSH_ALLOW:?set LUNAWAY_SSH_ALLOW}" >"$scratch/rules.json" <<'EOF' || die "LUNAWAY_SSH_ALLOW holds no admin source narrower than /16 or /48"
import ipaddress, json, sys
nets = [ipaddress.ip_network(v, strict=False) for v in sys.argv[1].split()]
sources = [str(n) for n in nets if n.prefixlen >= (16 if n.version == 4 else 48)]
if not sources:
    sys.exit(1)
anywhere = ["0.0.0.0/0", "::/0"]
rules = [{"direction": "in", "protocol": "tcp", "port": "22", "source_ips": sources}]
for proto, port in (("tcp", "53"), ("udp", "53"), ("udp", "123"), ("tcp", "80"), ("tcp", "443")):
    rules.append({"direction": "out", "protocol": proto, "port": port, "destination_ips": anywhere})
rules.append({"direction": "out", "protocol": "icmp", "destination_ips": anywhere})
print(json.dumps(rules))
EOF
hc firewall create --name "$fw" --rules-file "$scratch/rules.json" "${labels[@]}" >/dev/null || die "cannot create the firewall"

# The host key, generated here and handed over by cloud-init, then pinned.
ssh-keygen -q -t ed25519 -N "" -C "$server" -f "$scratch/host_ed25519"
{
  echo "#cloud-config"
  echo "ssh_keys:"
  echo "  ed25519_private: |"
  sed 's/^/    /' "$scratch/host_ed25519"
  echo "  ed25519_public: $(cat "$scratch/host_ed25519.pub")"
} >"$scratch/user-data.yaml"
created=no
# The dedicated ccx33 is the measured build; the shared cx53 (32 GB, 320 GB)
# is the fallback when the type is out of stock or the project's dedicated
# core limit is reached.
for choice in "ccx33 fsn1" "ccx33 nbg1" "cx53 fsn1" "cx53 nbg1"; do
  read -r type location <<<"$choice"
  if out=$(hc server create --name "$server" --type "$type" --location "$location" --image docker-ce \
    --ssh-key "$ssh_key_name" --firewall "$fw" --user-data-from-file "$scratch/user-data.yaml" \
    "${labels[@]}" 2>&1); then
    created=yes
    say "server $server created: $type in $location"
    break
  fi
  say "$type in $location refused: $(printf '%s' "$out" | tail -n 1)"
done
rm -f "$scratch/host_ed25519" "$scratch/user-data.yaml"
[ "$created" = yes ] || { server=""; die "no build server could be created"; }
born=$(date -u +%s)
ip=$(hc server ip "$server")
echo "$ip $(cut -d' ' -f1,2 "$scratch/host_ed25519.pub")" >"$scratch/known_hosts"
# -F /dev/null: nothing of the user's SSH configuration (agent forwarding,
# other identities) reaches the server.
ssh_opts=(-F /dev/null -o IdentitiesOnly=yes -i "$ssh_identity" -o BatchMode=yes -o ConnectTimeout=15
  -o ServerAliveInterval=30 -o ServerAliveCountMax=4
  -o UserKnownHostsFile="$scratch/known_hosts" -o StrictHostKeyChecking=yes -o HostKeyAlgorithms=ssh-ed25519)
remote() { ssh "${ssh_opts[@]}" "root@$ip" "$@"; }
for _ in $(seq 1 60); do
  remote true 2>/dev/null && break
  sleep 5
done
remote 'cloud-init status --wait >/dev/null; nproc; free -g | sed -n 2p; df -h / | tail -n 1' || die "the server does not answer over SSH"

# 3. The source and the run.
remote "git init -q /root/lunaway && cd /root/lunaway && git fetch -q --depth 1 https://github.com/$repo.git $commit && git checkout -q FETCH_HEAD" \
  || die "the server cannot fetch $commit"
if [ -n "$overlay" ]; then
  COPYFILE_DISABLE=1 tar --no-xattrs --no-mac-metadata -C "$overlay" -cf "$scratch/overlay.tar" infra/routing || die "cannot pack $overlay/infra/routing"
  remote 'tar -xf - -C /root/lunaway' <"$scratch/overlay.tar" || die "cannot copy the overlay"
fi
# systemd ends the build at 6 hours whatever happens to this Mac; the time
# budget below deletes the server at 7.
remote 'mkdir -p /root/run && systemd-run --quiet --unit=lunaway-routing-build --setenv=HOME=/root --property=RuntimeMaxSec=21600 \
  --property=StandardOutput=append:/root/run/build.log --property=StandardError=append:/root/run/build.log \
  /root/lunaway/infra/routing/europe-build.sh '"$day" || die "cannot start the build"
say "build started on $server"

# 4. Watch it: every 5 minutes, its state; past the budget, or after 30
# minutes without an answer, it ends.
unreachable=0
last=""
while :; do
  sleep 300 &
  wait $!
  if [ $(($(date -u +%s) - born)) -ge "$budget_s" ]; then
    remote 'tail -n 20 /root/run/build.log | head -c 65536' 2>/dev/null | printable || true
    die "the build passed its budget of $((budget_s / 3600)) hours"
  fi
  if ! st=$(remote 'head -c 100 /root/run/state' 2>/dev/null | LC_ALL=C tr -cd 'a-z0-9 '); then
    unreachable=$((unreachable + 1))
    [ "$unreachable" -lt 6 ] || die "the build server has not answered for 30 minutes"
    continue
  fi
  unreachable=0
  [ "$st" = "$last" ] || say "build: $st"
  last=$st
  case "$st" in
    done) break ;;
    failed*)
      remote 'tail -n 40 /root/run/build.log | head -c 65536' 2>/dev/null | printable || true
      die "the build ended with: $st"
      ;;
  esac
done

# 5. The result, then the server goes at once.
run_logs="$logs/$stamp"
mkdir -p "$run_logs"
# The run's logs, 64 MiB each at most: the server ran third-party code as
# root, which could make one endless.
for f in build.log extracts.tsv source.txt test-routes.txt prepare.json build.json graph-build.log cli-build.log; do
  (ulimit -f 65536; scp -q "${ssh_opts[@]}" "root@$ip:/root/run/$f" "$run_logs/" </dev/null) 2>/dev/null || true
done
# The names and sizes first, bounded as the backend bounds them (8 parts
# of 2 GiB at most, 1 MiB for the small files, 512 MiB for the
# restrictions), and within this Mac's free disk less its 50 GB floor: the
# build ran third-party code as root, which could have grown the bundle.
listing=$(remote 'cd /root/out/bundle && stat -c "%s %n" -- * | head -n 32 | head -c 8192') || die "cannot list the bundle"
total=0
parts=0
free_now=$(( $(df -k "$HOME" | awk 'NR == 2 { print $4 }') * 1024 ))
while read -r size name; do
  [[ "$size" =~ ^[0-9]{1,12}$ ]] || die "unexpected size in the bundle listing"
  case "$name" in
    build.json | prepare.json | test-routes.txt) cap=$((1024 * 1024)) ;;
    restrictions.ndjson.gz) cap=$((512 * 1024 * 1024)) ;;
    SHA256SUMS) cap=65536 ;;
    graph.tar.gz.part-[0-9][0-9]) cap=$((2048 * 1024 * 1024)); parts=$((parts + 1)) ;;
    *) die "unexpected file in the bundle: $(printf '%s' "$name" | printable | head -c 80)" ;;
  esac
  [ "$size" -le "$cap" ] || die "$name is $size bytes, more than $cap"
  total=$((total + size))
done <<<"$listing"
[ "$parts" -ge 1 ] && [ "$parts" -le 8 ] || die "the bundle has $parts parts"
for f in build.json prepare.json restrictions.ndjson.gz test-routes.txt SHA256SUMS; do
  grep -qE "^[0-9]+ ${f//./\\.}\$" <<<"$listing" || die "the bundle has no $f"
done
[ "$total" -le $((free_now - 50 * 1000 * 1000 * 1000)) ] || die "the bundle ($total bytes) would leave less than 50 GB free on the Mac"
dir="$bundles/$stamp"
mkdir -p "$dir"
while read -r size name; do
  [ "$name" = SHA256SUMS ] && continue
  ok=no
  for _ in 1 2 3; do
    # A file that grows past its listed size stops the copy (SIGXFSZ).
    if (ulimit -f $(( (size + 1023) / 1024 )); scp -q "${ssh_opts[@]}" "root@$ip:/root/out/bundle/$name" "$dir/$name" </dev/null); then
      ok=yes
      break
    fi
    sleep 30
  done
  [ "$ok" = yes ] || die "cannot copy $name from the build server"
  [ "$(stat -f %z "$dir/$name")" = "$size" ] || die "$name changed size during the copy"
done <<<"$listing"
# The server's own sums only check the copy; they are not published.
remote 'head -c 65536 /root/out/bundle/SHA256SUMS' >"$dir/server-sums" || die "cannot read the server's sums"
hc server delete "$server" >/dev/null && say "server $server deleted ($(( ($(date -u +%s) - born) / 60 )) minutes)"
server=""
for _ in 1 2 3 4 5 6; do
  hc firewall delete "$fw" >/dev/null 2>&1 && { say "firewall $fw deleted"; fw=""; break; }
  sleep 10
done
cd "$dir" || die "cannot enter $dir"
# Only lines naming the files copied are read: the names come from the
# server, and shasum would open whatever path a line names.
grep -E '^[0-9a-f]{64}  (build\.json|prepare\.json|restrictions\.ndjson\.gz|test-routes\.txt|graph\.tar\.gz\.part-[0-9]{2})$' server-sums >copy-sums
[ "$(wc -l <copy-sums | tr -d ' ')" = "$(find . -maxdepth 1 -type f ! -name server-sums ! -name copy-sums | wc -l | tr -d ' ')" ] \
  || die "the server's sums do not name exactly the files copied"
shasum -a 256 --check --quiet copy-sums || die "the copy differs from the server's sums"
rm -f server-sums copy-sums

# 6. The checks of the old publish job: build.json is the CLI's flat
# object, its id and build time fall within this run, every route test
# passed.
jq -e 'type == "object"
  and (keys == ["built_at", "engine", "id", "ign_edition", "ign_fetched_at", "osm_data_at"])
  and all(.[]; type == "string" or type == "null")' build.json >/dev/null || die "build.json: not the flat object the CLI writes"
[ "$(grep -c '"id"' build.json)" = 1 ] || die "build.json: more than one id"
id=$(jq -r .id build.json)
[[ "$id" =~ ^[0-9]{8}T[0-9]{4}Z-eu$ ]] || die "build.json: $id is not a Europe graph name"
built_s=$(jq -r '.built_at | sub("\\.[0-9]+"; "") | fromdateiso8601' build.json) || die "build.json: no build time"
id_s=$(printf '%s' "$id" | sed -E 's/^([0-9]{4})([0-9]{2})([0-9]{2})T([0-9]{2})([0-9]{2})Z-eu$/\1-\2-\3T\4:\5:00Z/' | jq -R 'fromdateiso8601') \
  || die "build.json: no date in $id"
now=$(date -u +%s)
for t in "$built_s" "$id_s"; do
  [ "$t" -le "$now" ] && [ "$t" -ge $((born - 60)) ] || die "build.json: $id built at $(jq -r .built_at build.json) is outside this run"
done
[ "$(jq -r .osm_data_at build.json)" = "$osm_date" ] || die "build.json: data of $(jq -r .osm_data_at build.json), the extracts were at $osm_date"
grep -q '^all [0-9]* route tests passed$' test-routes.txt && ! grep -q '^FAIL' test-routes.txt || die "a route test failed"

# 7. Signed sums, then the release: the parts first, the signed sums next,
# build.json last, since the backend reads build.json to learn a new graph
# exists.
shasum -a 256 -- build.json prepare.json restrictions.ndjson.gz test-routes.txt graph.tar.gz.part-* >SHA256SUMS || die "cannot hash the bundle"
ssh-keygen -q -Y sign -f "$signing_key" -n lunaway-routing-graph SHA256SUMS || die "cannot sign"
ssh-keygen -Y verify -f "$signers" -I lunaway-routing -n lunaway-routing-graph -s SHA256SUMS.sig <SHA256SUMS >/dev/null \
  || die "the signature does not verify against routing-signers"
GH_TOKEN=$(gh auth token --hostname github.com --user "$gh_user" 2>/dev/null) || die "no gh token for $gh_user"
export GH_TOKEN
notes="Valhalla graph of Europe and Morocco for the Lunaway API, rebuilt weekly from the maintainer's Mac (infra/ops/mac-routing/). ODbL (OpenStreetMap contributors, Geofabrik extracts) and Licence Ouverte 2.0 (IGN, BD TOPO, France)."
gh release view "$release" --repo "$repo" >/dev/null 2>&1 \
  || gh release create "$release" --repo "$repo" --prerelease --title "Routing graph (weekly)" --notes "$notes" >/dev/null \
  || die "cannot create the release"
gh release edit "$release" --repo "$repo" --notes "$notes" >/dev/null || say "could not update the release notes"
upload() {
  local attempt
  for attempt in 1 2 3; do
    gh release upload "$release" --repo "$repo" --clobber "$@" && return 0
    say "upload of $* failed (attempt $attempt)"
    sleep 60
  done
  return 1
}
start=$(date -u +%s)
for part in graph.tar.gz.part-*; do upload "$part" || die "cannot upload $part"; done
upload restrictions.ndjson.gz prepare.json test-routes.txt || die "cannot upload the metadata"
upload SHA256SUMS SHA256SUMS.sig || die "cannot upload the sums"
upload build.json || die "cannot upload build.json"
say "published $id in $(( $(date -u +%s) - start )) s"
# Parts of a larger graph would confuse no one (the sums name the parts),
# but they take the release's room.
for asset in $(gh release view "$release" --repo "$repo" --json assets --jq '.assets[].name'); do
  [ -e "$asset" ] || gh release delete-asset "$release" "$asset" --repo "$repo" --yes
done

# 8. What stays here: the metadata and the signed sums, not the 8 GB.
cp build.json prepare.json test-routes.txt SHA256SUMS SHA256SUMS.sig "$run_logs/"
for f in graph.tar.gz.part-* restrictions.ndjson.gz build.json prepare.json test-routes.txt SHA256SUMS SHA256SUMS.sig; do
  rm -f "$dir/$f"
done
cd / && rmdir "$dir"
state_set last_success "$(date -u +%s)"
state_set last_graph "$id"
record_run ok
say "done: $id published; the backend installs it at its next refresh (04:30 UTC)"
