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
     /upload ── lunaway-api, writes the photos     public status page, checks from outside
     /media/ from /srv/data/media
     /tiles/ ── 127.0.0.1:8485 pmtiles serve       dump replica, 14 days, and photos (/srv/data/backups)
       planet archive on /srv/tiles (own volume),
       refreshed monthly from Protomaps,
       and the offline packs cut from it
     /fdroid/repo/ from /srv/lunaway/fdroid
   PostgreSQL 18 + PostGIS (localhost)
   lunaway CLI timers: ingest; conflation worker (NOTIFY, 5 min)
   nightly dump and photo copy, age-encrypted
   lunaway-pull ◄── SSH over lunaway-net ───────── Gatus probe key: health JSON
                    (10.42.0.0/16), forced ─────── replica key: rrsync -ro, encrypted dumps and photos
                    commands, from 10.42.0.3 only

 maintainer's Mac, 04:30 local ── SSH, rrsync -ro ──► ops replica ──► ~/Backups/lunaway, 29 days
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
| `infra/server/*.sh` | server, root | backend steps `harden data-volume postgres caddy tiles backups api pipeline routing ops-access`, ops steps `harden data-volume ops-replica ops-status`, and the test and release helpers |
| `infra/deploy-api.sh` | here | builds a commit in a container (`infra/build/build-api.sh`), uploads the API and the CLI, migrates, switches the release, checks |
| `infra/build/remote-build.sh` | here | with `LUNAWAY_BUILDER=hetzner`, the same build on a throwaway Hetzner server, deleted at the end |
| `infra/deploy-gatus.sh` | here | copies the pinned Gatus binary out of its official image and installs it on the ops server |
| `infra/deploy-web.sh` | here | deploys the landing site or the Flutter web build as a new release |
| `infra/deploy-basemap-assets.sh` | here | deploys map styles or a sprite set to the basemap host |
| `infra/files/usr/local/sbin/lunaway-admin` | backend | the CLI by hand, as the API or as the imports (see "Data pipeline") |
| `infra/tests/api-flow.py` | here | accounts and photos end to end against a deployed API: creates an account, reads the vehicle limits and the points of interest around a place, confirms it and retracts the confirmation, uploads a photo, deletes the account (`uv run`) |
| `infra/ssh-access.sh` | here | which addresses may reach SSH on both servers |
| `infra/enable-domain.sh` | here | turns on the lunaway.net sites once DNS points at the backend |
| `infra/verify.sh` | here | external and internal checks of both servers, the status page, the pulls, and what each database role may do (`infra/server/test-grants.sh`) |
| `infra/files/` | server | configuration files, installed at the same path under `/`; `files/roles/<role>/` holds the per-role ones |
| `infra/systemd/` | server | units and drop-ins, installed in `/etc/systemd/system/` |
| `infra/caddy/` | servers | the backend's Caddyfile and domain sites, the ops server's `status.Caddyfile` |
| `infra/tiles/` | here, backend | the basemap's pins (`version.sh`: go-pmtiles, basemaps-assets, the tile schema) and `assets-hash.py`, which computes the fonts and sprites pin; `packs/regions.py` builds `packs/regions.geojson`, the outlines of the offline packs (see "Offline packs") |
| `infra/fdroid/` | here | Lunaway's own F-Droid repository: `keys.sh` (its two keys), `publish.sh` (an APK into the repository, up to the server), `requirements.txt` (fdroidserver, pinned with hashes), `legal.p2p.lunaway.yml` (the app's metadata there), and `fdroiddata/` (the draft for the official F-Droid); see "F-Droid repository" |
| `infra/ops/gatus/` | ops | Gatus's configuration template and the pinned release (`version.sh`) |
| `infra/ops/mac/` | the Mac | the nightly job, its launchd plist and `install.sh` |
| `infra/web/site/` | backend | the website, generated by `tool/site/build.py` from `tool/site/src/` (French at `/`, English under `/en/`); `infra/web/app/` is the web app's fallback page |
| `infra/tests/caddy-layout.sh` | here | runs `infra/caddy/` in the servers' Caddy release (native binaries on macOS and Linux x86_64, the Docker images with `LUNAWAY_CADDY_DOCKER=1`), the tile routes against a real `pmtiles serve`, and checks every route, header and the log masking |
| `infra/routing/` | GitHub Actions, backend | the routing engine: its pins (`version.sh`), the graph build (`build-graph.sh`, `valhalla-build.sh`, `osmium.Dockerfile`, `test-routes.json`), its measurement (`measure-build.sh`, `measure-remote.sh`), the weekly workflow (`.github/workflows/routing-graph.yml`), and on the backend the engine's units (`valhalla.container`, `valhalla-candidate.container`), its configuration (`valhalla.json`) and the graph refresh (`lunaway-routing-refresh` and its unit and timer) and the public half of the build key (`routing-signers`); installed by the backend step `routing`; see "Routing" |

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
| `LUNAWAY_MEDIA_BASE_URL` | optional: the public URL of the photos the API writes, `https://<backend sslip.io name>/media/` by default, `https://api.lunaway.net/media/` once DNS exists (see "Photos") |
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
| the F-Droid repository key, the F-Droid APK key and their passwords | the Mac, `~/.config/lunaway/fdroid/` (0700, files 0600), and an age-encrypted copy in the backup chain (see "F-Droid repository") |

## First installation

