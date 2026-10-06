#!/usr/bin/env bash
# Read-only inspection of a Lunaway server from the inside, run as root by
# infra/verify.sh: effective SSH settings, firewall, fail2ban, listening
# sockets, sandbox scores, kernel settings, updates; on the backend also
# PostgreSQL, credentials, backups, the API, the data pipeline and what the
# ops server may read; on the ops server Gatus, the status page and the dump
# replica. Key material is never printed: authorized_keys lines show their
# options with the key replaced.
#
#   sudo bash ~/infra/server/inspect.sh backend|ops
set -uo pipefail
[ "$(id -u)" -eq 0 ] || { echo "run as root (sudo)" >&2; exit 1; }
server_role="${1:?backend or ops}"
masked_keys() { sed -E 's/ssh-ed25519 [A-Za-z0-9+\/=]+.*$/ssh-ed25519 <key>/' "$1"; }

echo "--- sshd effective settings"
sshd -T 2>/dev/null | grep -E '^(permitrootlogin|passwordauthentication|kbdinteractiveauthentication|authenticationmethods|allowusers|maxauthtries|logingracetime|x11forwarding|allowtcpforwarding|allowagentforwarding|kexalgorithms|ciphers|macs|hostkeyalgorithms|persourcepenalties) '
ls /etc/ssh/sshd_config.d/
echo "--- accounts with a login shell"
awk -F: '$7 !~ /(nologin|false|sync)$/ { print $1, $7 }' /etc/passwd
echo "--- nftables (terse: set elements, which hold client addresses, left out)"
nft -t list ruleset
echo "--- fail2ban"
fail2ban-client status
fail2ban-client status sshd
grep -h '^ignoreip' /etc/fail2ban/jail.d/lunaway-ignore.local
echo "--- listening sockets"
ss -tulpnH | awk '{ print $1, $5, $7 }' | sort
echo "--- systemd-analyze security"
units="ssh caddy"
[ "$server_role" = backend ] && units="lunaway-api caddy lunaway-pgdump postgresql@18-main lunaway-migrate lunaway-ingest-osm lunaway-conflate ssh"
[ "$server_role" = ops ] && units="gatus caddy lunaway-replica ssh"
for unit in $units; do
  printf '%-22s %s\n' "$unit" "$(systemd-analyze security "$unit" 2>/dev/null | tail -n 1)"
done
echo "--- kernel"
sysctl net.ipv4.conf.all.rp_filter net.ipv4.conf.all.accept_redirects net.ipv6.conf.all.accept_redirects net.ipv4.tcp_syncookies kernel.kptr_restrict kernel.dmesg_restrict kernel.unprivileged_bpf_disabled fs.protected_symlinks fs.protected_hardlinks fs.suid_dumpable kernel.yama.ptrace_scope
echo "AppArmor: $(aa-enabled), $(aa-status --profiled 2>/dev/null) profiles loaded, $(aa-status --enforced 2>/dev/null) enforced"
echo "--- time, swap, journal, disks, mounts"
chronyc -n tracking | grep -E 'Reference ID|System time|Leap status'
swapon --show
grep -E '^[^#].* swap ' /etc/fstab || echo "fstab: no swap line"
journalctl --disk-usage
df -h / /srv/data | sed 1d
findmnt -no SOURCE,TARGET,OPTIONS /srv/data
grep -vE '^#|^$' /etc/fstab | awk '{ print $2, $3 }'
ip -brief address
echo "--- updates"
systemctl is-enabled unattended-upgrades apt-daily.timer apt-daily-upgrade.timer
systemctl list-timers --no-pager | grep -E 'apt-daily|lunaway' | awk '{ print $(NF-1), $NF }'
unattended-upgrade --dry-run --debug 2>&1 | grep -E 'Allowed origins' | head -n 1
echo "Caddy signing key: $(gpg --homedir /var/lib/lunaway-setup/gnupg --batch --with-colons --show-keys /usr/share/keyrings/caddy-stable-archive-keyring.gpg 2>/dev/null | awk -F: '$1 == "fpr" { print $10; exit }')"
grep -vE '^#|^$' /etc/apt/sources.list.d/caddy-stable.list
echo "--- units"
systemctl list-unit-files --no-pager --no-legend 'lunaway*' 'gatus*' | awk '{ print $1, $2 }'
systemctl --failed --no-legend --no-pager

