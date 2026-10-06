#!/bin/sh
# The nightly ops job of the maintainer's Mac, run by launchd
# (legal.p2p.lunaway.ops, 04:30 local time) and installed by
# infra/ops/mac/install.sh. It is the only piece outside Hetzner:
#
#   1. pulls the encrypted dump replica from the ops server (a key forced to
#      a read-only rsync), into ~/Backups/lunaway, 30 days kept
#   2. checks the newest dump: recent, no failure recorded after the last
#      success, decrypts (the age key exists only here) and lists with
#      pg_restore, without writing the plaintext anywhere
#   3. reads the state of every check of the status page (Gatus)
#   4. opens or updates one GitHub issue "ops: alerte" when something fails,
#      and closes it when everything is green again. The issue names the
#      failing checks only: no address, no key, no file path of a server.
#
# Settings come from the plist (EnvironmentVariables):
#   LUNAWAY_STATUS_URL     base URL of the status page
#   LUNAWAY_ALERT_REPO     the repository of the issue (owner/name)
#   LUNAWAY_ALERT_GH_USER  the gh account that writes it, whatever account
#                          is active in gh
#   LUNAWAY_OPS_DRILL=1    adds a fake failure, to test the alert path
#                          (infra/ops/mac/install.sh drill)
set -u
umask 077
PATH=/opt/homebrew/bin:/opt/homebrew/opt/libpq/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
export PATH

conf="$HOME/.config/lunaway"
dest="$HOME/Backups/lunaway"
status_url="${LUNAWAY_STATUS_URL:?set LUNAWAY_STATUS_URL}"
repo="${LUNAWAY_ALERT_REPO:-poka-IT/lunaway}"
gh_user="${LUNAWAY_ALERT_GH_USER:-poka-IT}"
title="ops: alerte"
keep_days=30
now=$(date -u +%s)
failures=""

say() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $*"; }
fail() {
	say "FAIL $1"
	failures="${failures}- $1
"
}
# Everything below comes from the ops server, which this job does not trust
# with the issue's text: a stamp is kept only when it is exactly one, a name
# only when it is plain.
# A dump stamp (20261006T001502Z) read from FILE, empty when it is not one.
read_stamp() {
	[ -r "$1" ] || return 0
	head -c 32 "$1" | grep -E '^[0-9]{8}T[0-9]{6}Z$' || true
}
# The seconds since 1970 of a dump stamp, empty if not one.
stamp_seconds() {
	printf '%s' "$1" | grep -qE '^[0-9]{8}T[0-9]{6}Z$' || return 0
	date -j -u -f %Y%m%dT%H%M%SZ "$1" +%s 2>/dev/null
}

say "start"
mkdir -p "$dest"

# 1. The pull. The ops server reboots at 02:30 UTC when an update asks for
# it, which is 04:30 in Paris in summer: three attempts, two minutes apart.
pulled=no
for attempt in 1 2 3; do
	if rsync -rt --timeout=300 -e "ssh -F $conf/ssh_config" lunaway-ops-pull: "$dest/"; then
		pulled=yes
		say "pulled: $(find "$dest" -maxdepth 1 -name 'lunaway-*.dump.age' | wc -l | tr -d ' ') dumps on the Mac"
		break
	fi
	say "pull attempt $attempt failed"
	[ "$attempt" = 3 ] || sleep 120
done
[ "$pulled" = yes ] || fail "copie des sauvegardes depuis le serveur ops vers le Mac"

# 2. The newest dump, by name; its age is the one the archive records
# inside, which age authenticates, so a renamed old dump does not pass.
newest=$(find "$dest" -maxdepth 1 -name 'lunaway-[0-9]*T[0-9]*Z.dump.age' | sort | tail -n 1)
if [ -z "$newest" ]; then
	fail "aucun dump sur le Mac"
else
	# age authenticates the whole file as it decrypts, and pg_restore reads
	# the archive's table of contents. Homebrew's pg_restore cannot
	# decompress zstd, so it lists without reading the data (and says so on
	# stderr); restoring data takes Debian's pg_restore (docs/deploy.md).
	if age --decrypt --identity "$conf/backup-age.key" "$newest" | TZ=UTC pg_restore --list > "$dest/.last-list" 2> "$dest/.last-list.err"; then
		created=$(sed -n 's/^; Archive created at \([0-9-]* [0-9:]*\) UTC$/\1/p' "$dest/.last-list" | head -n 1)
		at=$(date -j -u -f '%Y-%m-%d %H:%M:%S' "$created" +%s 2>/dev/null || true)
		if [ -z "$at" ]; then
			fail "le dump le plus récent ne dit pas quand il a été créé"
		elif [ $(( (now - at) / 3600 )) -ge 36 ]; then
			fail "le dump le plus récent a été créé il y a plus de 36 heures ($created UTC)"
		fi
		say "verified $(basename "$newest"): decrypted, created $created UTC, $(grep -c ' TABLE DATA ' "$dest/.last-list") tables listed"
	else
		cat "$dest/.last-list.err"
		fail "le dump le plus récent ne se déchiffre pas ou pg_restore ne le lit pas"
	fi