```bash
infra/ops/mac/install.sh keys   # the age identity and the pull key, on the Mac
infra/provision.sh              # both servers, the network, the volumes; waits for cloud-init
infra/configure.sh ops          # first: generates the probe and replica keys, pins the backend's host key
infra/configure.sh backend      # every backend step; lunaway-pull takes the ops server's keys;
                                # the tiles step starts the first planet download and its checks (about 45 minutes)
infra/deploy-api.sh             # builds HEAD, migrates, deploys, checks https://<ip>.sslip.io
infra/configure.sh backend pipeline   # turns the import timers and the conflation worker on, now that the CLI is there
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
| `lunaway-backend-1` | cx33, 4 vCPU, 8 GB, 80 GB NVMe, fsn1 | the API, PostgreSQL and the imports need little at launch; 8 GB also holds the France routing graph, without much room (see "Routing") | 8.49 |
| its daily backups | 20% of the server | images of the root disk, which carry a copy of the latest dumps | 1.70 |
| `lunaway-data` | volume, 150 GB | database, dumps, import cache, photos (budget below) | 8.58 |
| `lunaway-tiles` | volume, 350 GB | the basemap: two planet archives at the peak of a refresh, and two sets of offline packs (see "Basemap") | 20.02 |
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

Without a working local Docker, `LUNAWAY_BUILDER=hetzner infra/deploy-api.sh`
runs the same container on a throwaway server
(`infra/build/remote-build.sh`): a cx33 in fsn1 (x86_64 like the backend, so
no cross linker) named `lunaway-builder-1`, labelled
`project=lunaway,purpose=build`, behind the backend's firewall, created by
`hcloud` in the `lunaway` context and deleted when the build ends, failed or
not. The build of 0708e91 on 2026-10-06 took about 5 minutes of server time
(3 min 32 s of compilation), under a cent at 0.0136 EUR excl. VAT an hour.
Third-party build code (crates' build scripts) runs there, never on a
production server. The binaries it returns go to production, so the builder
is authenticated: an ed25519 host key generated here for each build goes in
through cloud-init and is pinned before the first connection
(`StrictHostKeyChecking=yes`, `-F /dev/null`); a build with the pinned key
took 5 min 44 s on 2026-10-06. A builder left by an interrupted run is
refused by the next one; delete it with `hcloud --context lunaway server
delete lunaway-builder-1`.

## Photos

The API takes a photo on `POST /upload` (`multipart/form-data`, a place and
an image, a session of trust level 1), rewrites it as two WebP files without
any metadata (2048 px and 512 px) and writes them under
`/srv/data/media/photos/<2 hex>/<2 hex>/<SHA-256>.webp`; Caddy serves them
under `/media/` with a year of cache.

- Caddy routes `/upload` to the API on the API hosts (the sslip.io name and
  `api.lunaway.net`): `POST`, and `OPTIONS` for the web app's preflight,
  anything else 405. The body may reach 10304 KiB there (10 MiB of image
  and 64 KiB of form, what the API accepts). A `/graphql` body may reach
  64 KiB (the API's own limit) and Caddy reads it whole before it opens a
  request to the API (`request_buffers`), so a slow client never holds a
  connection or a task of the API; 1 MB elsewhere.
- Caddy 2.11 has no per-route read timeout (`request_body` takes no
  `read_timeout`, in the Caddyfile or in JSON, checked on 2.11.7), so the
  server's `read_body` is 3 minutes for every request; headers still have
  10 seconds. The API gives an upload 120 seconds to arrive, so a 10 MiB
  photo needs about 700 kbit/s; the app should shrink photos first.
- The API runs as the static user `lunaway-api`, which owns
  `/srv/data/media` (0755, files 0644 for Caddy). Its unit sees nothing else
  of `/srv` and may write only there. `/etc/lunaway/media.env` gives it
  `LUNAWAY_MEDIA_DIR` and `LUNAWAY_MEDIA_BASE_URL`, rendered by
  `infra/server/api.sh` from `LUNAWAY_MEDIA_BASE_URL` (configure.sh). URLs
  are built at each answer from the stored paths, so changing the base later
  changes every URL at once.
- Two photo decodes at once take up to about 1 GB: the API's memory cap is
  1.5 GB (`MemoryHigh` 1.25 GB).
- Measured on 2026-10-06 with a 1600 by 1200 test JPEG: 0.9 to 1 second
  per upload, 517 to 529 KB for the large WebP and 104 KB for the thumbnail.
  At about 0.63 MB a photo, 10,000 photos take 6.3 GB in each of four
  places: `/srv/data/media`, its encrypted copy on the backend, the ops
  server's replica, the Mac. The ops server's 20 GB volume is the first to
  fill (about 25,000 photos with the deleted ones it holds); grow it with
  `hcloud volume resize lunaway-sync-data --size <GB>` and `resize2fs`.

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
| `lunaway-ingest-pois.timer` | daily, 03:45 UTC, after the places import | `lunaway ingest pois`: the points of interest of the same cached extract, then their opening hours (3 GiB cap) |
| `lunaway-ingest-fuel.timer` | every 15 minutes (`*:05/15`) | `lunaway ingest fuel --refresh`: the fuel price feed, joined to the fuel stations |
| `lunaway-ingest-laposte.timer` | daily, 04:10 UTC | `lunaway ingest laposte --refresh`: La Poste's calendar for two weeks, joined to the post offices |
| `lunaway-ingest-finess.timer` | the 2nd of each month, 04:20 UTC | `lunaway ingest finess --refresh`: the FINESS snapshot (closures); snapshots older than 45 days are removed |
| `lunaway-conflate.service` | after each successful import (`OnSuccess=`) | `lunaway conflate` |
| `lunaway-conflate-worker.service` | always (`Restart=always`, 15 s apart, at most 10 starts in 15 minutes) | `lunaway conflate --watch`: applies the community's submissions, refreshes the places' community summaries, conflates what the imports flagged, and slides the opening hours to the new day. The API wakes it with a `NOTIFY` when it commits work; it also runs at least every 5 minutes |
| `lunaway-worker-status.timer` | every minute | as `postgres`: the worker's queue sizes and ages, and the age of the last stored fuel feed, into `/var/lib/lunaway-status/worker.json` for the health probe |
| `lunaway-migrate.service` | on a deploy only | `lunaway migrate`, as `lunaway_owner` |

The nightly conflation timer of earlier versions is gone: the worker runs at
least every 5 minutes and recomputes "today" at each run.

Every writer of the catalogue (an import, a conflation, the worker) takes
the same transaction-level advisory lock (`pg_advisory_xact_lock`,
`backend/crates/lunaway-db/src/lib.rs`) and waits for it up to 30 minutes,
so they run one after the other and never lock records in opposite orders.
The worker, `lunaway-conflate.service` and the import units run the same
binary, so they agree on the lock. The worker needs no network but loopback.
The connection caps leave room for all of them at once (`lunaway_ingest` 15:
the worker's pool of 4 and its `LISTEN` connection, an import, a
conflation). The timers stay off while the release carries no CLI, and the
worker while its CLI has no `conflate --watch`;
`infra/configure.sh backend pipeline` turns them on. `install-release.sh`
restarts the worker on each deploy.

### `lunaway-admin`: the CLI by hand

`/usr/local/sbin/lunaway-admin` runs the current release's CLI as a
transient systemd service with the identity, role and sandbox the command
needs, and passes its output back:

```bash
sudo lunaway-admin moderation list                       # as the API: user lunaway-api, role lunaway_app,
sudo lunaway-admin moderation approve <entry> --note TEXT  # write access to /srv/data/media only (a
sudo lunaway-admin moderation ban <account> --reason TEXT # removal deletes the photo files)
sudo lunaway-admin accounts create-demo --level 2        # the store reviewers' account: prints its recovery code
sudo lunaway-admin accounts set-level <account> 4        # a moderator
sudo lunaway-admin ingest osm-extract                    # as the imports: user lunaway-ingest, role lunaway_ingest,
sudo lunaway-admin ingest municipalities                 # the import cache, HTTPS out (no private ranges)
sudo lunaway-admin ingest pois                           # 3 GiB cap for the imports (the extract reader)
sudo lunaway-admin conflate --full
sudo lunaway-admin stats
sudo lunaway-admin pois stats                            # the layer of points of interest and its joins
sudo lunaway-admin road-events stats                     # the road events by source, class and placement
sudo lunaway-admin migrate                               # starts lunaway-migrate.service
```

### Points of interest

The layer "around me" (`plan/research/18-backend-poi.md`): 314 671 points
on 2026-10-06 (shops, vending machines, water, fuel, health, services) from
the OpenStreetMap extract, joined by id to the fuel price feed, La Poste's
calendar and FINESS. The API serves it as PostGIS vector tiles:

- `GET /poi/tiles.json`: the TileJSON, cached 60 s. Its tile URLs name the
  API's public URL, `LUNAWAY_PUBLIC_URL` in `/etc/lunaway/media.env`,
  which `infra/server/api.sh` derives from the photos' base URL (the
  sslip.io name until DNS exists, then `https://api.lunaway.net`).
- `GET /poi/{version}/{z}/{x}/{y}.mvt`: points from zoom 13, clusters per
  category from 6 to 12. The current version is cached a year
  (`immutable`); any other version gets the current data for 5 minutes.
  204 outside the layer's bounds.

Caddy passes `GET`, `HEAD` and `OPTIONS` under `/poi/` to the API, with a
body of 1 KiB at most, and answers 405 to anything else; the API sets the
cache headers, the ETag, the compression and the CORS headers of
`https://lunaway.net`. The access log keeps the zoom only
(`/poi/{version}/{z}/x/y.mvt`), like the basemap's. Measured on
2026-10-06 from the maintainer's network: a z13 tile over Annecy holds 426
points, 16.7 KB gzip, 0.23 s cold and 0.12 s from the API's memory; the z8
tile around it holds 2 136 clusters, 11.8 KB.

The imports need no host list in their units (they deny only private
ranges); the hosts each source may reach or redirect to are in the code
(`REDIRECT_HOSTS` in `lunaway-ingest/src/http.rs`). First runs on the
backend, 2026-10-06:

| import | duration | anonymous memory, peak | cap |
|---|---|---|---|
| `ingest pois` | 7 min 48 s | 1.53 GiB (plus 2.1 GiB of page cache) | 2.5 GiB soft, 3 GiB |
| `ingest fuel --refresh` | 5 s | 163 MiB | 384 MiB soft, 512 MiB |
| `ingest laposte --refresh` | 62 s | 627 MiB | 1 GiB soft, 1.5 GiB |
| `ingest finess --refresh` | 16 s | 64 MiB | 768 MiB soft, 1 GiB |

The places import reads the extract with the same reader and peaked at
2.5 GiB with its page cache the same day; its cap went from 2 to 3 GiB.
The database grew from 323 MB to 994 MB (`pois` 591 MB, the joins 73 MB);
the cache holds 12 MB of fuel feed, 41 MB of La Poste pages and 49 MB a
month of FINESS.

### Europe and the regional packs (to install)

Not installed on 2026-10-06; the measurements and the run procedure are in
`plan/research/23-backend-europe-packs.md`.