if [ "$server_role" = ops ]; then
  echo "--- Gatus"
  systemctl is-active gatus caddy
  stat -c '%a %U:%G %n' /etc/gatus /etc/gatus/config.yaml /usr/local/bin/gatus /etc/lunaway-ops /etc/lunaway-ops/*
  sha256sum /usr/local/bin/gatus | cut -c1-64
  curl -fsS -m 10 http://127.0.0.1:8080/api/v1/endpoints/statuses | python3 -c '
import json, sys
for e in json.load(sys.stdin):
    r = (e.get("results") or [{}])[-1]
    print("  %-8s %-16s %s %s" % (e.get("group"), e.get("name"), "ok  " if r.get("success") else "FAIL", r.get("timestamp", "")))'
  echo "--- dump replica"
  stat -c '%a %U:%G %n' /srv/data/backups/postgresql
  ls -l /srv/data/backups/postgresql
  systemctl status lunaway-replica.service --no-pager -n 3 | tail -n 4
  echo "--- the Mac's pull account"
  stat -c '%a %U:%G %n' /var/lib/lunaway-pull/.ssh/authorized_keys
  masked_keys /var/lib/lunaway-pull/.ssh/authorized_keys
  exit 0
fi

echo "--- PostgreSQL"
runuser -u postgres -- psql -X -At -d lunaway -c "select 'version ' || current_setting('server_version') || ', postgis ' || postgis_lib_version() || ', listen ' || current_setting('listen_addresses') || ', password_encryption ' || current_setting('password_encryption') || ', data_directory ' || current_setting('data_directory')"
runuser -u postgres -- psql -X -At -d lunaway -c "select 'extensions: ' || string_agg(extname || ' ' || extversion, ', ' order by extname) from pg_extension"
runuser -u postgres -- psql -X -At -d postgres -c "select 'role ' || rolname || ': login=' || rolcanlogin || ' super=' || rolsuper || ' createdb=' || rolcreatedb || ' createrole=' || rolcreaterole || ' conn_limit=' || rolconnlimit from pg_roles where rolname like 'lunaway%' order by 1"
runuser -u postgres -- psql -X -At -d lunaway -c "select 'default privileges: ' || count(*) from pg_default_acl"
runuser -u postgres -- psql -X -At -d lunaway -c "select 'pg_stat_statements role statements with a password: ' || count(*) from pg_stat_statements where query ~* '^\s*(alter|create)\s+(role|user)\M.*\mpassword\M'"
grep -v '^#' /etc/postgresql/18/main/pg_hba.conf | grep -v '^$'
echo "--- logins with the generated credentials (password through the environment, never printed)"
for f in /etc/lunaway/api.env /etc/lunaway/ingest.env /etc/lunaway/owner.env; do
  url="$(sed -n 's/^DATABASE_URL=//p' "$f")"
  role="$(sed -n 's|^postgres://\([^:]*\):.*|\1|p' <<<"$url")"
  printf '%s as %s: ' "$f" "$role"
  PGPASSWORD="$(sed -n 's|^postgres://[^:]*:\([^@]*\)@.*|\1|p' <<<"$url")" \
    psql -X -At -h 127.0.0.1 -U "$role" -d lunaway \
    -c "select 'connected as ' || current_user || ', ssl ' || coalesce((select ssl::text from pg_stat_ssl where pid = pg_backend_pid()), '?') || ', may create in public: ' || has_schema_privilege('public', 'CREATE')" 2>&1 | head -n 1
done
echo "--- secrets files"
stat -c '%a %U:%G %n' /etc/lunaway /etc/lunaway/*
echo "--- backups"
stat -c '%a %U:%G %n' /srv/data/backups/postgresql /var/backups/lunaway/postgresql /srv/data/backups/offsite
ls -l /srv/data/backups/postgresql /var/backups/lunaway/postgresql /srv/data/backups/offsite
systemctl list-timers --no-pager --no-legend lunaway-pgdump.timer | awk '{ print "next dump:", $1, $2, $3 }'
systemctl show -p After apt-daily-upgrade.service | tr ' ' '\n' | grep -x 'lunaway-pgdump.service' || echo "apt-daily-upgrade is NOT ordered after the dump"
echo "--- API"
systemctl is-active lunaway-api caddy postgresql@18-main
readlink /opt/lunaway/current
ls /opt/lunaway/current/
echo "--- data pipeline"
systemctl is-enabled lunaway-ingest-osm.timer lunaway-ingest-atout-france.timer lunaway-conflate.timer 2>&1 | tr '\n' ' '
echo
stat -c '%a %U:%G %n' /srv/data/ingest /srv/data/media
echo "--- what the ops server may read (lunaway-pull)"
id lunaway-pull
stat -c '%a %U:%G %n' /var/lib/lunaway-pull/.ssh/authorized_keys
masked_keys /var/lib/lunaway-pull/.ssh/authorized_keys
runuser -u lunaway-pull -- /usr/local/sbin/lunaway-health
