#!/bin/sh
# The nightly ops job of the maintainer's Mac, run by launchd
# (legal.p2p.lunaway.ops, 04:30 local time) and installed by
# infra/ops/mac/install.sh. It is the only piece outside Hetzner:
#
#   1. pulls the encrypted dump replica from the ops server (a key forced to
#      a read-only rsync), into ~/Backups/lunaway, 29 days kept, and the
#      encrypted photos into ~/Backups/lunaway/media; a photo the server's
#      list (media/manifest) no longer names goes to media-deleted/<day> here,
#      <day> being when the backend deleted it, and is dropped 26 days later
#   2. checks the newest dump: recent, no failure recorded after the last
#      success, decrypts (the age key exists only here) and lists with
#      pg_restore, without writing the plaintext anywhere
#   3. checks the Mac's own disk (50 GB free at least) and the weekly
#      routing graph build it runs (infra/ops/mac-routing/), then reads the
#      state of every check of the status page (Gatus)
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
# 29: a dump taken just before an account is deleted holds it; dropped when
# 30 days old at most, as the privacy page announces.
keep_days=29
held_days=26
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

# The copies past their durations: the photos held 26 days after their
# deletion day, and the dumps whose date is more than keep_days days old.
# Run before the pull, so the durations hold on a night the ops server
# cannot be reached, and after it.
prune() {
	held_cutoff=$(date -u -v-"${held_days}"d +%Y%m%d)
	for d in "$dest"/media-deleted/*; do
		[ -d "$d" ] || continue
		day=$(basename "$d")
		case "$day" in
		[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]) ;;
		*) continue ;;
		esac
		if [ "$day" -lt "$held_cutoff" ]; then
			find "$d" -type f -delete
			find "$d" -depth -type d -empty -delete
			say "dropped the photos deleted on $day"
		fi
	done
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
}

say "start"
mkdir -p "$dest"
prune

# 1. The pull. The ops server reboots at 02:30 UTC when an update asks for
# it, which is 04:30 in Paris in summer: three attempts, two minutes apart.
pulled=no
for attempt in 1 2 3; do
	if rsync -rt --timeout=300 --exclude=/media/ -e "ssh -F $conf/ssh_config" lunaway-ops-pull: "$dest/" \
		&& rsync -rt --timeout=600 -e "ssh -F $conf/ssh_config" lunaway-ops-pull:media/ "$dest/media/"; then
		pulled=yes
		say "pulled: $(find "$dest" -maxdepth 1 -name 'lunaway-*.dump.age' | wc -l | tr -d ' ') dumps, $(find "$dest/media" -type f -name '*.webp.age' 2>/dev/null | wc -l | tr -d ' ') photos on the Mac"
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

# The photos: the newest copy must decrypt to a WebP file (RIFF....WEBP),
# and the server must have brought the copy up to date in the last 36 hours.
newest_photo=$(find "$dest/media" -type f -name '*.webp.age' -exec stat -f '%m %N' {} + 2>/dev/null | sort -n | tail -n 1 | cut -d' ' -f2-)
if [ -n "$newest_photo" ]; then
	head12=$(age --decrypt --identity "$conf/backup-age.key" "$newest_photo" 2>/dev/null | head -c 12 | LC_ALL=C tr -c 'A-Z' '.')
	case "$head12" in
	RIFF....WEBP) say "verified the newest photo copy: decrypted, WebP" ;;
	*) fail "la copie la plus récente d'une photo ne se déchiffre pas en WebP" ;;
	esac
fi
media_success=$(read_stamp "$dest/media/last-success")
media_at=$(stamp_seconds "$media_success")
if [ -z "$media_at" ] || [ $(( (now - media_at) / 3600 )) -ge 36 ]; then
	fail "la copie chiffrée des photos n'a pas été mise à jour depuis 36 heures (${media_success:-jamais})"
fi
# The account deletion journal's copy (lunaway-deletions-offsite, hourly on
# the server; none until a first account is deleted): it must decrypt, and
# the server must have run its copy in the last 36 hours. A restore replays
# it, or deleted accounts come back.
deletions_copy="$dest/account-deletions/account-deletions.jsonl.age"
if [ -f "$deletions_copy" ] && ! age --decrypt --identity "$conf/backup-age.key" "$deletions_copy" > /dev/null 2>&1; then
	fail "la copie du journal des suppressions de comptes ne se déchiffre pas"
fi
deletions_success=$(read_stamp "$dest/account-deletions/last-success")
deletions_at=$(stamp_seconds "$deletions_success")
if [ -z "$deletions_at" ] || [ $(( (now - deletions_at) / 3600 )) -ge 36 ]; then
	fail "la copie du journal des suppressions de comptes n'a pas été faite depuis 36 heures (${deletions_success:-jamais})"
fi
# The takedown journal's copy (lunaway-takedowns-offsite, hourly on the
# server; none until a first place is taken down): the same checks. A
# restore replays it, or places taken down come back.
takedowns_copy="$dest/place-takedowns/place-takedowns.jsonl.age"
if [ -f "$takedowns_copy" ] && ! age --decrypt --identity "$conf/backup-age.key" "$takedowns_copy" > /dev/null 2>&1; then
	fail "la copie du journal des retraits de lieux ne se déchiffre pas"
fi
takedowns_success=$(read_stamp "$dest/place-takedowns/last-success")
takedowns_at=$(stamp_seconds "$takedowns_success")
if [ -z "$takedowns_at" ] || [ $(( (now - takedowns_at) / 3600 )) -ge 36 ]; then
	fail "la copie du journal des retraits de lieux n'a pas été faite depuis 36 heures (${takedowns_success:-jamais})"
fi
# Photos deleted on the server. macOS's rsync (openrsync) sends --delete to
# the server even on a pull, and the ops server's read-only rrsync refuses
# it: a copy the server's list (media/manifest) no longer names is filed
# under the day the backend deleted its photo (media/deletions) in
# media-deleted/<day>, and dropped 26 days after that day, however long this
# Mac was off; a copy the deletions do not name goes now. Both lists come
# from the ops server: they are used only when every line has the form the
# backend writes, and a run that would remove more than 50 copies and more
# than 5% of them removes nothing and fails.
manifest="$dest/media/manifest"
deletions="$dest/media/deletions"
held_cutoff=$(date -u -v-"${held_days}"d +%Y%m%d)
photo_re='photos/[0-9a-f]{2}/[0-9a-f]{2}/[0-9a-f]{64}\.webp\.age'
if [ "$pulled" = yes ] && [ -f "$manifest" ]; then
	if grep -qvE "^$photo_re\$" "$manifest" || { [ -f "$deletions" ] && grep -qvE "^[0-9]{8} $photo_re\$" "$deletions"; }; then
		fail "la liste des photos du serveur a une forme inattendue ; rien n'est retiré"
	else
		(cd "$dest/media" && find photos -type f -name '*.webp.age' | grep -E "^$photo_re\$" | LC_ALL=C sort) > "$dest/.local-photos"
		LC_ALL=C comm -23 "$dest/.local-photos" "$manifest" > "$dest/.gone-photos"
		gone=$(wc -l < "$dest/.gone-photos" | tr -d ' ')
		local_count=$(wc -l < "$dest/.local-photos" | tr -d ' ')
		if [ "$gone" -gt 50 ] && [ $((gone * 100)) -gt $((local_count * 5)) ]; then
			fail "le serveur ne liste plus $gone des $local_count photos copiées sur le Mac ; rien n'est retiré"
		else
			while IFS= read -r rel; do
				day=$(awk -v p="$rel" '$2 == p { print $1; exit }' "$deletions" 2>/dev/null)
				if [ -z "$day" ] || [ "$day" -lt "$held_cutoff" ]; then
					rm -f "$dest/media/$rel"
				else
					mkdir -p "$dest/media-deleted/$day/$(dirname "$rel")"
					mv "$dest/media/$rel" "$dest/media-deleted/$day/$rel"
				fi
			done < "$dest/.gone-photos"
			[ "$gone" = 0 ] || say "$gone photo copies deleted on the server set aside or dropped"
		fi
	fi
elif [ "$pulled" = yes ]; then
	fail "aucune liste des photos sur le serveur ops"
fi
# The pruning again, for the copies the pull just set aside.
prune

# The Mac's own disk: the backups, the routing build's bundle (8.3 GB a
# week) and the work of this repository live there; a full disk stopped
# colima on 2026-10-06.
free_gb=$(df -g "$HOME" | awk 'NR == 2 { print $4 }')
if [ -z "$free_gb" ] || [ "$free_gb" -lt 50 ]; then
	fail "le disque du Mac n'a plus que ${free_gb:-?} Go libres (seuil 50 Go)"
else
	say "Mac disk: $free_gb GB free"
fi

# The weekly routing graph build (infra/ops/mac-routing/): its last run, and
# its last success less than 8 days ago (weekly). Digits and plain words
# only are read from its state file.
routing_state="$HOME/Library/Application Support/Lunaway/routing/state"
if [ -f "$HOME/Library/LaunchAgents/legal.p2p.lunaway.routing-build.plist" ]; then
	last_success=$(sed -nE 's/^last_success=([0-9]{9,11})$/\1/p' "$routing_state" 2>/dev/null | tail -n 1)
	last_run=$(sed -nE 's/^last_run=[0-9]{9,11} (ok|nothing|failed)$/\1/p' "$routing_state" 2>/dev/null | tail -n 1)
	swept=$(sed -nE 's/^swept=([0-9]{9,11}) [0-9]+$/\1/p' "$routing_state" 2>/dev/null | tail -n 1)
	if [ "$last_run" = failed ]; then
		fail "la dernière construction hebdomadaire du graphe de routage a échoué (~/Library/Logs/lunaway-routing-build.log)"
	fi
	if [ -z "$last_success" ] || [ $(( (now - last_success) / 86400 )) -ge 8 ]; then
		fail "aucune construction du graphe de routage n'a abouti depuis 8 jours"
	fi
	if [ -n "$swept" ] && [ $(( (now - swept) / 3600 )) -lt 24 ]; then
		fail "un serveur de construction du graphe de routage restait et a été supprimé par le balayage"
	fi
fi

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