- **Imports.** `lunaway ingest osm-extract --europe --refresh`, then
  `lunaway ingest pois --europe`, read France and 23 other extracts one at
  a time (`osm_extract::EUROPE`, 27.8 GB of files on 2026-10-06): the
  memory is the largest country's, France's, as today. A run that stops
  resumes after the last extract it stored, and does not download again a
  file younger than `--max-age-hours` (20). Each record is stored under its
  country, and a run retires only in the countries it read; in a country
  where it saw less than half of what is stored (10 records or more), it
  retires nothing and exits with an error after storing the rest.
- **Worker.** `lunaway conflate --watch --poi-layer-every-mins 360`: the
  tiles version of the points layer moves at most every six hours (the
  default), whatever the fuel poller, the imports or the community change
  meanwhile.
- **Packs.** `lunaway packs build --dir /srv/data/packs` (or
  `LUNAWAY_PACKS_DIR`) after the conflation that follows the daily import,
  as the import role: it writes `places/<region>-<seq>-<hash>.sqlite.gz`
  for every region whose places changed and records them in `region_packs`.
  The API host serves `/srv/data/packs/` read-only under `/packs/`
  (byte ranges, a year of cache: a file never changes under its name), and
  `Query.regions` names them under `LUNAWAY_PUBLIC_URL/packs/`. The route
  serves only names of the form
  `^/packs/places/[A-Z0-9-]+-[0-9]+-[0-9a-f]{12}\.sqlite\.gz$` (the
  build writes its work files in `/srv/data/packs/.work/`, never served),
  and the access log masks them as `/packs/places/[pack]`, since a pack
  names the region a traveller is heading for. After a place is taken down
  (its tombstone in the feed), `lunaway packs build --region <code>
  --takedown` rebuilds its region and every region whose pack is behind,
  and removes every pack file the manifest does not name (a region left
  without a live place loses its pack and its files). Builds take an
  advisory lock: a takedown run during the daily build waits for it, up to
  half an hour.
- **Once, at the deployment:** `lunaway conflate --full`, so a place only
  the community describes gets the country of its position, hence a sync
  region.

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
| public | Offline packs manifest | `<tiles>/packs/manifest.json` answers 200, version 1, at least one pack |
| public | POI TileJSON | `/poi/tiles.json` answers TileJSON 3.0.0 whose tiles are on the API host |
| public | POI tile | a z13 tile over Annecy at the old version 1 (the current data, whatever the version) answers 200, more than 1000 bytes, within 3 s |
| public | Routing | `{ routing { available graph { builtAt } } }` answers `available: true`: an active graph, and the engine answers |
| public | Witness route | every 15 minutes, a 3.3 m motorhome on Rue Maurice Utrillo in Limoges: `status OK` and more than 1000 m, round the 2.7 m bridge (four routes an hour, against a quota of 30 every ten minutes) |
| public | Road events (DIR feed read) | `roadEventSources`: the DIR, first in the list, read less than 15 minutes ago |
| public | Road events (DiaLog read) | DiaLog, second, read less than 45 minutes ago |
| public | Road events feed | `roadEvents(first: 1)` answers a cursor within 3 s |
| backend | Conflation worker | the probe: `lunaway-conflate-worker` active, its queues measured less than 5 minutes ago, nothing waiting there for 15 minutes |
| backend | Photo backup | the probe: the encrypted copy of the photos brought up to date less than 26 hours ago |
| backend | PostgreSQL | the health probe reports `pg_isready` on loopback |
| backend | Data volume | mounted, under 80% full; root disk under 85% |
| backend | Nightly dump | succeeded less than 26 hours ago, no failure recorded after it |
| backend | Basemap build | the tile volume is mounted and the planet served is less than 35 days old (a refresh failed otherwise) |
| backend | Offline packs | the probe: the packs' manifest names one pack per outline, its build is less than 35 days old and is the planet served (or the planet switched less than a day ago) |
| backend | Fuel prices | the probe: the fuel price feed was stored less than 2 hours ago (eight runs of `lunaway-ingest-fuel` in a row failed otherwise) |
| backend | Routing graph | the probe: `valhalla.service` active, serving a graph built less than 10 days ago (weekly build, daily refresh) |

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
   (the ops server may be rebooting for an update at 02:30 UTC). The
   encrypted photos go to `~/Backups/lunaway/media/`. macOS's rsync
   (openrsync) sends `--delete` to the server even on a pull, which
   `rrsync -ro` refuses, so the job pulls without it: a copy the server's
   list (`media/manifest`) no longer names goes to `media-deleted/<day>/`,
   `<day>` being the backend's deletion date (`media/deletions`), and is
   dropped 26 days after it, or at once when the list of the last 30 days
   does not name it. A run that would set aside more than 50 copies and
   more than 5% of them sets none aside and fails. It decrypts the newest
   photo copy (it must be a WebP file) and fails when the copy is more than
   36 hours old;
2. checks the newest dump: decrypts and lists it with `pg_restore --list`,
   without writing the plaintext; created less than 36 hours ago according
   to the archive itself (age authenticates it, so a renamed old dump fails);
   no failure recorded after the last success; drops what is older than 29
   days, so no dump outlives an account deleted after it by more than 30
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
systemctl list-timers 'lunaway*'             # dump, imports, conflation, basemap refresh and packs (backend), replica (ops)
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
| `lunaway.net/` | `/srv/lunaway/site` | website, script-free except `/account/delete` (its own CSP); `/privacy`, `/account/delete`, `/about` map to `privacy.html` or `privacy/index.html`; hashed assets cached a year, the rest five minutes |
| `lunaway.net/app/` | `/srv/lunaway/web` | Flutter web build; the app's routes (`/app/place/42`) fall back to `/app/index.html`, a missing file (under `assets/`, `fonts/`, `canvaskit/`, `icons/`, or any name with an extension) is an empty 404, so a fallback font Flutter asks for never gets HTML; revalidated on every load; its CSP allows `tiles.lunaway.net` as the only tile host |
| `www.lunaway.net` | | permanent redirect to `https://lunaway.net` |
| `tiles.lunaway.net` | pmtiles serve, `/srv/tiles` | the basemap (see "Basemap"); the sslip.io name serves the same under `/tiles/` |

The sslip.io name of the backend serves the API snippet too, `/media/`
included. `infra/tests/caddy-layout.sh` runs this configuration in the
Caddy release the servers run (2.11.7: native binaries pinned by hash on
macOS and Linux x86_64, bound to loopback; the Docker image with
`LUNAWAY_CADDY_DOCKER=1`), with plain HTTP and test roots, and checks each
route and header, and that the logs mask client addresses, tile
coordinates and photo paths; run it after editing `infra/caddy/`. Once the A and AAAA records of the four names point
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
and `LUNAWAY_WEB_URL`, and rerun `infra/configure.sh ops ops-status`; set
`LUNAWAY_MEDIA_BASE_URL=https://api.lunaway.net/media/` and rerun
`infra/configure.sh backend api`.

### Deploying the landing site and the web app

```bash
python3 tool/site/build.py                 # regenerates infra/web/site/ from tool/site/src/
infra/deploy-web.sh site infra/web/site     # index.html at the root
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
| age-encrypted | backend `/srv/data/backups/offsite/` (7), pulled at 01:15 UTC into the ops server's volume in nbg1 (14 days), pulled at 04:30 local into the Mac's `~/Backups/lunaway/` (29 days) | |
| photos, age-encrypted | backend `/srv/data/backups/offsite/media/`, the ops server's `/srv/data/backups/postgresql/media/`, the Mac's `~/Backups/lunaway/media/` | as long as the photo exists, then until 26 days after its deletion date |
| the F-Droid keys, age-encrypted | backend `/srv/data/backups/offsite/fdroid-keys-<stamp>.tar.age`, the ops server's replica, the Mac's `~/Backups/lunaway/` | every copy, never pruned (see "F-Droid repository") |

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
- The photos (`/srv/data/media/photos`): `lunaway-media-offsite.timer`
  (00:45 UTC) encrypts each new photo file with age, to the same recipient,
  into `/srv/data/backups/offsite/media/photos/` (one `.age` file for one
  photo; a photo never changes, so each is encrypted once), removes the
  copies of photos deleted since and notes them with the date in
  `media/deletions` (30 days of entries), and writes `media/manifest` (the
  list of copies) and `media/last-success`. It runs as root without
  capabilities, as a member of `lunaway-pull`, and writes only that
  directory. A run that would remove more than 50 copies and more than 5%
  of them, or that finds `/srv/data/media/photos` missing, removes nothing
  and fails (the Photo backup check turns red);
  `LUNAWAY_MEDIA_ALLOW_MASS_REMOVAL=1` in the unit's environment lets a
  deliberate one through. The ops server pulls the copy at 01:15 UTC with
  `--delete`, setting what disappeared aside in
  `/srv/data/backups/media-deleted/<deletion date>/`; the Mac does the same
  in `~/Backups/lunaway/media-deleted/<deletion date>/` (see "The nightly
  job on the Mac"). Both drop a deleted photo's copy 26 days after the
  backend's deletion date, however late they run, and at once when the
  last 30 days of the list do not name it: a photo deleted on the backend
  (an account deleted, a moderation) leaves every copy within 29 days,
  inside the 30 days the privacy page announces, and a mistaken deletion
  can be restored meanwhile. The status page checks the copy (Photo
  backup).
- A dump restored brings back the accounts deleted after it was taken: the
  backend has no record of those deletions to apply again yet (an open
  point for the backend).
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

Photos come back from the Mac's copy: decrypt each file to its name without
`.age` (its SHA-256 must equal its name), then copy the tree into
`/srv/data/media/photos/` on the backend, owned by `lunaway-api`:

```bash
cd ~/Backups/lunaway/media
find photos -name '*.webp.age' | while read -r f; do
  mkdir -p "$HOME/restore-media/$(dirname "$f")"
  age --decrypt --identity ~/.config/lunaway/backup-age.key -o "$HOME/restore-media/${f%.age}" "$f"