fi
last_success=$(read_stamp "$dest/last-success")
last_failure=$(read_stamp "$dest/last-failure")
if [ -n "$last_failure" ]; then
	failure_at=$(stamp_seconds "$last_failure")
	success_at=$(stamp_seconds "$last_success")
	if [ -n "$failure_at" ] && [ "$failure_at" -gt "${success_at:-0}" ]; then
		fail "le dump nocturne du serveur a échoué ($last_failure)"
	fi
fi

# Retention: the dumps whose date is more than keep_days days old.
cutoff=$(date -u -v-"${keep_days}"d +%Y%m%d)
for f in "$dest"/lunaway-*.dump.age "$dest"/globals-*.sql.age; do
	[ -e "$f" ] || continue
	day=$(basename "$f" | sed -E 's/^[a-z]+-([0-9]{8})T.*/\1/')
	case "$day" in
	[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]) ;;
	*) continue ;;
	esac
	if [ "$day" -lt "$cutoff" ]; then
		rm -f "$f"
		say "dropped $(basename "$f")"
	fi
done

# 3. The status page.
if statuses=$(curl -fsS -m 30 "$status_url/api/v1/endpoints/statuses"); then
	failing=$(printf '%s' "$statuses" | jq -r '.[] | select((.results | last | .success) != true) | "\(.group) / \(.name)"' \
		| sed -E 's#^.*[^A-Za-z0-9 ./-].*$#(un contrôle au nom inattendu)#')
	if [ -n "$failing" ]; then
		echo "$failing" | while IFS= read -r check; do say "FAIL check: $check"; done
		failures="${failures}$(echo "$failing" | sed 's/^/- contrôle en échec : /')
"
	fi
	say "status page: $(printf '%s' "$statuses" | jq 'length') checks read"
else
	fail "page de statut injoignable"
fi

[ "${LUNAWAY_OPS_DRILL:-0}" = 1 ] && fail "exercice d'alerte (LUNAWAY_OPS_DRILL=1), pas une vraie panne"

# 4. The issue.
GH_TOKEN=$(gh auth token --hostname github.com --user "$gh_user" 2>/dev/null)
if [ -z "$GH_TOKEN" ]; then
	say "no gh token for $gh_user: the issue cannot be written"
	[ -z "$failures" ] && exit 0
	exit 2
fi
export GH_TOKEN
# The plain list, not --search: the search index lags behind by seconds to
# minutes, and a lookup through it opened a second issue on 2026-10-06.
# Only an issue this job's account wrote: anyone may open one with this title.
open_issue=$(gh issue list --repo "$repo" --state open --author "$gh_user" --limit 500 --json number,title \
	--jq ".[] | select(.title == \"$title\") | .number" | head -n 1)
day=$(date +%Y-%m-%d)
if [ -n "$failures" ]; then
	body="Contrôle nocturne du $day, depuis le Mac de maintenance (infra/ops/mac/lunaway-ops.sh).

${failures}
Journal détaillé sur le Mac : ~/Library/Logs/lunaway-ops.log. Page de statut : voir docs/deploy.md, section Status page.
L'issue se ferme d'elle-même la nuit où tout repasse au vert."
	if [ -n "$open_issue" ]; then
		gh issue edit "$open_issue" --repo "$repo" --body "$body" >/dev/null \
			&& gh issue comment "$open_issue" --repo "$repo" --body "Toujours en échec le $day :

${failures}" >/dev/null \
			&& say "issue #$open_issue updated"
	else
		url=$(gh issue create --repo "$repo" --title "$title" --body "$body") && say "issue opened: $url"
	fi
	exit 1
fi
if [ -n "$open_issue" ]; then
	gh issue comment "$open_issue" --repo "$repo" --body "Tout est revenu au vert le $day." >/dev/null \
		&& gh issue close "$open_issue" --repo "$repo" >/dev/null \
		&& say "issue #$open_issue closed"
fi
say "all green"
