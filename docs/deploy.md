# Deploying the backend

Lunaway runs on two Hetzner Cloud servers in their own Hetzner project, built
and kept by the scripts in `infra/`, plus one nightly job on the
maintainer's Mac. Everything is idempotent: running a script again changes
only what differs from the files in the repository.

```
 internet
   │ Hetzner Cloud Firewalls: 22 from admin sources; 80, 443 tcp+udp, ICMP
   ▼
 lunaway-backend-1, fsn1 (10.42.0.2)           lunaway-sync-1, nbg1 (10.42.0.3), role "ops"
   nftables, fail2ban                            nftables, fail2ban
   Caddy :80 :443 ── 127.0.0.1:8484 lunaway-api  Caddy :80 :443 ── 127.0.0.1:8080 Gatus
     /media/ from /srv/data/media                  public status page, checks from outside
     /tiles/ ── 127.0.0.1:8485 pmtiles serve       dump replica, 14 days (/srv/data/backups)
       planet archive on /srv/tiles (own volume),
       refreshed monthly from Protomaps
   PostgreSQL 18 + PostGIS (localhost)
   lunaway CLI timers: ingest, conflate
   nightly dump, age-encrypted copy
   lunaway-pull ◄── SSH over lunaway-net ───────── Gatus probe key: health JSON
                    (10.42.0.0/16), forced ─────── replica key: rrsync -ro, encrypted dumps
                    commands, from 10.42.0.3 only

 maintainer's Mac, 04:30 local ── SSH, rrsync -ro ──► ops replica ──► ~/Backups/lunaway, 30 days
                                ── HTTPS ───────────► status page API
                                ── gh ──────────────► GitHub issue "ops: alerte"
```

The backend never connects to the ops server. Lunaway ingests open data
only (`.claude/rules/data-sources.md`); the imports run on the backend.

## Files

| path | runs | role |
|---|---|---|
| `infra/lib.sh` | here | roles, names, private IPs; reads `~/.config/lunaway/env` |
| `infra/provision.sh` | here | admin key, private network, then per role: firewall, server, primary IPs, volume |
| `infra/cloud-init.yaml` | first boot | admin account, SSH policy, nftables, fail2ban, sysctl, automatic updates |
| `infra/configure.sh` | here | copies `infra/` to a server, runs `infra/server/setup.sh` for its role, reboots if an update asks |
| `infra/server/*.sh` | server, root | backend steps `harden data-volume postgres caddy tiles backups api pipeline ops-access`, ops steps `harden data-volume ops-replica ops-status`, and the test and release helpers |
| `infra/deploy-api.sh` | here | builds a commit in a container, uploads the API and the CLI, migrates, switches the release, checks |
| `infra/deploy-gatus.sh` | here | copies the pinned Gatus binary out of its official image and installs it on the ops server |
| `infra/deploy-web.sh` | here | deploys the landing site or the Flutter web build as a new release |
| `infra/deploy-basemap-assets.sh` | here | deploys map styles or a sprite set to the basemap host |
| `infra/ssh-access.sh` | here | which addresses may reach SSH on both servers |
| `infra/enable-domain.sh` | here | turns on the lunaway.net sites once DNS points at the backend |
| `infra/verify.sh` | here | external and internal checks of both servers, the status page, the pulls, and what each database role may do (`infra/server/test-grants.sh`) |
| `infra/files/` | server | configuration files, installed at the same path under `/`; `files/roles/<role>/` holds the per-role ones |
| `infra/systemd/` | server | units and drop-ins, installed in `/etc/systemd/system/` |
| `infra/caddy/` | servers | the backend's Caddyfile and domain sites, the ops server's `status.Caddyfile` |
| `infra/tiles/` | here, backend | the basemap's pins (`version.sh`: go-pmtiles, basemaps-assets, the tile schema) and `assets-hash.py`, which computes the fonts and sprites pin |
| `infra/ops/gatus/` | ops | Gatus's configuration template and the pinned release (`version.sh`) |
| `infra/ops/mac/` | the Mac | the nightly job, its launchd plist and `install.sh` |
| `infra/web/` | backend | placeholder landing page and web app page |
| `infra/tests/caddy-layout.sh` | here | runs `infra/caddy/` in the Caddy image, the tile routes against a real `pmtiles serve`, and checks every route, header and the log masking |
| `infra/routing/valhalla.container` | backend, later | draft unit of the routing engine, not installed |

## Private settings

Values that name the account, an address or a key stay out of the repository,
in `~/.config/lunaway/env` (directory 0700, file 0600):