done
```

A photo deleted by mistake is in `media-deleted/<day>/` (Mac or ops server)
for 26 days; its database row comes back with the dump of before the
deletion.

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
| `/sprites/protomaps-v4/{light,dark,white,grayscale,black}[@2x].{json,png}` | Protomaps' sprites, which the styles name | a day |
| `/sprites/lunaway-pins/pins[@2x].{json,png}` | the app's place markers (111 images, from `app/tool/map_sprites/`), for a web page that draws them by name | a day |
| `/styles/<name>.json` | map styles: the app's Aube and Minuit in French and English (`aube-fr`, `aube-en`, `minuit-fr`, `minuit-en`, from `app/tool/map_style/`), and Protomaps' defaults (`protomaps-light`, `protomaps-dark`) | an hour |
| `/packs/manifest.json` | the offline packs' manifest (see "Offline packs") | five minutes |
| `/packs/<region>-<YYYYMMDD>-<digest>.pmtiles` | an offline pack, whole or by byte range | a year, immutable |

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
  `Content-Length`, `Content-Range`, and the response size. A photo's
  file name points at a place too: every path under `/media/` is logged as
  `/media/[photo]`. A pack's name says where a traveller is heading: every
  pack is logged as `/packs/[pack].pmtiles`.

```
/srv/tiles/
  builds/<YYYYMMDD>.pmtiles      planet archives: the current one and the previous
  serve/planet-<YYYYMMDD>.pmtiles, serve/planet.pmtiles   symlinks into builds/
  tilejson/planet.json           written by the refresh, a template Caddy fills in per host
  assets/fonts/ assets/sprites/ assets/styles/
  packs/manifest.json, packs/<region>-<YYYYMMDD>-<digest>.pmtiles   offline packs, two sets
  packs/.work/<YYYYMMDD>/        the set being built, never served
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
The offline packs take about 19 GB a set and two sets stay, so the volume
went to 350 GB on 2026-10-06 (369 GB formatted, `df -B1`), online
(`hcloud volume resize lunaway-tiles --size 350`, then `sudo resize2fs
/dev/disk/by-id/scsi-0HC_Volume_<id>` on the backend): two planets and two
sets of packs take about 318 GB at the peak of the December 2026 refresh,
which leaves about 50 GB, three years of growth at the 2026 rate.

### Offline packs

The app works without network, the map included: before a trip it
downloads the basemap of a region as one PMTiles file, a `pmtiles extract`
of the planet served, zoom 0 to 14. 40 regions: the 13 regions of
metropolitan France and the 5 overseas regions, and 22 countries (Spain,
Portugal, Italy, Germany, Austria, Switzerland, Belgium, the Netherlands,
Luxembourg, the United Kingdom, Ireland, Denmark, Norway, Sweden, Finland,
Croatia, Slovenia, Greece, Poland, Czechia, Andorra, Morocco). 19.4 GB
(19,388,729,661 bytes) for the whole set of 2026-10-05: from 4.2 MB
(Mayotte) and 23 MB (Corsica) to 421 MB (Auvergne-Rhône-Alpes), 209 MB
(Morocco), 1.3 GB (United Kingdom) and 2.7 GB (Germany).

**Outlines.** `infra/tiles/packs/regions.py` (`uv run
infra/tiles/packs/regions.py`, on a workstation) writes
`infra/tiles/packs/regions.geojson`, committed, from two sources pinned by
SHA-256: the French regions of the data.gouv.fr "Contours administratifs"
2025 (100 m, IGN Admin Express and OpenStreetMap, ODbL) and Natural Earth
1:10m admin 0 countries v5.1.2 (public domain). Each outline is filled
(enclaves such as San Marino fall inside), widened by 3 km for a French
region and 8 km for a country (Natural Earth draws coasts at 1:10 million;
the margin keeps the coast, the near islands and the roads across a
border), simplified to 500 m, 16,892 vertices in all, 309 KB. Svalbard,
Jan Mayen, Bouvet Island, Rockall and the Caribbean Netherlands are left
out; the Canary Islands, Madeira and the Azores stay. Natural Earth's
Morocco reaches 21.4 degrees north (Dakhla is in it). Adding a region is a
line in the script (`COUNTRY_LIST` or `FR`), a run, a commit, then
`infra/configure.sh backend tiles` and `sudo systemctl start
lunaway-tiles-packs` on the backend: the script leaves the other outlines
byte for byte as they were, so their packs keep their names and are
reused, and only the new pack is built (Morocco on 2026-10-06: 39 reused,
one built in 2 s, 3 s in all).

**Zoom 14.** Measured on the build of 2026-10-05 (`pmtiles extract
--dry-run` for every region, real extracts of three):

| pack | zoom 0 to 13 | 0 to 14 | 0 to 15 |
|---|---|---|---|
| Bretagne | 84 MB | 163 MB | 346 MB |
| Île-de-France | 48 MB | 103 MB | 263 MB |
| Switzerland | 190 MB | 359 MB | 719 MB |
| the first 39 (before Morocco) | 10.3 GB | 19.2 GB | 38.0 GB |

Zoom 13 lacks the streets: over Locronan (Finistère) its tile names 7
roads, the four zoom 14 tiles of the same area 136, the sixteen zoom 15
tiles 134 (`minor_road` features: 5, 144, 195). Zoom 15 adds the buildings
(7 at zoom 14, 2,123 at zoom 15 there; 60 and 15,191 over Annecy) and most
shops and amenities as basemap icons, for twice the size; the map renders a
zoom 14 tile at any closer zoom (overzoom). Germany at zoom 15 also needs
4217 MiB of memory to extract (1995 MiB at zoom 14), more than the backend
can spare. Hence zoom 14: every street, half the size of zoom 15.

**The job.** `lunaway-tiles-packs.service` runs
`/usr/local/sbin/lunaway-tiles-packs` as `lunaway-tiles`, with no network
at all, after each successful planet refresh (`OnSuccess=` of
`lunaway-tiles-refresh.service`) and daily at 07:15 UTC
(`lunaway-tiles-packs.timer`), which finds nothing to do when the manifest
already names the served build:

1. one GeoJSON per outline of `/usr/local/share/lunaway/pack-regions.geojson`
   (installed from the repository by the `tiles` step); each pack's name
   carries the build and a digest of its outline, its zoom and the pmtiles
   release, so a name never changes content (`pmtiles extract` writes the
   same bytes from the same input: two extracts of Bretagne had the same
   SHA-256 on 2026-10-06);
2. a pack the manifest already lists under the same name, with its file of
   that size, is reused with the manifest's SHA-256: a new or changed
   outline rebuilds its own pack only;
3. a dry run of every pack still to build for the room it needs, plus a
   tenth and 2 GB; when short, packs of sets older than the one the
   manifest names go;
4. each pack extracted into `packs/.work/<build>/`, checked by `pmtiles
   verify` and its header (MVT, gzip, zoom 0 to 14), hashed (SHA-256); an
   interrupted run keeps the packs it finished;
5. the packs renamed into `packs/`, then `manifest.json` replaced by an
   atomic rename; the set before the previous one goes. `packs/.work` sits
   inside `packs/` because the unit's sandbox makes each writable path its
   own mount, and a move between two mounts is a copy: the first run, with
   two paths, spent 123 s copying 19 GB.

First run, 2026-10-06: 215 s for the 39 extracts (Germany 29 s), 2.5 GB
memory peak with the page cache (`MemoryHigh` 2.5 GB, `MemoryMax` 3 GB).
`LUNAWAY_PACKS_DIR=/srv/tiles/packs-test` and `LUNAWAY_PACKS_REGIONS` run
the job on a test directory (a transient unit with that directory writable);
that is how the rotation of sets was checked.

```bash
sudo systemctl start lunaway-tiles-packs          # now (does nothing when up to date)
sudo journalctl -u lunaway-tiles-packs -f
```

**The contract for the app.** The manifest,
`https://tiles.lunaway.net/packs/manifest.json` (before DNS:
`https://<backend sslip.io name>/tiles/packs/manifest.json`):

```json
{
 "version": 1,
 "build": "20261005",
 "generated_at": "2026-10-06T12:40:45Z",
 "schema": "4.15.2",
 "osm_timestamp": "2026-10-05T04:00:00Z",
 "max_zoom": 14,
 "attribution": "© OpenStreetMap",
 "packs": [
  {
   "id": "fr-bre",
   "name": {"fr": "Bretagne", "en": "Brittany"},
   "kind": "region",
   "country": "fr",
   "bbox": [-5.1809, 47.2531, -0.9787, 48.9108],
   "url": "fr-bre-20261005-<digest>.pmtiles",
   "size": 162863132,
   "sha256": "<64 hex>",
   "build": "20261005",
   "min_zoom": 0,
   "max_zoom": 14
  }
 ]
}
```

- `version` changes only with an incompatible format; an app refuses a
  version it does not know. Fields may be added.
- `id`: ISO 3166-1 alpha-2 for a country (`es`), ISO 3166-2 for a French
  region (`fr-bre`, `fr-20r` for Corsica, `fr-974` for Réunion), lower
  case; stable across builds. `kind` is `region` or `country`, `country`
  the ISO 3166-1 code, for grouping.
- `bbox`: west, south, east, north in degrees, of the outline with its
  margin (Spain's reaches the Canary Islands, Portugal's the Azores).
- `url`: relative to the manifest's own URL. A new build means new names;
  a pack's URL never changes content, so a download can resume over days
  with `Range` and `If-Range` (the `ETag` of the first answer): a 206
  continues it, a 200 means the file changed and the download restarts.
- `size` and `sha256` of the whole file: check both before using a pack.
- `build`: the planet build (the date of its OpenStreetMap data), the same
  for every pack of a set, also in the TileJSON's tile URLs online. An
  installed pack is out of date when the manifest's `build` is newer; the
  previous set stays served for a month after a new one is published.
- `max_zoom`: the pack's last zoom; the style's source must say so
  (`maxzoom`), so the map scales zoom 14 tiles up beyond it.

A pack holds tiles only. Offline, the app also needs the style (it ships
Aube and Minuit), the glyphs and the sprites. The styles use three font
stacks (Noto Sans Regular, Medium, Italic): the full ranges weigh 6.9, 4.4
and 2.2 MB under `/fonts/`; the seven ranges of Latin, Greek and Cyrillic
(0-255 to 1024-1279, 7680-7935, 8192-8447) weigh about 0.7 MB per stack.
The app can open a downloaded pack as a PMTiles source
(`pmtiles://file://...` for MapLibre Native) or read a pack remotely
through the PMTiles protocol. The map must still show "© OpenStreetMap".

Checked from the Mac on 2026-10-06 against the sslip.io name: the manifest
(200, five minutes of cache, CORS `*`), two packs downloaded whole (SHA-256
equal to the manifest's), a download resumed at half the file (206, the
whole file's SHA-256 equal; a stale `If-Range` gets the whole file),
and tiles at zoom 6, 10 and 14 read by byte range from four packs (Bretagne,
Germany, Norway, Spain) byte for byte equal to the same tiles of the
planet; no zoom 15 tile in a pack. After Morocco was added: 40 packs in
the manifest, the Morocco pack (208,688,111 bytes) downloaded in two halves
with `If-Range` (206 twice) and hashed as it streamed, SHA-256 equal to the
manifest's, and its tiles over Marrakech, Dakhla and Tangier equal to the
planet's. The status page checks the manifest from outside and its age on
the backend ("Offline packs").

## Routing

The app's motorhome navigation asks the API for a route (`Query.route`);
the API asks a Valhalla engine on the backend's loopback, checks every route
against the physical limits it knows (`route_restrictions` in PostgreSQL),
and asks again around any limit the vehicle exceeds. Installed on
2026-10-06 by the backend step `routing` (`infra/server/routing.sh`):
Podman, the id ranges of `UserNS=auto`, the pinned image, the units, the
refresh and its files, `/srv/routing` and the build key. The step enables
the daily timer once a graph serves.

```
 GitHub Actions, Sundays 01:00 UTC (.github/workflows/routing-graph.yml)
   Geofabrik France extract + IGN BD TOPO restricted sections (WFS)
   lunaway routing prepare ─ osmium apply-changes ─ Valhalla build ─ route tests
   release `routing-graph`: graph.tar.gz parts, restrictions, signed SHA256SUMS
        │ HTTPS, pulled daily at 04:30 UTC by lunaway-routing-refresh
        ▼
 lunaway-backend-1
   /srv/routing/builds/<id>/   current ─► valhalla.service 127.0.0.1:8002
   route_restrictions (PostgreSQL)         ▲
   lunaway-api  Query.route ───────────────┘  check, exclusion rings, warnings
```

### The graph build

`infra/routing/build-graph.sh <extract> <dir>` runs every step, each
stopping the build on failure:

1. `lunaway routing fetch-ign`: IGN's restricted road sections (134 321 for
   France on 2026-10-06, 27 pages of the WFS, about 8 minutes), cached;
2. `lunaway routing prepare` (75 s and 3.7 GB of memory for France on the
   Mac): one reading of the extract writes `fixes.osc.gz`, the tags Valhalla
   must read differently (limits in canonical form, `maxweightrating` copied
   into `maxweight`, `motorhome=*` copied into `motorcar`, IGN limits on the
   ways they match, the lowest value winning), `restrictions.ndjson.gz`
   (266 389 restrictions: OpenStreetMap ways and nodes, IGN sections, each
   with its geometry and certainty), `prepare.json` and `build.json`;