| key | meaning |
|---|---|
| `LUNAWAY_HCLOUD_CONTEXT` | hcloud CLI context of the Lunaway Hetzner project; every script passes it to each call, the active context is left alone |
| `LUNAWAY_SSH_KEY_NAME`, `LUNAWAY_SSH_PUBKEY` | name of the admin public key in that project, and its file here (uploaded when missing) |
| `LUNAWAY_SSH_IDENTITY` | path of the matching private key on this machine |
| `LUNAWAY_SSH_ALLOW` | CIDRs allowed to reach SSH (written by `provision.sh`, `ssh-access.sh`) |
| `LUNAWAY_BACKUP_RECIPIENT` | the age public key the dumps are encrypted to (written by `infra/ops/mac/install.sh keys`) |
| `LUNAWAY_API_HOST`, `LUNAWAY_WEB_URL`, `LUNAWAY_TILES_URL`, `LUNAWAY_STATUS_DOMAIN` | optional: what the status page checks and its public name (see "Status page") |
| `LUNAWAY_BACKEND_*`, `LUNAWAY_OPS_*`, `LUNAWAY_HOSTNAME` | addresses, volume ids (the backend's tile volume in `LUNAWAY_BACKEND_TILES_VOLUME_ID`), types, written by `provision.sh` |

`~/.config/lunaway/ssh_config` (written by the scripts) defines the hosts
`lunaway` (backend) and `lunaway-ops` (also `lunaway-sync`, the server's first
role), both as the admin user `ops`, and `lunaway-ops-pull` for the Mac's
nightly pull: `ssh -F ~/.config/lunaway/ssh_config lunaway`. Adding
`Include ~/.config/lunaway/ssh_config` at the top of `~/.ssh/config` makes it
`ssh lunaway`.

Secrets live where they are used and nowhere else:

| secret | where |
|---|---|
| database passwords | backend, `/etc/lunaway/{api,ingest,owner}.env` (root, 0600) |
| the probe and replica keys | ops server, `/etc/lunaway-ops/probe_ed25519` (root) and `replica_ed25519` (lunaway-backup), 0600; Gatus's configuration carries the probe key inline (`/etc/gatus/config.yaml`, root:gatus 0640) |
| the age identity that decrypts every dump | the Mac only, `~/.config/lunaway/backup-age.key` (0600); keep an offline copy (a password manager): without it no backup can be read |
| the Mac's pull key | the Mac, `~/.config/lunaway/ops-pull_ed25519` (0600) |

## First installation

```bash
infra/ops/mac/install.sh keys   # the age identity and the pull key, on the Mac
infra/provision.sh              # both servers, the network, the volumes; waits for cloud-init
infra/configure.sh ops          # first: generates the probe and replica keys, pins the backend's host key
infra/configure.sh backend      # every backend step; lunaway-pull takes the ops server's keys;
                                # the tiles step starts the first planet download and its checks (about 45 minutes)
infra/deploy-api.sh             # builds HEAD, migrates, deploys, checks https://<ip>.sslip.io
infra/configure.sh backend pipeline   # turns the import timers on, now that the CLI is there
infra/deploy-gatus.sh           # the status page's engine
infra/ops/mac/install.sh        # the nightly job on the Mac
infra/verify.sh                 # both servers, the status page, the pulls
```

Each server is created stopped, attached to `lunaway-net` with its fixed
address, then started, so cloud-init configures the private interface at
first boot. `infra/provision.sh --render-only ROLE FILE` writes the rendered
user data for review without creating anything.

## Sizing

Prices excluding VAT on 2026-10-06 (`hcloud server-type describe`); the
Lunaway project is billed with 20% VAT.

| resource | type | why | EUR a month excl. VAT |
|---|---|---|---|
| `lunaway-backend-1` | cx33, 4 vCPU, 8 GB, 80 GB NVMe, fsn1 | the API, PostgreSQL and the imports need little at launch; 8 GB also holds the France routing graph, without much room (see "Next service") | 8.49 |
| its daily backups | 20% of the server | images of the root disk, which carry a copy of the latest dumps | 1.70 |
| `lunaway-data` | volume, 150 GB | database, dumps, import cache, photos (budget below) | 8.58 |
| `lunaway-tiles` | volume, 300 GB | the basemap: two planet archives at the peak of a refresh (see "Basemap") | 17.16 |
| `lunaway-sync-1` (role ops) | cx23, 2 vCPU, 4 GB, 40 GB, nbg1 | Gatus and Caddy, a nightly rsync | 5.49 |
| `lunaway-sync-data` | volume, 20 GB | the dump replica | 1.14 |
| 2 primary IPv4 | | mobile networks and campsite Wi-Fi without IPv6 | 1.00 |
| `lunaway-net`, primary IPv6 | | | 0 |

`provision.sh` tries types in order of value and keeps the first one the API
accepts: for the backend `cx43` (8 vCPU, 16 GB, 15.99), `cax31`, then `cx33`;
for the ops server `cax11`, then `cx23`. On 2026-10-06 the API refused `cx43`
in nbg1 and fsn1 (out of stock) and every ARM type in both German sites, so
the backend runs on `cx33`. The type list's `available` flag is not a
reliable stock signal: on the same day it said `cx43` was unavailable
everywhere, and the API had still created one in nbg1 an hour earlier.

The backend moves to `cx43` in place once Hetzner has stock in fsn1:
`hcloud server change-type lunaway-backend-1 cx43` (stops it for about a
minute; without `--keep-disk` the disk grows to 160 GB, for the routing
tiles), then `infra/configure.sh backend postgres` to retune PostgreSQL. Do it
before the routing engine serves France, or move to `cpx42` (16 GB, 69.49)
if `cx43` stays out of stock.

### The data volume

| content | size |
|---|---|
| PostgreSQL with France (about 15,600 places from 19,500 records on the development database, 2026-10-05) | well under a GB now; Europe later, a few GB |
| the OpenStreetMap France extract in the import cache (`/srv/data/ingest`) | 5.9 GB (5,867,462,742 bytes on 2026-10-05); during the daily refresh the old file stays until the new one is complete, so 12 GB at the peak |
| 7 nightly dumps and their 7 encrypted copies | small (two copies of each dump) |
| community photos (`/srv/data/media`) | to size when the feature is designed |

The volume was sized for an image feed that no longer exists; a volume
cannot shrink, and the photos will use the room. On 2026-10-06, 140 GB of
its 147 GB were free. It grows online (`hcloud volume resize lunaway-data
--size <GB>`, then `sudo resize2fs /dev/disk/by-id/scsi-0HC_Volume_<id>` on
the backend, about 0.06 EUR per GB a month): the status page turns red at
80%.

## Deploying the API

```bash
infra/deploy-api.sh                              # the backend of HEAD
LUNAWAY_DEPLOY_REV=<commit> infra/deploy-api.sh  # any commit, a rollback included
```

The script builds a committed revision (`git archive`), never the working
tree, in the `rust:<toolchain>-trixie` container pinned by digest in the
script (one line per toolchain; a new toolchain needs its digest from
`docker buildx imagetools inspect`): the same glibc as the server, and a
cross linker when the server's architecture differs from the builder's. The
container mounts only `data/tmp/infra/` (gitignored), read-only; the
binaries come out with `docker cp`. It builds `lunaway-api` and, from the
revisions that have `backend/crates/lunaway-cli`, the `lunaway` CLI.

On the server, `infra/server/install-release.sh` puts both in
`/opt/lunaway/releases/<date>-<commit>/` and points `/opt/lunaway/current` at
it. With a CLI, `lunaway-migrate.service` then runs `lunaway migrate` as
`lunaway_owner`; when it fails, `current` goes back and the running API is
never touched. Then the API restarts, and `current` goes back to the
previous release when `/health` does not answer within 20 seconds. Applied
migrations stay after such a rollback: they are additive
(`.claude/rules/sqlx.md`), so the previous API runs on the newer schema. Old
releases stay until removed by name.

## Data pipeline

The `lunaway` CLI of the current release runs from systemd on the backend,
as the database role `lunaway_ingest` (`/etc/lunaway/ingest.env`), under the
static user `lunaway-ingest`, sandboxed like the API (no capabilities,
read-only system, syscall filter, W^X memory), with two differences: the
imports may open outbound connections (the sources' servers over HTTPS), and
they write their cache under `LUNAWAY_DATA_DIR=/srv/data/ingest` on the data
volume, so an interrupted download resumes.

| unit | when | runs |
|---|---|---|
| `lunaway-ingest-osm.timer` | daily, 03:00 UTC | `lunaway ingest osm-extract --refresh`: the Geofabrik France extract, streamed to disk and resumed after an interruption |
| `lunaway-ingest-atout-france.timer` | Sundays, 04:00 UTC | `lunaway ingest atout-france --refresh`: the classified campsites, geocoded |
| `lunaway-conflate.service` | after each successful import (`OnSuccess=`) | `lunaway conflate` |
| `lunaway-conflate.timer` | daily, 00:05 Europe/Paris | `lunaway conflate`, so the opening hours the API serves start from the new day |
| `lunaway-migrate.service` | on a deploy only | `lunaway migrate`, as `lunaway_owner` |

An import and a conflation may overlap: every writer of places waits for
one PostgreSQL advisory lock, and the conflation locks the records it reads
(`backend/crates/lunaway-db/src/conflation.rs`). The timers stay off while the
release carries no CLI; `infra/configure.sh backend pipeline` turns them on
once it does. By hand: `sudo systemctl start lunaway-ingest-osm` (and
`journalctl -u lunaway-ingest-osm -f`).

## Status page

Gatus on the ops server checks the backend from another server in another
datacenter, every one to fifteen minutes, and serves the result at
`https://<ops-ipv4-dashed>.sslip.io/` (later `status.lunaway.net`), through
Caddy with automatic TLS. Its API, `/api/v1/endpoints/statuses`, is what the
Mac's nightly job reads.

| group | check | how |
|---|---|---|
| public | API | `GET https://<api host>/health` answers `ok` with 200 within 3 s |
| public | GraphQL | `{ apiVersion }` answers with an `apiVersion` |
| public | API certificate | more than 14 days left (Caddy renews 30 days before the end) |
| public | Web app | 200 and the certificate, off until `LUNAWAY_WEB_URL` is set |
| public | Basemap TileJSON | `<tiles>/planet.json` answers 200, TileJSON 3.0.0, tile URLs naming a build |
| public | Basemap tile | a z14 tile over Paris (`<tiles>/planet/14/8299/5636.mvt`) answers 200, more than 1000 bytes, within 2 s |
| backend | PostgreSQL | the health probe reports `pg_isready` on loopback |
| backend | Data volume | mounted, under 80% full; root disk under 85% |
| backend | Nightly dump | succeeded less than 26 hours ago, no failure recorded after it |
| backend | Basemap build | the tile volume is mounted and the planet served is less than 35 days old (a refresh failed otherwise) |

The backend checks run the probe over SSH on the private network: Gatus
logs in as `lunaway-pull` with its probe key, which the backend forces to
`/usr/local/sbin/lunaway-health` (one JSON object, computed at each call,
nothing secret). PostgreSQL keeps listening on localhost only. Gatus does
not verify SSH host keys (its client accepts any). A host posing as the
backend gets nothing it can reuse, since the key's signature is bound to that
one session; it could only answer a false green, from inside the private
network. The replica pull, which uses OpenSSH, pins the backend's host key. The
backend's fail2ban exempts the ops server's private address, since a ban
would turn every backend check red and stop the replica.

What the page checks comes from the private settings, then
`infra/configure.sh ops ops-status`:

- `LUNAWAY_API_HOST`: the API's name, the backend's sslip.io name by
  default; `api.lunaway.net` once DNS exists.
- `LUNAWAY_WEB_URL`: `https://lunaway.net/app/` once the web app is served.
- `LUNAWAY_TILES_URL`: the basemap's base URL, `https://<backend sslip.io
  name>/tiles` by default; `https://tiles.lunaway.net` once DNS exists.
- `LUNAWAY_STATUS_DOMAIN`: `status.lunaway.net` once its A and AAAA records
  point at the ops server; Caddy then serves both names and gets the
  certificate.

Gatus is pinned in `infra/ops/gatus/version.sh`: the official image by the
digest of its multi-architecture index, and the SHA-256 of the binary for
each architecture. Gatus publishes no binary; `infra/deploy-gatus.sh` pulls
the image by digest, copies `/gatus` out of a container it never starts,
checks the hash here, and the server checks it again before installing.

## The nightly job on the Mac

The Mac Studio this repository lives on is the only machine outside
Hetzner, and the only holder of the age identity. Every night at 04:30
local time, launchd runs `infra/ops/mac/lunaway-ops.sh` (label
`legal.p2p.lunaway.ops`, a missed run happens at wake-up):

1. pulls the ops server's replica into `~/Backups/lunaway/` with the pull
   key, which the ops server forces to `rrsync -ro` on the replica and
   accepts only from the admin sources; three attempts two minutes apart
   (the ops server may be rebooting for an update at 02:30 UTC);
2. checks the newest dump: decrypts and lists it with `pg_restore --list`,
   without writing the plaintext; created less than 36 hours ago according
   to the archive itself (age authenticates it, so a renamed old dump fails);
   no failure recorded after the last success; drops what is older than 30
   days. What comes from the ops server (markers, names) reaches the issue
   only when it has the expected form;
3. reads every check of the status page;
4. when anything failed, opens the GitHub issue `ops: alerte` on
   `poka-IT/lunaway` (or edits it and comments when it is already open),
   naming the failing checks only, never an address or a key; when all is
   green and the issue is open, comments and closes it. It writes as the gh
   account `poka-IT`, whichever account is active in gh, and only touches an
   issue that account opened.

The log is `~/Library/Logs/lunaway-ops.log`.

```bash
infra/ops/mac/install.sh            # keys if missing, the script, the plist, launchctl bootstrap
infra/ops/mac/install.sh run        # one run now (launchctl kickstart)
infra/ops/mac/install.sh drill      # one run with a fake failure: opens the issue; the next run closes it
infra/ops/mac/install.sh remove     # launchctl bootout, plist and script removed; keys and backups stay
launchctl print gui/$(id -u)/legal.p2p.lunaway.ops | grep -E 'state|last exit'
```

It needs `age`, `jq`, `gh` logged in as `poka-IT`, and `pg_restore` from
Homebrew's `libpq` (`brew install libpq`, keg-only). That `pg_restore` cannot
decompress zstd, so it lists the archive without reading its data; the
decryption, which age authenticates over the whole file, and the listing are
the nightly check.

If the Mac is off for days, nothing alerts: the status page stays the place
to look.

## Day to day

```bash
ssh -F ~/.config/lunaway/ssh_config lunaway        # backend
ssh -F ~/.config/lunaway/ssh_config lunaway-ops    # ops server
sudo journalctl -u lunaway-api -f            # API logs
sudo tail -f /var/log/caddy/access.log       # access log, truncated addresses
sudo -u postgres psql lunaway                # database shell
sudo fail2ban-client status sshd             # bans
systemctl list-timers 'lunaway*'             # dump, imports, conflation, basemap refresh (backend), replica (ops)
infra/configure.sh backend harden            # re-apply one step after editing infra/files
```

### SSH access from a new place

SSH (22/tcp) is open in the host firewalls but filtered by the Hetzner Cloud
Firewalls to the admin sources. From a new network:

```bash
infra/ssh-access.sh add-current     # adds this machine's public IPv4 and IPv6 /64, on both firewalls
infra/configure.sh backend harden   # refreshes fail2ban's ignore list
infra/configure.sh ops harden ops-replica   # the same, and the sources the Mac's pull key is accepted from
infra/ssh-access.sh show
infra/ssh-access.sh set 203.0.113.7/32 2001:db8:1::/64   # replace the list
infra/ssh-access.sh open            # any address; keys and fail2ban still apply
```

Only the Hetzner API token is needed, so a changed home address never locks
anyone out. fail2ban exempts the admin sources, except ranges wider than /16
(IPv4) or /48 (IPv6), such as the 0.0.0.0/0 of `open`. Lost key or broken
SSH: the Hetzner rescue system mounts the disk; the admin account has no
password, so the web console alone cannot log in.

### The domain

The `lunaway.net` sites are in `infra/caddy/lunaway.net.caddy`, installed but
not loaded:

| address | served from | notes |
|---|---|---|
| `api.lunaway.net` | lunaway-api | `/health` and `/graphql`; `/media/` below; anything else 404 |
| `api.lunaway.net/media/` | `/srv/data/media` | a present file is served with a one-year immutable cache and a sandboxing CSP; a missing file or a directory is a plain 404, never listed |
| `lunaway.net/` | `/srv/lunaway/site` | landing site, HTML and CSS only; `/privacy`, `/account/delete`, `/about` map to `privacy.html` or `privacy/index.html`; hashed assets cached a year, the rest five minutes |
| `lunaway.net/app/` | `/srv/lunaway/web` | Flutter web build, unknown paths fall back to `/app/index.html`; revalidated on every load |
| `www.lunaway.net` | | permanent redirect to `https://lunaway.net` |
| `tiles.lunaway.net` | pmtiles serve, `/srv/tiles` | the basemap (see "Basemap"); the sslip.io name serves the same under `/tiles/` |

The sslip.io name of the backend serves the API snippet too, `/media/`
included. `infra/tests/caddy-layout.sh` runs this configuration in the
official Caddy image (plain HTTP, test roots) and checks each route and
header, and that Caddy's own log masks client addresses; run it after
editing `infra/caddy/`. Once the A and AAAA records of the four names point
at the backend (DNS only, not proxied, so the HTTP-01 challenge reaches
Caddy):

```bash
infra/enable-domain.sh              # checks DNS from 1.1.1.1 and 8.8.8.8, enables, waits for the certificates
infra/enable-domain.sh --disable
```

Caddy uses Let's Encrypt only (no fallback CA), so a CAA record
`0 issue "letsencrypt.org"` on `lunaway.net` matches it. The API answers
CORS requests from `https://lunaway.net` only (the web app's origin);
`LUNAWAY_DEV_CORS=1` in its environment adds pages served from
`localhost` and `127.0.0.1`, for development, never on the server. Then set
`LUNAWAY_API_HOST=api.lunaway.net`, `LUNAWAY_TILES_URL=https://tiles.lunaway.net`
and `LUNAWAY_WEB_URL`, and rerun `infra/configure.sh ops ops-status`.

### Deploying the landing site and the web app

```bash
infra/deploy-web.sh site path/to/site     # index.html at the root, HTML and CSS only
infra/deploy-web.sh app --build           # fvm flutter build web --base-href /app/ --no-web-resources-cdn, then deploy
infra/deploy-web.sh app app/build/web     # an existing build
```

Each deploy lands in `/srv/lunaway/releases/<site|app>/<date>-<commit>/` and
switches the `/srv/lunaway/site` or `/srv/lunaway/web` symlink. Without
`--no-web-resources-cdn` the app would load CanvasKit from `www.gstatic.com`,
which the CSP refuses. A previous release comes back with
`sudo ln -sfn /srv/lunaway/releases/app/<name> /srv/lunaway/web` on the server.

## Backups and restore

Three copies of each nightly dump, in three places, the off-site ones
encrypted:

| copy | where | kept |
|---|---|---|
| plaintext dump and roles | backend data volume, `/srv/data/backups/postgresql/` (postgres, 0700) | 7 |
| plaintext, on the root disk | backend, `/var/backups/lunaway/postgresql/`, captured by Hetzner's daily server backup (7 images, taken between 06:00 and 10:00 UTC) | 3 |
| age-encrypted | backend `/srv/data/backups/offsite/` (7), pulled at 01:15 UTC into the ops server's volume in nbg1 (14 days), pulled at 04:30 local into the Mac's `~/Backups/lunaway/` (30 days) | |

- `lunaway-pgdump.timer` (00:15 UTC) dumps the `lunaway` database
  (`pg_dump --format=custom`, zstd) and the roles (without password hashes),
  checks the dump with `pg_restore --list`, then encrypts both to
  `LUNAWAY_BACKUP_RECIPIENT` with age and writes `last-success`. A run that
  stops half-way removes its partial files; a failed run starts
  `lunaway-pgdump-failed.service`, which writes `last-failure`. Both markers
  travel with the copies, and the status page and the Mac read them.
- The upgrade run (01:30 UTC) may restart PostgreSQL (a PGDG update, or
  needrestart after a library update). It is ordered after the dump
  (`apt-daily-upgrade.service.d/lunaway-pgdump.conf`): a dump still running
  then delays the upgrade.
- The images under `/srv/data/media` are not backed up yet: nothing writes
  there before community photos.
- The ops server has no Hetzner backup: everything on it but its volume is
  rebuilt by `provision.sh` and `configure.sh ops`, and its volume holds
  ciphertext only.

Restore test on the Mac (also what the nightly job does):

```bash
age --decrypt --identity ~/.config/lunaway/backup-age.key \
  ~/Backups/lunaway/lunaway-<stamp>.dump.age | /opt/homebrew/opt/libpq/bin/pg_restore --list
```

Restoring data needs a `pg_restore` built with zstd, Debian's: on a server,
or in the development image (`imresamu/postgis:18-3.6`). The plaintext
leaves the Mac only towards the server being restored:

```bash
age --decrypt --identity ~/.config/lunaway/backup-age.key ~/Backups/lunaway/lunaway-<stamp>.dump.age \
  | ssh -F ~/.config/lunaway/ssh_config lunaway 'umask 077; cat > restore.dump'
```

Then, on the backend, into a fresh database (also the path for a dump of the
backend's own directory):

```bash
sudo -u postgres psql -c 'CREATE DATABASE lunaway_restore OWNER lunaway_owner'
sudo -u postgres pg_restore --dbname=lunaway_restore --no-owner --role=lunaway_owner restore.dump
```

Before the API serves restored data, give it a new sync epoch:

```bash
sudo -u postgres psql -d lunaway_restore -c 'UPDATE sync_epoch SET epoch = gen_random_uuid(), created_at = now()'
```

A dump puts the change feed back at the dump's position, while devices hold
cursors from later. Every sync cursor names the copy of the feed that issued
it, the epoch and the database's own identifier (`c2.<identity>.<position>`),
and the API answers a cursor of another copy, or one past the end of the
feed, with the code `RESYNC`; the app then syncs again from scratch. A
restore into a new database changes the identifier by itself; the epoch
covers a restore over the same database (a volume snapshot) and costs one
statement, so run it every time. Without either, a device would silently
skip every change made between the backup and its last sync.

`globals-<stamp>.sql.age` holds the roles and their settings, without
passwords; `infra/server/postgres.sh` sets the passwords again.

## Resizing and rebuilding

The volumes hold what must survive, so the servers can change.

- **Another type, same architecture**: `hcloud server change-type [--keep-disk]
  <server> <type>` (the server stops for a minute; with `--keep-disk` it can
  come back down), then `infra/configure.sh backend postgres` to retune
  PostgreSQL for the new memory.
- **Another architecture or a fresh system**: the servers have rebuild and
  delete protection, and their primary IPs survive a deletion (auto-delete
  off), so the DNS records stay valid. Create the new server with
  `provision.sh`, attach the volume, run `configure.sh`: `postgres.sh` takes
  over the existing data directory. Between x86 and ARM, restore from a dump
  instead. This path has not been exercised yet.
- A volume stays in its location: moving the backend to another site means
  copying the data.

## Basemap

The map's background (roads, water, places, labels) comes from our own host,
so the published app depends on no third-party tile service. The data is the
Protomaps basemap, built daily by Protomaps from OpenStreetMap (ODbL) and
Natural Earth, in the schema of
[github.com/protomaps/basemaps](https://github.com/protomaps/basemaps)
(schema 4), as one PMTiles archive of the whole planet, zoom 0 to 15
(138,605,245,404 bytes for the build of 2026-10-05).

| URL, on `tiles.lunaway.net` (on the sslip.io name: under `/tiles/`) | what | cache |
|---|---|---|
| `/planet.json` | TileJSON 3.0.0; its tile URLs name the current build and this host | an hour |
| `/planet-<YYYYMMDD>/{z}/{x}/{y}.mvt` | vector tiles of one build, gzip-encoded (decoded by Caddy for a client that does not accept gzip) | a year, immutable |
| `/planet/{z}/{x}/{y}.mvt` | the current build, for the status page and tools | a day |
| `/fonts/{fontstack}/{range}.pbf` | glyphs: Noto Sans Regular, Medium, Italic, Devanagari | a week |
| `/sprites/protomaps-v4/{light,dark,white,grayscale,black}[@2x].{json,png}` | Protomaps' sprites; ours go to `/sprites/<name>/` | a day |
| `/styles/<name>.json` | map styles, empty until the app's styles are deployed | an hour |
| `/packs/<region>.pmtiles` | offline packs, whole or by byte range, empty for now | a day, then ETag |

Every answer carries `Access-Control-Allow-Origin: *` (public data), and a
preflight allows `Range`. A tile absent from the archive answers 204, a zoom
beyond 15 answers 404; both are cached like the tiles of their build, errors
are not cached. Caddy lets at most 64 requests reach pmtiles at once. A map
style points at the TileJSON (`"url": "https://tiles.lunaway.net/planet.json"`),
the glyphs (`https://tiles.lunaway.net/fonts/{fontstack}/{range}.pbf`) and a
sprite set; `@protomaps/basemaps` generates the default styles
(`npx -p @protomaps/basemaps@5.7.2 -p tsx generate_style style.json <TileJSON>
light en <sprite> <glyphs>`). The map must show the attribution
`© OpenStreetMap` (ODbL); Protomaps asks for, without requiring, a credit to
Protomaps when its styles are used.

Styles and sprite sets go to the server with

```bash
infra/deploy-basemap-assets.sh styles DIR        # DIR/<name>.json, written for https://tiles.lunaway.net
infra/deploy-basemap-assets.sh sprites SET DIR   # DIR/<name>[@2x].json|png, served under /sprites/SET/
```

A style is written with `https://tiles.lunaway.net` in its URLs; the server
turns that prefix into a template action (`` {{placeholder `http.vars.tiles_base`}} ``)
that Caddy fills in per host, so the sslip.io name serves the same style
pointing at itself. The TileJSON works the same way.

### On the backend

- The volume `lunaway-tiles` (300 GB, fsn1) is mounted at `/srv/tiles`,
  `nodev,nosuid,noexec`, no blocks reserved for root. Nothing on it needs a
  backup: a lost volume is a new download.
- `lunaway-tiles.service` runs `pmtiles serve /srv/tiles/serve` on
  127.0.0.1:8485 (go-pmtiles 1.31.2, pinned by the SHA-256 of its release
  tarball in `infra/tiles/version.sh`), as a dynamic user that sees
  `/srv/tiles` read-only and nothing else under `/srv`. pmtiles logs every
  tile path; `LogFilterPatterns=` keeps those lines out of the journal.
- `infra/server/tiles.sh` installs the fonts and sprites from
  `protomaps/basemaps-assets` at a pinned commit, accepted only when the
  hash of their files matches `infra/tiles/version.sh`.
- The access log keeps the zoom of a tile and drops x and y
  (`/planet-20261005/14/x/y.mvt`); it never logs what else would name a
  tile, and so a place on the map: request ranges and validators (`Range`,
  `If-Range`, `If-Match`, `If-None-Match`), response `ETag`,
  `Content-Length`, `Content-Range`, and the response size.

```
/srv/tiles/
  builds/<YYYYMMDD>.pmtiles      planet archives: the current one and the previous
  serve/planet-<YYYYMMDD>.pmtiles, serve/planet.pmtiles   symlinks into builds/
  tilejson/planet.json           written by the refresh, a template Caddy fills in per host
  assets/fonts/ assets/sprites/ assets/styles/
  packs/<region>.pmtiles         offline packs, later
```

### Monthly refresh

`lunaway-tiles-refresh.timer` (the 2nd of each month, 05:00 UTC) runs
`/usr/local/sbin/lunaway-tiles-refresh` as `lunaway-tiles`:

1. reads Protomaps' build list (`https://build-metadata.protomaps.dev/builds.json`:
   name, size and BLAKE3 hash of each daily build) and picks the newest of
   schema 4;
2. makes room: removes a stale partial download, then the previous build
   (never the one served) when two planets and 2 GB would not fit;
3. downloads `https://build.protomaps.com/<YYYYMMDD>.pmtiles` over HTTP/1.1,
   each attempt resuming at the size of the partial file (65.6 MB/s on
   average from fsn1 on 2026-10-06, so about 35 minutes; the host cut the
   transfer three times, after 9 to 15 minutes). curl's own `--retry` is not
   used: it restarted a broken transfer from byte 0 and truncated the file;
4. checks the size, the BLAKE3 hash against the list (9 minutes), `pmtiles
   verify` (1 minute) and the header (MVT, gzip, zoom 0 to at least 14);
5. links `serve/planet-<YYYYMMDD>.pmtiles`, fetches its z0 tile through the
   running pmtiles, writes the new TileJSON, then moves `serve/planet.pmtiles`
   by an atomic rename. pmtiles notices the change by itself (it compares the
   file's size and time on each read).

The previous build stays on the volume and stays served under its own name
until the next refresh needs its room, so a client that read the TileJSON
before the switch keeps its tiles for the hour of its cache. A failed run
changes nothing that is served; it leaves its partial download, which the
next run resumes. Protomaps keeps every daily build for a week and the last
build of each version after that, and asks users to copy the file rather
than link to it (https://docs.protomaps.com/basemaps/downloads), which is
what this does.

```bash
sudo systemctl start lunaway-tiles-refresh               # refresh now
sudo journalctl -u lunaway-tiles-refresh -f
sudo -u lunaway-tiles /usr/local/sbin/lunaway-tiles-refresh 20261005   # back to a build still on the volume
```

A new tile schema (5) needs new styles in the app first: the refresh stays
on schema 4 until `LUNAWAY_TILES_SCHEMA_MAJOR` (in the unit) changes.

### Size

Measured on the build of 2026-10-05 with `pmtiles extract --dry-run`
(archive sizes):

| extract | size |
|---|---|
| planet, zoom 0 to 15 | 138.6 GB |
| planet, zoom 0 to 14 | 68 GB |
| planet, zoom 0 to 13 / 12 / 11 / 10 / 8 | 36 / 18 / 8.0 / 3.8 / 0.56 GB |
| Europe (-25 to 45 E, 27 to 72 N), zoom 0 to 15 | 50 GB |
| France (-5.5 to 9.8 E, 41.2 to 51.2 N), zoom 0 to 15 / 0 to 14 | 9.9 / 4.7 GB |

The whole planet was chosen over Europe at full zoom with the world at low
zoom: the latter is about 54 GB, but needs two extracts and a merge of
disjoint archives at each refresh, so about 160 GB at the peak (a 9.15 EUR
volume instead of 17.16) and no published hash to check the result against.
The planet grew by about 0.6 GB a month in 2026 (Protomaps' build list);
two copies leave about 38 GB of the 300 GB volume (316 GB formatted) free.
Offline packs will need room of their own: grow the volume online
(`hcloud volume resize lunaway-tiles --size <GB>`, then `sudo resize2fs` on
the backend).

### Offline packs (later)

A pack is a `pmtiles extract` of one region (`--bbox` or `--region` with a
GeoJSON polygon, from the current build) written to `/srv/tiles/packs/`,
served as a static file with range requests: the app can download it whole,
or read it remotely through the PMTiles protocol. A pack's name should carry
its build (`france-20261005.pmtiles`) so its URL never changes content.

## Next service: routing (Valhalla)

The app's motorhome-aware navigation will query a Valhalla server on the
backend, behind the API, on `127.0.0.1:8002`. Nothing is installed yet; the
decisions are taken:

- **Serving path**: the official image `ghcr.io/valhalla/valhalla` (amd64 and
  arm64, 3.9.0 on 2026-10-06), run by Podman from Debian 13 through the
  Quadlet unit drafted in `infra/routing/valhalla.container`. Debian 13 has
  no Valhalla package; building it on the server would put a compiler
  toolchain on the production host; Docker Engine would add a root daemon
  that writes its own firewall rules. With `Network=host` and a listener on
  127.0.0.1, no rule changes and the port stays private.
- **Graph build**: elsewhere (the Mac Studio, or a throwaway builder), with
  the same image tag, then `rsync` to `/srv/routing/<build>/` and a switch of
  `/srv/routing/current`. That tiles built on arm64 serve unchanged on x86_64
  is an assumption (both little-endian, 64-bit), to check on the first
  France build by comparing a few routes on both machines.
- **Disk**: the tiles go on the root disk (local NVMe), not on the data
  volume: they are memory-mapped and read at random, which local storage
  serves faster, and they can be rebuilt. About 20 GB for France fits in the
  80 GB of a `cx33` (about 65 GB free); Europe (up to about 100 GB) needs the
  160 GB disk of a `cx43`.
- **Memory**: PostgreSQL takes a quarter of the memory for its buffers and
  assumes half for its cache (`effective_cache_size`), leaving the rest of
  the page cache to the tiles; the container is capped at 4 GB including the
  page cache it maps, which holds France. On 8 GB that is tight; serve France
  from a `cx43` (16 GB), Europe from a `cx53` (32 GB, 29.49).

## Security baseline

| layer | measure |
|---|---|
| account | a Hetzner project of its own, sharing nothing with other projects |
| network | Hetzner Cloud Firewalls: SSH from the admin sources only on both servers; 80, 443 tcp and udp, ICMP from anywhere; nothing else in |
| network | nftables on both: default drop in and forward, per-source limits on new SSH connections and on new and concurrent web connections (IPv6 per /64); only this table is reloaded, fail2ban's bans survive; the only filter of the private network |
| ops access | the ops server reaches the backend through one account, `lunaway-pull`, from one private address, with two keys each forced to one read-only command (the health probe, `rrsync -ro` on the encrypted dumps); the backend never connects to the ops server; the Mac's key on the ops server is forced to `rrsync -ro` on the replica and accepted from the admin sources only |
| backups | off-site copies encrypted with age to a key that exists only on the Mac; the ops server and the replica hold ciphertext |
| SSH | admin `ops` only (plus `lunaway-pull`, from 10.42.0.3 only on the backend, from the admin sources on the ops server), keys only, no root, `MaxAuthTries 3`, `LoginGraceTime 20`, no forwarding of any kind, post-quantum hybrid key exchange first, no NIST host key, RSA keys of 3072 bits or more |
| SSH | fail2ban `sshd` jail (aggressive mode, systemd backend, nftables action, increasing ban time); the admin sources (no range wider than /16 or /48) and, on the backend, the ops server's private address are exempt |
| system | unattended upgrades from Debian security, PGDG and Caddy; reboot at 02:30 UTC when needed; needrestart restarts services; the upgrade waits for a running dump |
| system | sysctl hardening (rp_filter, no redirects or source routing, syncookies, kptr and dmesg restriction, BPF and ptrace limits, protected links), unused protocols and filesystems blacklisted, no core dumps, AppArmor, chrony, persistent journal capped at 1 GB and one month, swap on zram (compressed memory, never on a disk) |
| packages | the Caddy repository's signing key accepted only with its pinned fingerprint, the source line written from the repository; Gatus and the Rust build image pinned by digest |
| data | volumes mounted `nodev,nosuid,noexec`, their mount point immutable when unmounted; services require the mount |
| PostgreSQL | localhost only, SCRAM, a DDL owner and two row roles (API, imports) with timeouts and no default privileges: the migrations grant each table to the role that needs it, and `test-grants.sh` checks the exact list in production; the statistics views closed to them; connection caps under `max_connections` (API 30, imports 10, owner 5); data checksums, builtin C.UTF-8 collation (no glibc collation drift), slow-query log without bound values; passwords set with statement tracking and statement logging off |
| PostgreSQL | systemd sandbox over Debian's unit: runs as `postgres` with no capabilities, read-only system except its data, socket and log directories, syscall filter, W^X memory, loopback-only network |
| web | Caddy: automatic TLS from Let's Encrypt, HTTP/3, HSTS, strict CSP, `nosniff`, `no-referrer`, frame denial, 1 MB request bodies on the API, header and body read timeouts, admin API on a private unix socket; access log and Caddy's own log with IPv4 truncated to /16 and IPv6 to /32, no port, kept 14 days |
| API | systemd sandbox: dynamic user, no capabilities, read-only system, private /tmp and devices, syscall filter, W^X memory, loopback-only network (no outbound request), may bind only 8484, memory capped at 1 GB; CORS for `https://lunaway.net` only |
| imports | the same sandbox under a static user, outbound connections allowed except to private and link-local ranges (the private network, the metadata service), writes only to `/srv/data/ingest`, memory capped at 2 GB |
| status page | Gatus under its own user with the same sandbox, listening on loopback; Caddy in front refuses anything but GET and HEAD |
| basemap | pmtiles under a dynamic user with the API's sandbox, loopback only (8485), the tile volume read-only and nothing else under `/srv`; its refresh as `lunaway-tiles`, writing only the archives, links and TileJSON, outbound HTTPS except to private ranges; go-pmtiles and the fonts pinned by hash; Caddy accepts GET, HEAD and OPTIONS only on the tile routes, at most 64 requests to pmtiles at once; tile coordinates and byte ranges never logged |