3. `osmium apply-changes` (Debian's osmium-tool in `osmium.Dockerfile`);
4. Valhalla's build in the pinned image (`valhalla-build.sh`): roads only,
   no time zones, no elevation;
5. the route tests of `test-routes.json` on the new graph: the Limoges
   bridge of Rue Maurice Utrillo at 2.5, 2.71 and 3.3 m, the Pas Redon
   bridge (signed with `maxweightrating` alone) at 3.5 and 4.5 t,
   `motorhome=no` on Route de Grandchamp, an `hgv=no` road a motorhome may
   take, the 3.4 m porch of Rue Braille that only IGN measures, Brive to
   Ussel. On the raw France graph three of the ten fail (the porch, the
   weight rating, `motorhome=no`): what the preparation exists for;
6. the bundle, the graph in gzip parts under 1.9 GB (a release asset may not
   exceed 2 GiB).

Measured on 2026-10-06 (`measure-build.sh`, 4 threads, a 16 GiB cap):

| where | extract | build | anonymous memory, peak | work files, peak | graph |
|---|---|---|---|---|---|
| Mac Studio, Docker VM (arm64) | France, 5.87 GB (the import cache) | 18 min (admins 81 s, tiles 970 s, tar 29 s) | 6.1 GiB | 16.5 GiB | 3.25 GB |
| Hetzner cpx42, ephemeral (x86) | France, 5.09 GB (Geofabrik) | 20 min (admins 110 s, tiles 1 102 s, tar 5 s) | 6.1 GiB | 16.1 GiB | 3.59 GB |

The whole pipeline on the same cpx42 took 28 minutes: prepare 3 min (8
cores), osmium 98 s, the build 19 min, the ten route tests 3 s (all
passed; three of them fail on the raw graph), the bundle 3.6 min, for one
part of 1.48 GB and 11 MB of restrictions. The weekly build runs on GitHub
Actions, because the backend cannot hold it: about 6 GiB of anonymous
memory, which a memory cap cannot reclaim, against 8 GB shared with
PostgreSQL, the API and the tiles, and no container runtime installed. The
Mac is not part of the weekly run, and builds no France graph at all: one
filled its disk on 2026-10-06.

The first run on GitHub Actions (run 37433921370, 2026-10-06, ubuntu-24.04,
4 vCPUs, 145 GB disk with 105 GB free after the clean-up step) took 64
minutes for the build job: the CLI 3 min 9 s, the extract 9 min 55 s
(5.09 GB), then the graph step 49 min 9 s (IGN 11 min 23 s, prepare 5 min
46 s with a 4.3 GB peak resident size, osmium 3 min 49 s, Valhalla 24 min 24
s with tiles 1 295 s, the ten route tests 3 s, the bundle 3 min 44 s), for
one part of 1.48 GB; the disk then had 92 GB free. `/usr/bin/time -v`
measures the script and the `lunaway` CLI, not the Docker containers of
osmium and Valhalla. The publish job then took 2 min 28 s.

When a run fails:

- The IGN read is tried three times, five minutes apart: the WFS once cut
  a page off after 102 s (an HTTP/2 stream reset) that it served in 18 s
  ten minutes later.
- The publish job refuses a build older than six hours (`built_at` and the
  id must fall within the run). To publish a build again, re-run only the
  `publish` job within those six hours: it reads the artifact the build job
  left (kept three days).
- On 2026-10-06 the `publish` job of a re-run stayed `waiting` for 13
  minutes, with no reviewer and no timer on the environment; cancelling the
  run and re-running that job alone started it at once.

### The build key

The workflow's `publish` job signs `SHA256SUMS` with an ed25519 key
(`ssh-keygen -Y sign`, namespace `lunaway-routing-graph`); the backend
accepts a graph only when `ssh-keygen -Y verify` finds that signature by
the identity `lunaway-routing` in `/etc/lunaway/routing-signers`, installed
from `infra/routing/routing-signers`. The private half exists only as the
secret `ROUTING_SIGNING_KEY` of the GitHub environment `routing-graph`,
whose deployments are limited to `main`: it was generated on the Mac on
2026-10-06, stored with `gh secret set ... < file` and deleted. Nobody holds
a copy, so rotation is a new pair, never a recovered one:

```bash
mkdir -p data/tmp/routing-key
ssh-keygen -t ed25519 -C lunaway-routing -N "" -f data/tmp/routing-key/routing_ed25519
gh secret set ROUTING_SIGNING_KEY --env routing-graph --repo poka-IT/lunaway \
  < data/tmp/routing-key/routing_ed25519
rm data/tmp/routing-key/routing_ed25519
# then replace the key in infra/routing/routing-signers by the new .pub line,
# commit, and run: infra/configure.sh backend routing
```

Graphs signed by the old key stop installing as soon as the new
`routing-signers` is on the backend: run the workflow again after it so a
graph signed by the new key is published. The graph already served keeps
serving meanwhile.

### Serving on the backend

- `valhalla.service` (Quadlet unit `infra/routing/valhalla.container`):
  the official image pinned by digest, run by Podman, `Network=host` with a
  listener on 127.0.0.1:8002 only, read-only, no capability, a 3 GB memory
  cap, and an IP filter to loopback: the engine receives every route's
  positions and reaches nothing. Its configuration is the repository's
  `infra/routing/valhalla.json` (route, trace_attributes and status only),
  never the downloaded bundle's. Serving France measured 593 MiB after long
  routes; Lille to Nice with two alternatives takes 0.25 to 0.36 s and
  answers 4.5 MB (836 KB gzip). On the backend, after Lille to Nice and
  Brest to Strasbourg, the container held 326 MB (200 MB anonymous, 119 MB
  of page cache), next to PostgreSQL's 1.06 GB, with 6.3 GB available
  (2026-10-06). `valhalla_service` ignores SIGTERM, and Podman's init did
  not pass SIGINT on: a stop is a SIGKILL after 2 s (`StopTimeout=2`), so a
  plain `systemctl stop valhalla` leaves the unit failed (137), which a
  restart clears. The candidate unit counts 137 as its normal end.
- `lunaway-routing-refresh` (daily timer): downloads the release's
  `build.json`, stops when that graph serves or is not newer, downloads the
  parts, checks `SHA256SUMS` against the build key
  (`ssh-keygen -Y verify`, `/etc/lunaway/routing-signers`) and every sum,
  refuses a graph built more than 30 days ago, unpacks into
  `/srv/routing/builds/<id>/`, loads the restrictions inactive
  (`lunaway routing load`), serves the new graph on 127.0.0.1:8003
  (`valhalla-candidate.service`) for the route tests, switches `current`
  by an atomic rename, restarts the engine, runs the tests again, then
  activates the restrictions (`lunaway routing activate`). A failure before
  the switch serves nothing new; after it, the previous graph comes back.
  Two graphs stay: the current and the previous. A graph from the future,
  or not newer than the one a rollback refused, is not installed; a run
  that stopped between the switch and the activation is finished by the
  next one. The graph id is the top-level `"id"` of `build.json`, read once
  (a nested or repeated one is refused, and the publish job refuses any
  `build.json` that is not the CLI's flat object). Downloads are capped
  (64 KiB for the first `build.json` and the sums, 1 MiB for the other
  small files, 512 MiB for the restrictions, 2 GiB a part, 8 parts), and
  only the download of the graph being installed stays in `incoming/`, so
  failed runs cannot pile up there.
- Disk: the root disk (local NVMe), not the data volume: the tiles are
  memory-mapped and read at random, and can be rebuilt. Two graphs and a
  download take about 11 GB of the root disk's 70 GB free; the first graph
  takes 3.4 GB (2026-10-06). The first refresh took 2 min 35 s, download
  included, with a 1.5 GB memory peak.
- The engine's unit reaches nothing outside loopback: from inside the
  container, HTTPS to 1.1.1.1 and to github.com fail, while the same image
  started outside the unit reaches 1.1.1.1 (checked 2026-10-06). Its
  journal holds request numbers, times, statuses and sizes, never a
  position.

```bash
sudo systemctl start lunaway-routing-refresh          # now
sudo journalctl -u lunaway-routing-refresh -f
sudo /usr/local/sbin/lunaway-routing-refresh --rollback
```

### The check after each route

`Query.route` validates the request (points in metropolitan France and
Corsica, 5 waypoints, 2 alternatives, 2 500 km in a straight line, the
vehicle's bounds; one route per request), takes one use of the client's
route quota (`LUNAWAY_QUOTA_ROUTE`, 30 every ten minutes, given back when
the server fails), waits at most `LUNAWAY_ROUTING_QUEUE_WAIT_MS` (1 s) for
one of `LUNAWAY_ROUTING_CONCURRENCY` engine slots, held until the answer is
checked, and asks the engine with the vehicle's four dimensions (`auto`
costing, `top_speed` 110 above 3.5 t). Everything a route does fits in
15 s. The
restrictions within 15 m of each route come from one corridor query
(260 ms for Lille to Nice, 15 234 points, 1 472 candidates, on the 266 389
rows of France); a restriction counts when the route follows it (a node on
the line, or a stretch at the same heading), the first and last edge of
each leg included. A limit the vehicle exceeds blocks the route: the engine
is asked again with a 5 m ring excluded at each blocker, three calls at
most; a recalculation that moves a stop more than 30 m, or loses the road
it lies on, ends there. A route with a blocker never reaches the app;
`NO_SAFE_ROUTE` names the blockers. The answer carries the OSRM JSON
Ferrostar reads, typed warnings with their position, and the graph's dates
and IGN edition. Tested end to end on the prepared France graph
(`infra/routing/e2e.sh`, which needs Docker: run it on a build machine,
never on the maintainer's Mac).

## F-Droid repository

Until the official F-Droid carries the app, Lunaway publishes its own
repository, with the `fdroid` flavour (no Google Play Services):

| | |
|---|---|
| address | `https://lunaway.net/fdroid/repo` (before DNS: `https://<backend sslip.io name>/fdroid/repo`) |
| repository key fingerprint (SHA-256) | `EA3EC0CA3EF97A4F9E31552D38751AEACCE202A2D15CD5FBB318F20EDE910D2B` |
| link for a phone | `https://lunaway.net/fdroid/repo?fingerprint=EA3EC0CA3EF97A4F9E31552D38751AEACCE202A2D15CD5FBB318F20EDE910D2B` |
| QR code of that link | `infra/web/site/img/fdroid-repo-qr.png` |
| APK signing certificate (SHA-256) | `263ecb714e07eb251edf933331deda6682367eec2569ab042160c5073484969b` |

The page `https://lunaway.net/fdroid/` explains it; on lunaway.net,
`/fdroid/repo` and `/fdroid/repo/` lead there (a browser opens the link of a
phone without F-Droid).

### Keys

Two RSA 4096 keys, valid 10,000 days, created on 2026-10-06 by
`infra/fdroid/keys.sh create`, in `~/.config/lunaway/fdroid/` on the Mac
(0700, files 0600), with their passwords in `passwords.env` (PKCS12: one
password per store):

| key | alias | signs | if lost |
|---|---|---|---|
| `repo-keystore.p12` | `lunaway-repo` | the index (`entry.jar`, `index-v1.jar`) | a new repository fingerprint: users remove the repository and add it again |
| `app-keystore.p12` | `lunaway-fdroid` | the APK | Android refuses any update signed by another key: every user reinstalls, and loses what the app keeps on the device only |

The APK key serves F-Droid only; the Play upload key is not reused. Play App Signing
re-signs Play installs with Google's key, so reusing the upload key would
not let a Play install take an F-Droid update anyway (`docs/play-store.md`);
the upload key can be reset through Play Console, an APK key cannot; the
upload key lives in `key.properties`, which no script or agent reads. A key
used only for F-Droid also stays usable for a reproducible build in the
official F-Droid (below).

`infra/fdroid/keys.sh backup` encrypts the three files with age to
`LUNAWAY_BACKUP_RECIPIENT` on the Mac, checks that the copy opens with
`~/.config/lunaway/backup-age.key` and lists the three files, and writes it
as `fdroid-keys-<stamp>.tar.age` at the top of the backend's
`/srv/data/backups/offsite/`. The ops server pulls it at 01:15 UTC, the Mac
at 04:30, and neither prunes it (they prune the dumps by name). Not in a
subdirectory: the ops server's pull cannot copy a setgid directory
(`RestrictSUIDSGID` of `lunaway-replica.service`; a `keys/` directory made
it fail on 2026-10-06 until removed). The first copy,
`fdroid-keys-20261006T123732Z.tar.age`, is on the backend and the ops
server with the same SHA-256, and the Mac's pull key lists it. The age
identity must have its offline copy (see "Private settings"): without it,
no copy opens. Restore:

```bash
age --decrypt --identity ~/.config/lunaway/backup-age.key ~/Backups/lunaway/fdroid-keys-<stamp>.tar.age \
  | tar -x -C ~/.config/lunaway
chmod 0700 ~/.config/lunaway/fdroid; chmod 0600 ~/.config/lunaway/fdroid/*
infra/fdroid/keys.sh show     # the two fingerprints above
```

### Publishing a version

Build the `fdroid` flavour from a committed revision, not the working tree,
then publish:

```bash
mkdir -p data/tmp/fdroid/src
git archive <tag> .fvmrc app | tar -x -C data/tmp/fdroid/src
(cd data/tmp/fdroid/src/app && JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home \
  fvm flutter build apk --release --flavor fdroid)
LUNAWAY_FDROID_REV=<tag> infra/fdroid/publish.sh \
  data/tmp/fdroid/src/app/build/app/outputs/apk/fdroid/release/app-fdroid-release-unsigned.apk
rm -r data/tmp/fdroid/src
```

`publish.sh` checks the APK (package; the `fdroid` flavour, by the
`legal.p2p.lunaway.DISTRIBUTION` meta-data of its manifest, or by a
versionName ending in `-fdroid` for the builds made before that marker; no
Play Services class with `app/tool/android/check_gms.py`, native libraries
aligned on 16 KB), signs it with the APK key (`apksigner
--alignment-preserved`, schemes v2 and v3 for minSdk 24), refuses a
versionCode already published with other bytes, fetches the APKs already
on the server, writes the metadata (`infra/fdroid/legal.p2p.lunaway.yml`,
and the listing of `fastlane/metadata/android/` at `LUNAWAY_FDROID_REV`,
`HEAD` by default), checks that every APK the index will list, the ones
fetched back from the server included, is signed by the APK key and no
other (the metadata's `AllowedAPKSigningKeys` makes `fdroid update` drop
any other too), runs `fdroid update` (fdroidserver 2.4.5 in
`~/.cache/lunaway/fdroidserver-2.4.5`, Python 3.12, installed by `uv pip
sync --require-hashes` from `infra/fdroid/requirements.txt`; the JDK of
Homebrew's openjdk@21 and the Android SDK's build tools), checks that both
index files verify and are signed by the repository key, uploads the
repository into `/home/ops/fdroid-staging` (rsync, only what changed), and
`infra/server/install-fdroid.sh` copies it into
`/srv/lunaway/releases/fdroid/<stamp>-<versionCode>/`, turns every APK
identical to the previous release's into a hard link to it (two releases
of the same APK took 98 MB, not 194), and switches the `/srv/lunaway/fdroid`
symlink. It then reads the index files and the APK
back over HTTPS and compares them with the local ones. Older versions move
to the archive section (`archive_older: 3`). `fdroid update`'s run reports
(`repo/status/`) and its browser page (`index.html`, its stylesheet and QR
code) are never uploaded. The working copy, `~/.local/share/lunaway/fdroid`
(`LUNAWAY_FDROID_DIR`), can be deleted: the server's copy is the reference.

Caddy serves `/fdroid/repo/` and `/fdroid/archive/` from
`/srv/lunaway/fdroid` on lunaway.net and on the sslip.io name (the
`fdroid_repo` snippet): GET and HEAD only, a sandbox CSP, the index files
revalidated on every read, an APK cached a day. Old releases stay until
removed by name.

First publication, 2026-10-06: Lunaway 0.1.0-fdroid, versionCode 1, built
from `main` at 69f9c98, a universal APK of 100,563,315 bytes (arm64-v8a,
armeabi-v7a, x86_64; minSdk 24, targetSdk 36; 0 Play Services class; every
64-bit library aligned on 16 KB), served by release `20261006T130528Z-1`.
An APK signed by another key, put in the archive of a test working copy,
stopped the publication before anything was uploaded. Checked from the Mac with fdroidserver's own client code
(`index.download_repo_index_v2`, `data/tmp/fdroid/client-check.py`): the
index downloaded through the sslip.io name verifies against the
fingerprint, a wrong fingerprint is refused, and the APK it lists has the
SHA-256 and size of the index and the APK key's certificate. The build
points at `api.lunaway.net` and `tiles.lunaway.net`: it works once DNS
exists.

The index v2 carries no "what's new" text: fdroidserver puts the changelog
there only for apps with build recipes; index v1 has it.

### Official F-Droid

`infra/fdroid/fdroiddata/metadata/legal.p2p.lunaway.yml` is the draft for
fdroiddata: the metadata above, the anti-feature `TetheredNet` (places,
reviews and routes come from api.lunaway.net, whose address is fixed at
build time), and a build of the `fdroid` flavour from the source with the
Flutter srclib at 3.47.6, NDK 28.2.13676358 (Flutter's, which compiles the
vendored SQLite amalgamation through the sqlite3 build hook, `hooks:` in
`app/pubspec.yaml`), JDK 21, the prebuilt web files (`sqlite3.wasm`,
`drift_worker.js`) and the iOS, macOS and Windows trees removed, and the
pub cache scanned then deleted. It passes `fdroid lint` against
fdroiddata's own category and anti-feature lists and is unchanged by
`fdroid rewritemeta` (fdroidserver 2.4.5, 2026-10-06). The recipe was not
built on F-Droid's build server. For the maintainer:

1. Tag the release (`v0.1.0` in the draft) and check that
   `app/pubspec.yaml` gives the draft's `versionCode`.
2. F-Droid refuses an APK whose versionName differs from the recipe's,
   and its automatic updates take the version from `pubspec.yaml`. Since
   the app's pass 4 the `fdroid` flavour keeps that versionName as it is
   (no `-fdroid` suffix; the flavour is told apart by the
   `legal.p2p.lunaway.DISTRIBUTION` meta-data of its manifest), so the
   draft can say `AutoUpdateMode: Version` with `versionName` and
   `CurrentVersion` written without the suffix.
3. Fork `gitlab.com/fdroid/fdroiddata`, add the file under `metadata/`, run
   `fdroid build -v -l legal.p2p.lunaway` in F-Droid's build container to
   prove the recipe, then open the merge request (template "App
   inclusion").
4. Optional, reproducible builds: attach the APK signed here to the GitHub
   release and add `Binaries:` (its URL pattern) and
   `AllowedAPKSigningKeys: 263ecb714e07eb251edf933331deda6682367eec2569ab042160c5073484969b`.
   When F-Droid's build equals ours apart from the signature, F-Droid
   distributes ours, and installs from this repository update from F-Droid
   with no reinstall. Otherwise F-Droid signs with its own key and a user
   moving from this repository to F-Droid reinstalls.

## Road events

Closures, works and temporary limits from the feeds of
`docs/data-sources.md` ("Road events"), checked with every route
(`docs/architecture.md`, "Road events"). Installed on 2026-10-06 by the
backend step `pipeline` (the two units and timers below) and the step
`routing` (the engine's limits).

- `lunaway-road-events.service` and `.timer` (`infra/systemd/`): `lunaway
  road-events poll` every three minutes as `lunaway-ingest`, with
  `LUNAWAY_VALHALLA_URL=http://127.0.0.1:8002` for the matching. A run
  with nothing due takes under a second; the hourly reads add about ten
  seconds (2026-10-06, Mac, debug build: the DIR aggregate read in 135
  ms, DiaLog's 7.9 MB in 208 ms, a forced read of every feed in 18 s, most
  of it the quarter-second pace between DIR increments). The unit fails
  when a feed failed, after the others ran. A feed that fails is asked
  again at its own pace (DiaLog 15 minutes, the cities hourly, the DIR
  aggregate after 15 minutes), never at every run. First pass on the
  backend (2026-10-06, 14:10 UTC): 84 s, 33 MiB of anonymous memory at
  the peak; the DIR aggregate and 36 increments (616 events), DiaLog 439,
  Toulouse 790, Lyon 354, Charente-Maritime 120, Paris 93 and 115.
- Quotas: `LUNAWAY_QUOTA_ROAD_REPORT` (per account, 30 a day) and
  `LUNAWAY_QUOTA_ROAD_REPORT_CLIENT` (per client address, 100 a day).
- `lunaway-road-events-dialog.service` and `.timer`: DiaLog's permanent
  orders weekly into `route_restrictions` (source `dialog`, outside any
  graph): 6 008 orders, 17 594 restriction lines in 15 s (2026-10-06,
  on the backend, 86 MiB of anonymous memory at the peak).
- The engine's limits on excluded polygons are raised in
  `infra/routing/valhalla.json` (`max_exclude_polygons_vertices` 100 to
  2 000, `max_exclude_polygons_length` 20 000 to 50 000 m): a route around
  closures sends up to 200 rings of 9 points (`routing::MAX_EXCLUSIONS`),
  where 100 vertices allowed 11 and the engine refused the whole request
  beyond. A test of the API reads the file and fails if the two drift
  apart. Each graph serves the copy of the file put next to it at its
  install; `infra/configure.sh backend routing` brings a changed file to
  the graphs on disk and restarts the engine.
- Matching on the engine: each pass matches the events waiting until the
  engine refuses one, then stops for that pass. On 2026-10-06 every pass
  stopped on such a refusal (`400::Insufficient number of locations
  provided`, `500::leg_shape_index not set for intermediate location`)
  after 6 to 179 matches; `infra/verify.sh backend` counts the refusals of
  the last hour.
- Freshness: `{ roadEventSources { id ageSeconds dataAt fresh } }` is
  public; the DIR is listed first, DiaLog second. `ageSeconds` counts from the last read
  that succeeded, news or not: the poller is alive. `fresh` counts from
  `dataAt`, when the data was last current: a publisher that stops makes
  its events warn instead of block. The status page alerts when the DIR
  has not been read for 15 minutes (`infra/ops/gatus/config.yaml`, with
DiaLog read in the last 45 minutes and the feed answering a page):

```yaml
  - name: Road events (DIR feed read)
    group: public
    url: "https://__API_HOST__/graphql"
    method: POST
    graphql: true
    headers:
      Content-Type: application/json
    body: "{ roadEventSources { id ageSeconds } }"
    interval: 5m
    conditions:
      - "[STATUS] == 200"
      - "[BODY].data.roadEventSources[0].id == dir"
      - "[BODY].data.roadEventSources[0].ageSeconds < 900"
```

```bash
sudo systemctl start lunaway-road-events            # one pass now
sudo lunaway-admin road-events stats                 # placement by source and class
sudo lunaway-admin road-events poll --force --only dir
```

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
| PostgreSQL | localhost only, SCRAM, a DDL owner and two row roles (API, imports) with timeouts and no default privileges: the migrations grant each table to the role that needs it, and `test-grants.sh` checks the exact list in production; the statistics views closed to them; connection caps under `max_connections` (API 25, imports 15, owner 5); data checksums, builtin C.UTF-8 collation (no glibc collation drift), slow-query log without bound values; passwords set with statement tracking and statement logging off |
| PostgreSQL | systemd sandbox over Debian's unit: runs as `postgres` with no capabilities, read-only system except its data, socket and log directories, syscall filter, W^X memory, loopback-only network |
| web | Caddy: automatic TLS from Let's Encrypt, HTTP/3, HSTS, strict CSP, `nosniff`, `no-referrer`, frame denial, request bodies of 64 KiB on `/graphql` (read whole before the API sees them), 10304 KiB on `/upload` (POST and OPTIONS only) and 1 MB elsewhere, header (10 s) and body (3 min) read timeouts, admin API on a private unix socket; access log and Caddy's own log with IPv4 truncated to /16 and IPv6 to /32, no port, no query string, no tile coordinates, photo paths as `/media/[photo]`, kept 14 days |
| API | systemd sandbox: static user `lunaway-api`, no capabilities, read-only system, of `/srv` only `/srv/data/media` visible and writable, private /tmp and devices, syscall filter, W^X memory, loopback-only network (no outbound request), may bind only 8484, memory capped at 1.5 GB; CORS for `https://lunaway.net` only; `lunaway-admin` runs the moderation and account commands under the same user, role and limits |
| conflation worker | the imports' sandbox under `lunaway-ingest`, loopback only, restarted 15 s after a failure, stopped after 10 starts in 15 minutes (the status page then shows it); its queues measured every minute as `postgres` into a world-readable file of counts and ages |
| photo backups | one age-encrypted file per photo, to the key that exists only on the Mac; the job runs as root without capabilities; deleted photos leave every copy within 29 days of their deletion, whenever the ops server and the Mac run; a run that would remove more than 50 copies and 5% of them refuses, on the backend and on the Mac |
| imports | the same sandbox under a static user, outbound connections allowed except to private and link-local ranges (the private network, the metadata service), writes only to `/srv/data/ingest`, memory capped at 2 GB |
| status page | Gatus under its own user with the same sandbox, listening on loopback; Caddy in front refuses anything but GET and HEAD |
| routing | Valhalla under Podman, loopback only (8002, 8003 for a graph under test), read-only, no capability, an IP filter to loopback, only the route, trace_attributes and status actions, its configuration from the repository; the API refuses an engine URL that is not loopback, and calls it with no proxy and no redirect, bounded in time, answer size, calls in flight and routes per client; the graph is built off the server, pulled over HTTPS, accepted only with a signature of the build key, newer than the one served and less than 30 days old, unpacked by fixed names, and tested before and after the switch |
| basemap | pmtiles under a dynamic user with the API's sandbox, loopback only (8485), the tile volume read-only and nothing else under `/srv`; its refresh as `lunaway-tiles`, writing only the archives, links and TileJSON, outbound HTTPS except to private ranges; the offline packs built as `lunaway-tiles` with no network at all, writing only `/srv/tiles/packs`; go-pmtiles and the fonts pinned by hash; Caddy accepts GET, HEAD and OPTIONS only on the tile routes, at most 64 requests to pmtiles at once; tile coordinates, byte ranges and pack names never logged |
| F-Droid repository | the index signed by a key, and the APK by another, that exist only on the Mac (age-encrypted copies in the backup chain); fdroidserver pinned with hashes; served as static files, GET and HEAD only, sandbox CSP; fdroidserver's run reports never published |
