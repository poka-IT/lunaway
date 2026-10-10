# Deploying the backend

Lunaway runs on three Hetzner Cloud servers in their own Hetzner project,
built and kept by the scripts in `infra/`, plus one nightly job on the
maintainer's Mac. The third, the geocoding server, serves the addresses of
the map's search to the backend alone (see "Geocoding"). Everything is idempotent: running a script again changes
only what differs from the files in the repository.

```
 internet
   │ Hetzner Cloud Firewalls: 22 from admin sources; 80, 443 tcp+udp, ICMP
   ▼
 lunaway-backend-1, fsn1 (10.42.0.2)           lunaway-sync-1, nbg1 (10.42.0.3), role "ops"
   nftables, fail2ban                            nftables, fail2ban
   Caddy :80 :443 ── 127.0.0.1:8484 lunaway-api  Caddy :80 :443 ── 127.0.0.1:8080 Gatus
     /upload ── lunaway-api, writes the photos     public status page, checks from outside
     /external-photos/ ── lunaway-api, a partner's photo on first view
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
                    commands, from 10.42.0.3 only ─ the feed producer's erasures key: the erased
                                                    authors' hashes (/srv/data/extcom-erasures)
   extcom-drop ◄─── SSH over lunaway-net ───────── the external community feed's producer:
                    rrsync -wo into /srv/data/extcom-inbox, from 10.42.0.3 only

 maintainer's Mac, 04:30 local ── SSH, rrsync -ro ──► ops replica ──► ~/Backups/lunaway, 29 days
                                ── HTTPS ───────────► status page API
                                ── gh ──────────────► GitHub issue "ops: alerte"
 maintainer's Mac, Sundays 03:00 ── hcloud ─────────► throwaway build server (ccx33, purpose=routing-build)
                                ◄── SSH, pinned ──── Europe routing graph bundle
                                ── gh, signed ──────► release `routing-graph` ◄── backend, daily refresh

 lunaway-backend-1 Caddy 127.0.0.1:8486 ── lunaway-net ──► lunaway-geocode-1, fsn1 (10.42.0.4), role "geocode"
   (the API's searches                                    photon@europe :2322, photon@morocco :2323
    and translations)                                     lunaway-translate :2324 (OPUS-MT on CTranslate2)
                       ── HTTPS ──► data.geopf.fr          monthly refresh from download1.graphhopper.com
```

The backend never connects to the ops server. Lunaway ingests open data,
and one source under a written licence whose feed its producer drops on
the backend (`.claude/rules/data-sources.md`, "The external community
feed" below); the imports run on the backend.

## Files

| path | runs | role |
|---|---|---|
| `infra/lib.sh` | here | roles, names, private IPs; reads `~/.config/lunaway/env` |
| `infra/provision.sh` | here | admin key, private network, then per role: firewall, server, primary IPs, volume |
| `infra/cloud-init.yaml` | first boot | admin account, SSH policy, nftables, fail2ban, sysctl, automatic updates |
| `infra/configure.sh` | here | copies `infra/` to a server, runs `infra/server/setup.sh` for its role, reboots if an update asks |
| `infra/server/*.sh` | server, root | backend steps `harden data-volume postgres caddy tiles backups api pipeline routing ops-access`, ops steps `harden data-volume ops-replica ops-status`, geocoding steps `harden geocode translate`, and the test and release helpers |
| `infra/deploy-api.sh` | here | builds a commit in a container (`infra/build/build-api.sh`), uploads the API and the CLI, migrates, switches the release, checks |
| `infra/server/pause-jobs.sh` | backend | installed by `install-release.sh` as `/usr/local/sbin/lunaway-pause-jobs`: the long jobs of the CLI stopped between two transactions while a migration runs, then let go on (see "Deploying the API"); `infra/tests/pause-jobs.py` checks it against fakes |
| `infra/build/remote-build.sh` | here | with `LUNAWAY_BUILDER=hetzner`, the same build on a throwaway Hetzner server, deleted at the end |
| `infra/deploy-gatus.sh` | here | copies the pinned Gatus binary out of its official image and installs it on the ops server |
| `infra/deploy-web.sh` | here | deploys the landing site or the Flutter web build as a new release |
| `infra/deploy-basemap-assets.sh` | here | deploys map styles or a sprite set to the basemap host |
| `infra/files/usr/local/sbin/lunaway-admin` | backend | the CLI by hand, as the API or as the imports (see "Data pipeline") |
| `infra/files/etc/nftables.d/lunaway-api-egress.nft` | backend | the API's user may open HTTPS and DNS connections only, besides the loopback (installed by the `api` step once the user exists) |
| `infra/files/usr/local/sbin/lunaway-extcom-inbox` | backend | takes the newest feed of the external community source from its inbox, checks its SHA-256 and imports it (see "The external community feed"); `infra/tests/extcom-inbox.sh` checks it against a scratch inbox |
| `infra/files/usr/local/sbin/lunaway-extcom-erasures` | backend | the forced command of the feed producer's erasures key on `lunaway-pull`: prints the list of the source's erased authors (see "The external community feed"); `infra/tests/extcom-erasures.sh` checks it against a scratch list |
| `infra/files/usr/local/sbin/lunaway-unit-result` | backend | run by a unit's `ExecStopPost=`, keeps how its last finished run ended in `/var/lib/lunaway-unit-result/<name>.result` (root 0755, made by the `pipeline` step; the script writes nowhere else) for the health probe; `infra/tests/unit-result.sh` checks it |
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
| `infra/ops/mac-routing/` | the Mac | the weekly routing graph build: `lunaway-routing-build.sh` (a throwaway Hetzner build server, the bundle signed and published), its two launchd plists (the Sunday build, the hourly sweep) and `install.sh`; see "Routing" |
| `infra/web/site/` | backend | the website, generated by `tool/site/build.py` from `tool/site/src/` (French at `/`, English under `/en/`); `infra/web/app/` is the web app's fallback page |
| `infra/tests/caddy-layout.sh` | here | runs `infra/caddy/` in the servers' Caddy release (native binaries on macOS and Linux x86_64, the Docker images with `LUNAWAY_CADDY_DOCKER=1`), the tile routes against a real `pmtiles serve`, and checks every route, header and the log masking |
| `infra/geocode/` | geocoding server | Photon's pins (`version.sh`), its unit (`photon@.service`, one instance per database), and the monthly refresh of the databases (`lunaway-photon-refresh` and its unit and timer); installed by the step `geocode`; see "Geocoding" |
| `infra/translate/` | geocoding server | the translation server (`lunaway-translate.py`, its unit `lunaway-translate.service`), its Python packages pinned with their hashes (`requirements.in`, compiled into `requirements.txt`), its models (`models.txt`: each OPUS-MT archive and its SHA-256) and their installer (`lunaway-translate-models` and its unit); installed by the step `translate`; see "Translation". `infra/tests/translate-server.py` checks the server without its models |
| `infra/caddy/geocoders.caddy` | backend | the API's way to the geocoders and to the translation server on the loopback (127.0.0.1:8486), installed in `/etc/caddy/sites-enabled/` with or without the domain |
| `infra/routing/` | build server, backend | the routing engine: its pins (`version.sh`), the graph build (`europe-build.sh` and `europe-extracts.txt` on the build server, `build-graph.sh`, `valhalla-build.sh`, `osmium.Dockerfile`, `test-routes.json`), its measurement (`measure-build.sh`, `measure-remote.sh`), and on the backend the engine's units (`valhalla.container`, `valhalla-candidate.container`), its configuration (`valhalla.json`) and the graph refresh (`lunaway-routing-refresh` and its unit and timer) and the public half of the build key (`routing-signers`); installed by the backend step `routing`; see "Routing" |

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
| `LUNAWAY_API_HOST`, `LUNAWAY_TILES_URL`, `LUNAWAY_WEB_URL`, `LUNAWAY_STATUS_DOMAIN`, `LUNAWAY_MEDIA_BASE_URL` | optional: the public names, `api.lunaway.net`, `https://tiles.lunaway.net`, `https://lunaway.net`, `status.lunaway.net` and `https://api.lunaway.net/media/` unless set (`infra/lib.sh`; see "The domain") |
| `LUNAWAY_BACKEND_*`, `LUNAWAY_OPS_*` | addresses, volume ids (the backend's tile volume in `LUNAWAY_BACKEND_TILES_VOLUME_ID`), types, written by `provision.sh` |

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
| the DATAtourisme key (`LUNAWAY_DATATOURISME_KEY`) | backend, `/etc/lunaway/datatourisme.env` (root, 0600), given by the maintainer (a free key, `docs/data-sources.md`) and copied without being shown: `{ printf 'LUNAWAY_DATATOURISME_KEY='; cat ~/.config/lunaway/datatourisme.key; } \| ssh -F ~/.config/lunaway/ssh_config lunaway 'sudo install -m 0600 -o root -g root /dev/stdin /etc/lunaway/datatourisme.env'`; loaded by `lunaway-ingest-datatourisme.service` alone; an age-encrypted copy, `datatourisme-key.env.age`, in the backup chain, made once by the `pipeline` step and never overwritten. To restore it: `age --decrypt --identity ~/.config/lunaway/backup-age.key ~/Backups/lunaway/datatourisme-key.env.age \| ssh -F ~/.config/lunaway/ssh_config lunaway 'sudo install -m 0600 -o root -g root /dev/stdin /etc/lunaway/datatourisme.env'` |
| the external community source's settings (`LUNAWAY_EXTCOM_AGREEMENT_REF`, `LUNAWAY_EXTCOM_PHOTO_HOSTS`, `docs/feeds.md`) | backend, `/etc/lunaway/extcom.env` (root, 0600), and nowhere in the repository: a photo host names the partner. Given by the maintainer and installed without being shown: `printf 'LUNAWAY_EXTCOM_AGREEMENT_REF=%s\nLUNAWAY_EXTCOM_PHOTO_HOSTS=%s\n' "$ref" "$hosts" \| ssh -F ~/.config/lunaway/ssh_config lunaway 'sudo install -m 0600 -o root -g root /dev/stdin /etc/lunaway/extcom.env'`, then `infra/configure.sh backend pipeline`, which turns the feed's import on. Loaded by `lunaway-ingest-extcom.service` and `lunaway-admin ingest extcom` alone (the API reads the hosts of the agreement in force from the database, where each import writes them). An age-encrypted copy, `extcom-env.age`, in the backup chain, encrypted again by the `pipeline` step whenever the file is newer than it. To restore it: `age --decrypt --identity ~/.config/lunaway/backup-age.key ~/Backups/lunaway/extcom-env.age \| ssh -F ~/.config/lunaway/ssh_config lunaway 'sudo install -m 0600 -o root -g root /dev/stdin /etc/lunaway/extcom.env'` |
| the takedown secret (`LUNAWAY_TAKEDOWN_SECRET`) | backend, `/etc/lunaway/takedown.env` (root, 0600), loaded only by the conflation units (`lunaway-conflate-worker`, `lunaway-conflate`) and `lunaway-admin conflate|takedowns|take-down|replay-takedowns` (the import role without outbound network), never by the imports nor the API; an age-encrypted copy, `takedown-secret.env.age`, in the backup chain. Generated once by the `pipeline` step and never changed: the cells stored around every place taken down are keyed with it, and the step refuses to generate another while the copy exists (see "Backups and restore") |
| the danger zones' secret (`LUNAWAY_ZONE_SECRET`) | backend, `/etc/lunaway/zone.env` (root, 0600), read only by the speed camera builds (`lunaway-enforcement*.service`, `lunaway-admin enforcement`); an age-encrypted copy, `zone-secret.env.age`, in the backup chain. Generated once by the `pipeline` step and never changed: a new secret moves every zone the phones keep (see "Backups and restore") |
| the probe and replica keys | ops server, `/etc/lunaway-ops/probe_ed25519` (root) and `replica_ed25519` (lunaway-backup), 0600; Gatus's configuration carries the probe key inline (`/etc/gatus/config.yaml`, root:gatus 0640) |
| the external community feed producer's keys | ops server, made and kept by its private deployment (the push key for `extcom-drop`, the erasures key for `lunaway-pull`); the erasures key's public half sits in `/etc/lunaway-ops/extcom-erasures_ed25519.pub`, where `infra/configure.sh backend` reads it |
| the age identity that decrypts every dump | the Mac only, `~/.config/lunaway/backup-age.key` (0600); keep an offline copy (a password manager): without it no backup can be read |
| the Mac's pull key | the Mac, `~/.config/lunaway/ops-pull_ed25519` (0600) |
| the F-Droid repository key, the F-Droid APK key and their passwords | the Mac, `~/.config/lunaway/fdroid/` (0700, files 0600), and an age-encrypted copy in the backup chain (see "F-Droid repository") |
| the routing graph's signing key | the Mac, `~/.config/lunaway/routing-signing_ed25519` (0600), and an age-encrypted copy in the backup chain, `routing-signing-key-<stamp>.age` (see "Routing") |
| the Hetzner API token | the Mac only, in the hcloud context of the project (`~/.config/hcloud/cli.toml`); never on a server, never on GitHub |

## First installation

```bash
infra/ops/mac/install.sh keys   # the age identity and the pull key, on the Mac
infra/provision.sh              # both servers, the network, the volumes; waits for cloud-init
infra/configure.sh ops          # first: generates the probe and replica keys, pins the backend's host key
infra/configure.sh backend      # every backend step; lunaway-pull takes the ops server's keys;
                                # the tiles step starts the first planet download and its checks (about 45 minutes)
infra/enable-domain.sh          # the lunaway.net sites, once their DNS records point at the backend
infra/deploy-api.sh             # builds HEAD, migrates, deploys, checks https://api.lunaway.net
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
| `lunaway-backend-1` | cx43, 8 vCPU, 16 GB, 160 GB NVMe, fsn1 | the API, PostgreSQL, the imports, and the Europe routing engine (6 GB cap, two graphs of 20.4 GB on the root disk; see "Routing") | 15.99 |
| its daily backups | 20% of the server | images of the root disk, which carry a copy of the latest dumps | 3.20 |
| `lunaway-data` | volume, 150 GB | database, dumps, import cache, photos (budget below) | 8.58 |
| `lunaway-tiles` | volume, 350 GB | the basemap: two planet archives at the peak of a refresh, and two sets of offline packs (see "Basemap") | 20.02 |
| `lunaway-sync-1` (role ops) | cx23, 2 vCPU, 4 GB, 40 GB, nbg1 | Gatus and Caddy, a nightly rsync | 5.49 |
| `lunaway-sync-data` | volume, 20 GB | the dump replica | 1.14 |
| `lunaway-geocode-1` (role geocode) | cx43, 8 vCPU, 16 GB, 160 GB NVMe, fsn1 | Photon over Europe and Morocco, two copies of the Europe database during a refresh (see "Geocoding"), and the translation server (see "Translation") | 15.99 |
| 3 primary IPv4 | | mobile networks and campsite Wi-Fi without IPv6; the geocoding server's, for GraphHopper and GitHub, which answer over IPv4 only | 1.50 |
| `lunaway-net`, primary IPv6 | | | 0 |

`provision.sh` tries types in order of value and keeps the first one the API
accepts: for the backend `cx43` (8 vCPU, 16 GB, 15.99), `cax31`, then `cx33`;
for the ops server `cax11`, then `cx23`. On 2026-10-06 the API refused `cx43`
in nbg1 and fsn1 (out of stock) and every ARM type in both German sites, so
the backend runs on `cx33`. The type list's `available` flag is not a
reliable stock signal: on the same day it said `cx43` was unavailable
everywhere, and the API had still created one in nbg1 an hour earlier.

The backend moved from `cx33` to `cx43` in place on 2026-10-06 at 22:58
UTC, for the Europe routing graph (plan/research/35-routage-europe-prod.md):
`hcloud server shutdown`, `hcloud server change-type lunaway-backend-1 cx43`
(hcloud 1.67 grows the disk to 160 GB unless `--keep-disk`; the root
filesystem grew to 150 GB by itself at boot), `hcloud server poweron`, then
`infra/configure.sh backend postgres routing` (PostgreSQL retuned to
`shared_buffers` 3905 MB, the engine's cap raised to 6 GB). `/health` answered
again 2 min 17 s after the shutdown (22:58:09 to 23:00:26 UTC). A fresh dump was taken and pulled to the
ops server and the Mac before.

### The data volume

| content | size |
|---|---|
| PostgreSQL with France (about 15,600 places from 19,500 records on the development database, 2026-10-05) | well under a GB now; Europe later, a few GB |
| the OpenStreetMap France extract in the import cache (`/srv/data/ingest`) | 5.9 GB (5,867,462,742 bytes on 2026-10-05); during the daily refresh the old file stays until the new one is complete, so 12 GB at the peak |
| 7 nightly dumps and their 7 encrypted copies | 351 MB a dump with Europe (2026-10-07), so about 4.9 GB |
| community photos (`/srv/data/media`) | to size when the feature is designed |
| open content photos (`/srv/data/media/external`) | a photo's two WebP files (1 280 and 512 pixels) took 262 KB from Commons and 203 KB from Panoramax on average on 2026-10-10 (784 and 73 photos of points of France). The points add up to about 1.4 GB a week from Commons (2 000 points, 2.6 photos a point) until each has been asked once: about 16 GB for the 22 861 points of France that name a Commons file or a Wikidata item |

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
never touched.

The long jobs of the CLI wait while the migrations run
(`infra/server/pause-jobs.sh`, uploaded with the release and installed as
`/usr/local/sbin/lunaway-pause-jobs`): a migration that alters a table
waits for every transaction that read or wrote it and gives up after its
`lock_timeout`, which a deploy met on 2026-10-08 behind a query of the
open content's refresh. When the release carries a migration not applied
yet (`lunaway migrate --list` against `_sqlx_migrations`), each running
unit whose processes run the CLI of a release (the API and the migrations
aside) is stopped with `SIGSTOP` once none of its sessions is inside a
transaction, read in `pg_stat_activity` by the name the CLI gives its
sessions (`lunaway:<unit>`, from its cgroup), and checked again once
stopped; a job none of whose sessions carries that name (a CLI from
before the names) runs on. Then no other session may keep a transaction
open for more than 5 s or stay idle inside one, `current` moves to the
release, the migrations run, and `SIGCONT` lets every job go on in the
same process where it stood. A pause not reached within
`LUNAWAY_PAUSE_WAIT` (300 s), an error or an interruption lets the jobs
go on and fails the deploy before any migration; a transient timer
(`lunaway-resume-jobs`) resumes them after `LUNAWAY_PAUSE_MAX` (1 800 s)
should the deploy die meanwhile, and the next pause resumes them first.
A release without a pending migration pauses nothing, so a nightly dump
in progress does not hold it back. `sudo lunaway-pause-jobs status`
lists the jobs paused and the transactions that hold a pause back;
`sudo lunaway-pause-jobs resume` lets them go. A unit started during the
migrations is not paused. `infra/tests/pause-jobs.py` checks the script
against fakes (`tool/check.sh` runs it). Then the API restarts, and `current` goes back to the
previous release when `/health` does not answer within 20 seconds. Applied
migrations stay after such a rollback: they are additive
(`.claude/rules/sqlx.md`), so the previous API runs on the newer schema. Old
releases stay until removed by name.

The API refuses to start when it cannot write the account deletion journal
(`LUNAWAY_DELETION_JOURNAL=/srv/data/account-deletions`, in
`/etc/lunaway/media.env`; see "Backups and restore"). Servers configured
before the journal existed take, before the first deploy of a release that
has it, `infra/configure.sh ops ops-replica` (the replica's directory for
the journal's copy, setgid so the Mac's pull can read it), then
`infra/configure.sh backend backups api` (the directory, the unit's access
to it, the variable and the hourly encrypted copy). Without the backend
step the new release fails its `/health` check and `current` goes back.

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

The project's quotas can stop the builder's creation while throwaway
servers run: `Primary IP limit exceeded` (ten addresses, IPv4 and IPv6
together) or `shared core limit exceeded`, both met on 2026-10-07.
`LUNAWAY_BUILDER_IPV6=1` creates it without an IPv4 address (Docker Hub,
Debian and crates.io answer over IPv6; this machine must too, and the build
container then uses the builder's network, Podman's bridge having no
IPv6), and `LUNAWAY_BUILDER_TYPE=ccx23` takes dedicated vCPUs, which count
apart (0.1378 EUR excl. VAT an hour in fsn1; the build of 7565bb6 took 5 min 20 s on
it). An address is still needed: when all ten are taken, a server must go
first.

## Photos

The API takes a photo on `POST /upload` (`multipart/form-data`, a place and
an image, a session of trust level 1), rewrites it as two WebP files without
any metadata (2048 px and 512 px) and writes them under
`/srv/data/media/photos/<2 hex>/<2 hex>/<SHA-256>.webp`; Caddy serves them
under `/media/` with a year of cache.

- Caddy routes `/upload` to the API on `api.lunaway.net`: `POST`, and `OPTIONS` for the web app's preflight,
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
- Every answer must reach its client within 3 minutes of the request plus
  one second per 32 KiB already sent (`write_idle 3m 32768`): the API holds
  a whole answer (a route reaches 12 MB) until Caddy has passed it on, and
  Caddy's default only cuts a write stalled for a minute, so a client
  reading a few KB a second held it for an hour. 3 minutes covers an
  upload's 120 s before the API answers; past it 256 kbit/s still receives
  anything, and a slower offline pack download is cut and resumes by
  range (measured on 2026-10-07: a pack read at 16 KiB/s cut after 486 s
  over HTTP/1.1, 513 s over HTTP/2, 416 s over HTTP/3). Server-wide
  because the per-route `timeouts` handler of Caddy 2.11.7 has no effect:
  the server's own writer, on by default, arms the connection's deadline
  again on each write. `infra/tests/caddy-layout.sh` checks the bound with
  shorter values.
- The API runs as the static user `lunaway-api`, which owns
  `/srv/data/media` (0755, files 0644 for Caddy). Its unit sees nothing else
  of `/srv` and may write only there. `/etc/lunaway/media.env` gives it
  `LUNAWAY_MEDIA_DIR` and `LUNAWAY_MEDIA_BASE_URL`, rendered by
  `infra/server/api.sh` from `LUNAWAY_MEDIA_BASE_URL` (configure.sh). URLs
  are built at each answer from the stored paths, so changing the base later
  changes every URL at once.
- Two photo decodes at once take up to about 1 GB: the API's memory cap is
  1.5 GB (`MemoryHigh` 1.25 GB).
- `/media/` answers with `Access-Control-Allow-Origin: https://lunaway.net`:
  the web app reads a photo with `fetch`, from another origin. Without it
  every photo failed in the web app (measured in Chromium on 2026-10-07,
  "No 'Access-Control-Allow-Origin' header is present"). A browser that
  stored a photo before the header came keeps its copy without it, for a
  year (`immutable`), until its cache drops it.
- The photos of the external community source come through
  `GET /external-photos/{id}/thumb|large` (see "The external community
  feed"): the API downloads one from the partner the first time a device
  asks for it, stores it like an upload, and answers a redirect to its file
  under `/media/`.
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
| `lunaway-ingest-osm.timer` | daily, 03:00 UTC | `lunaway ingest osm-extract --extract france --refresh`: the places of the Geofabrik France extract (Monaco included), streamed to disk and resumed after an interruption |
| `lunaway-ingest-osm-europe@<Day>.timer` | weekly, Monday to Saturday, 05:00 UTC | `lunaway ingest osm-extract $LUNAWAY_EXTRACTS_<Day> --refresh`: the places of one group of the other 23 European extracts, listed in `/usr/local/share/lunaway/osm-extracts.env` (from `infra/files/`); Germany alone on Monday (see "Europe and the regional packs") |
| `lunaway-ingest-atout-france.timer` | Sundays, 04:00 UTC | `lunaway ingest atout-france --refresh`: the classified campsites, geocoded |
| `lunaway-ingest-pois.timer` | daily, 03:45 UTC, after the places import | `lunaway ingest pois --extract france`: the points of interest of the same cached extract, then their opening hours, then the establishments of the search (3 GiB cap) |
| `lunaway-ingest-pois-europe@<Day>.timer` | weekly, Monday to Saturday, 05:45 UTC | `lunaway ingest pois $LUNAWAY_EXTRACTS_<Day>`: the points of interest of that day's group, from the files its places import cached; waits for that import when it still runs |
| `lunaway-ingest-fuel.timer` | every 15 minutes (`*:05/15`) | `lunaway ingest fuel --refresh`: the fuel price feed, joined to the fuel stations |
| `lunaway-ingest-laposte.timer` | daily, 04:10 UTC | `lunaway ingest laposte --refresh`: La Poste's calendar for two weeks, joined to the post offices |
| `lunaway-ingest-finess.timer` | the 2nd of each month, 04:20 UTC | `lunaway ingest finess --refresh`: the FINESS snapshot (closures); snapshots older than 45 days are removed |
| `lunaway-ingest-overture.timer` | the 28th of each month, 09:00 UTC, after the points of interest of the day | `lunaway ingest overture`: the establishments OpenStreetMap lacks, from the latest release of Overture Maps Places (`docs/data-sources.md`, "Establishments from Overture Maps Places"): the release's files of Europe and Morocco (7 files, 4.7 GB) downloaded once into `/srv/data/ingest/raw/overture/<release>/`, those of the release before removed after a complete run; a run that stops resumes after the last file it stored |
| `lunaway-ingest-datatourisme.timer` | Sundays, 04:30 UTC, when the key is installed | `lunaway ingest datatourisme --refresh`: the tourist offices' motorhome areas, service areas and campsites, then the conflation (`OnSuccess=`) |
| `lunaway-ingest-extcom.path`, `lunaway-ingest-extcom.timer` | when a file lands in `/srv/data/extcom-inbox`, and hourly; once `/etc/lunaway/extcom.env` is installed | `lunaway-extcom-inbox import`: the newest feed of the external community source not imported yet, checked against its SHA-256, then `lunaway ingest extcom --file`; after an import, the conflation (and the packs after it) and `lunaway-extcom-purge-media.service` (see "The external community feed") |
| `lunaway-extcom-purge-media.timer` | daily, 05:10 UTC, and after each import of that feed | as the API's user and role: `lunaway extcom purge-media --yes`, the files and rows of the source's retired photos, and the files of its photos made without cutting the band of its mark |
| `lunaway-extcom-erasures.timer` | hourly at :25, and after each `lunaway-admin extcom erase-author --yes` | as the imports: `lunaway extcom erasures --out /srv/data/extcom-erasures/erased-authors`, the SHA-256 of every erased author id of the source, which its producer reads (see "The external community feed") |
| `lunaway-content-refresh.timer` | Sundays, 07:00 UTC | `lunaway content refresh` then `lunaway content gc`: the open content of the places (Commons and Panoramax photos, Wikipedia, the offices' texts and photos, Mangrove reviews, which also reach the named points of interest), each place asked once a week, by batches of 50 read from where the run stands (`lunaway_db::content::places_due`, under a second a batch on 2026-10-09; a run that starts again skips the places asked this week); then, once every source has read its places, the Commons and Panoramax photos the points' own tags name, 2 000 points a source and run at most, least recently asked first (`lunaway_db::content::pois_due`; measured on France on 2026-10-10, 3.4 s a point on Commons and 0.9 s on Panoramax, so about two hours and a half; a run its timeout stops before leaves the points for the next one: `journalctl -u lunaway-content-refresh` says "refreshing the open content of the points" when they start). The photos under `/srv/data/media/external` (lunaway-ingest, setgid caddy, served under `/media/`); nothing to back up, a run makes it again. An item users report three times is hidden until a moderator decides (`lunaway moderation list`), and an operator hides one for good with `lunaway content hide` |
| `lunaway-conflate.service` | after each successful import (`OnSuccess=`) | `lunaway conflate` |
| `lunaway-packs.service` | after each conflation that follows an import of places (`OnSuccess=` of `lunaway-conflate.service`), and daily at 06:30 UTC (`lunaway-packs.timer`) | `lunaway packs build`: the regional first-sync packs of the regions whose places changed, into `/srv/data/packs/places/` (`docs/region-packs.md`) |
| `lunaway-enforcement.timer` | daily, 05:30 UTC | `lunaway-cameras.service` (`lunaway ingest cameras --refresh`, the official lists, each downloaded at its own pace), then `lunaway-enforcement.service` (`lunaway enforcement build`), which runs whether a list failed or not |
| `lunaway-enforcement-full.service` | after each new routing graph, started by `lunaway-routing-refresh` | `lunaway-cameras-osm.service` (`lunaway ingest cameras-osm --europe`, from the cached extracts, no download unless a file is missing), then `lunaway enforcement build --full` |
| `lunaway-conflate-worker.service` | always (`Restart=always`, 15 s apart, at most 10 starts in 15 minutes) | `lunaway conflate --watch`: applies the community's submissions, refreshes the places' community summaries, conflates what the imports flagged, and slides the opening hours to the new day; after a run, publishes the points layer (every 6 hours at most), computes the places' filter ratings again (once 15 minutes have passed, checked at each run, so every 15 to 20 minutes; a Lunaway user's rating sets its place's with the summary; `lunaway_db::place_ratings`) and publishes the places layer (every 15 minutes at most, "Places layer"). The API wakes it with a `NOTIFY` when it commits work; it also runs at least every 5 minutes |
| `lunaway-worker-status.timer` | every minute | as `postgres`: the worker's queue sizes and ages, the age of the last stored fuel feed, the points layer's pending change, the speed camera lists' last reads and the regional packs behind their places, into `/var/lib/lunaway-status/worker.json`; every 15 minutes, the age of each country's OpenStreetMap places into `imports.json`; both for the health probe |
| `lunaway-migrate.service` | on a deploy only | `lunaway migrate`, as `lunaway_owner` |

The nightly conflation timer of earlier versions is gone: the worker runs at
least every 5 minutes and recomputes "today" at each run.

An import whose next run is a day or more away (every `lunaway ingest ...`
unit above except fuel and the external community feed,
`lunaway-content-refresh`, `lunaway-road-events-dialog`, `lunaway-cameras`,
`lunaway-cameras-osm`) runs again 15 minutes after the database left it,
three runs at most (`RestartForceExitStatus=75`, `RestartSec=15min`,
`StartLimitBurst=3`). On 2026-10-08 at 01:36 UTC, needrestart restarted
PostgreSQL after an update of liblzma5 and the weekly content refresh died
with "terminating connection due to administrator command"; its next run was
a week away. The CLI exits with status 75 (`EX_TEMPFAIL`) when the cause of
its failure is the database going away (`lunaway_db::connection_lost`: a
shutdown or restart under a query, a connection exception, the socket
closed or refused, no connection in time) and with 1 otherwise. No other
failure is retried: a source that refused us, or asked to wait longer than
an import waits, is not asked again before the next run, and a check that
stopped an import (a truncated extract, too many places retired) would stop
it again. A run stopped by its timeout or by a reboot is not retried either;
its timer runs it at its next date.

Each unit's `StartLimitIntervalSec=` holds its three runs at their longest
(systemd arms `TimeoutStartSec=` again for each start command,
`ExecStartPost=` included), the waits between them, and for each run the
longest run of a unit it is ordered after (`After=`), so a fourth start
falls inside it and is refused; and it ends before the unit's next timer,
which then runs it as usual. A longer chain of waits (`lunaway-ingest-laposte`
waits for the points of interest, which wait for the places and their
conflation) can push a fourth start past the window; it still needs the
database to go away under each run before it. `infra/tests/unit-restart.py` checks
both on the unit files (`tool/check.sh` runs it). Measured on the
backend's systemd 257 with transient units: a unit exiting 75 runs three
times, then systemd logs "Start request repeated too quickly" and the unit
stays `failed` (result `exit-code`); one exiting 1 is not run again; a
`systemctl daemon-reload` during the wait keeps the count. While it waits
the unit is `activating (auto-restart)`, which the health probe does not
count as failed. Any start counts, a manual one too: after running an
import by hand, `systemctl reset-failed <unit>` empties the count so that
its timer is not refused within the window.

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
sudo lunaway-admin moderation approve <entry> --note TEXT  # write access to /srv/data/media (a removal
sudo lunaway-admin moderation ban <account> --reason TEXT # deletes the photo files) and the deletion journal
sudo lunaway-admin accounts create-demo --level 2        # the store reviewers' account: prints its recovery code
sudo lunaway-admin accounts set-level <account> 4        # a moderator
sudo lunaway-admin accounts find "<pseudonym>"            # the accounts of a pseudonym, with what each holds
sudo lunaway-admin accounts delete <account> [--yes]     # as deleteAccount, journaled first; without --yes, shows only
sudo lunaway-admin accounts import-deletions < FILE     # the journal's copy back into its days (see "Backups and restore")
sudo lunaway-admin accounts replay-deletions [--dry-run] [--allow-empty]  # after a restore (see "Backups and restore")
sudo lunaway-admin moderation confirmations <place>      # its "still there?" answers, author or "a deleted account"
sudo lunaway-admin moderation remove-confirmation <id>   # a false one, or a test left on a real place
sudo lunaway-admin moderation take-down <place> [--yes]  # step 2 of "Taking a place down"
sudo lunaway-admin ingest osm-extract --extract france   # as the imports: user lunaway-ingest, role lunaway_ingest,
sudo lunaway-admin ingest municipalities                 # the import cache, HTTPS out (no private ranges)
sudo lunaway-admin ingest pois --extract spain           # 3 GiB cap for the imports (the extract reader)
sudo lunaway-admin ingest osm-extract --europe --refresh # every European extract in one run (see "Europe and the regional packs")
sudo lunaway-admin ingest cameras --refresh              # the official speed camera lists
sudo lunaway-admin ingest cameras --list france-dsr --force   # a list now, whatever the age of its copy
sudo lunaway-admin ingest cameras --list france-dsr --force --allow-change   # a yearly file that moves by more than a tenth, its cause known
sudo lunaway-admin ingest cameras-osm --europe           # OpenStreetMap's cameras, from the cached extracts
sudo lunaway-admin ingest extcom --file /srv/data/extcom-inbox/<feed>  # with /etc/lunaway/extcom.env as well
sudo lunaway-admin extcom status                         # the external community source: switch and counts
sudo lunaway-admin extcom hide|show [--note TEXT]        # import role, loopback only, after a running import (docs/feeds.md, "Switches")
sudo lunaway-admin extcom purge [--yes] [--note TEXT]
sudo lunaway-admin extcom erase-author - [--yes]         # the id on standard input, not echoed,
                                                         # never on a command line that sudo logs;
                                                         # then the producer's list is written again
sudo lunaway-admin extcom purge-media [--yes]            # as the API: the retired photos' files, and those made uncut
sudo lunaway-admin conflate --full
sudo lunaway-admin conflate --same|--distinct <source:id> <source:id> --note TEXT  # a merge the score got wrong
                                                         # (docs/conflation.md, "Groups"); the worker applies it;
                                                         # a pair decided already is refused (the owner replaces)
sudo lunaway-admin conflate --take-down <place> --reason-code CODE [--yes]  # step 1 of "Taking a place down",
                                                         # conflate and takedowns get the takedown secret and journal
sudo lunaway-admin takedowns import < FILE               # the takedown journal's copy back into its days
sudo lunaway-admin takedowns replay [--dry-run]          # after a restore; replay-takedowns below does all three steps
sudo lunaway-admin stats
sudo lunaway-admin addresses --for-mins 5                # the places' reverse geocoding now (lunaway-addresses.timer)
sudo lunaway-admin pois stats                            # the layer of points of interest and its joins
sudo lunaway-admin road-events stats                     # the road events by source, class and placement
sudo lunaway-admin packs build                           # the regional packs now; writes /srv/data/packs only
sudo lunaway-admin packs build --region FR-BRE --takedown  # after a place is taken down (docs/region-packs.md)
sudo lunaway-admin packs list
sudo lunaway-admin enforcement build [--full]            # the zones and points, with the zones' secret and the engine
sudo lunaway-admin enforcement stats                     # each list's last read, the items by kind and country
sudo lunaway-admin take-down <place> --reason-code CODE [--yes]  # the three steps of "Taking a place down", in order
sudo lunaway-admin replay-takedowns [--dry-run]          # after a restore (see "Backups and restore")
sudo lunaway-admin migrate                               # starts lunaway-migrate.service
```

### Taking a place down

For a place that must leave the map for good: a private home listed as a
spot, a request under the GDPR (erasure, objection), a court order. Hiding
or editing does not answer such a request: the name, the position and the
address stay in the database, the records come back with the next import,
and the devices keep their copy. The takedown removes all of it, in three
steps. The normal path runs them in order, each under its own identity,
and stops at the first that fails:

```bash
sudo lunaway-admin take-down <place> --reason-code gdpr        # step 1's preview, changes nothing
sudo lunaway-admin take-down <place> --reason-code gdpr --yes  # steps 1, 2 and 3
```

`--reason-code` (`private-home`, `gdpr`, `court-order` or `other`) is
required: the request is kept as that code only, in the database and in
the takedown journal. No free text goes on the command line, which lands
in the `sudo` log; the wrapper refuses `--reason`, and the request's
reference stays in the maintainer's own records. `sudo` writes the whole
command line to the journal before the wrapper runs: a text typed there
by mistake stays until the journal's own expiry. It takes `--with-nearby`
like step 1, and gives steps 2 and 3 the place
and the region step 1 prints (an id merged into another names the other).
When it stops, the step that failed and what to run next are printed. The
manual path, the same three commands one by one:

```bash
sudo lunaway-admin conflate --take-down <place> --reason-code gdpr        # prints, changes nothing
sudo lunaway-admin conflate --take-down <place> --reason-code gdpr --yes  # 1. the catalogue
sudo lunaway-admin moderation take-down <place> --yes                                     # 2. the community's content
sudo lunaway-admin packs build --region <code> --takedown                                 # 3. the pack (printed by 1)
```

- **Which place.** The id the app shows (`Place.id`). An id merged into
  another place takes down the place that absorbed it, and every place
  merged into that one: they are one spot to the conflation. Without
  `--yes`, both commands print the place, its region and what they touch
  (merged places, records, reviews, photos, confirmations, issue reports,
  submissions) and change nothing.
- **1. The catalogue**, as the import role: it first conflates what
  waits (a record not read yet could become the place again; if one
  arrives meanwhile, it stops and asks to run again), then, under the
  writers' lock, the place and the places merged into it keep their id,
  kind and country and lose everything else (name, position, address,
  hours, links, descriptions, provenance, community summary). Every record
  that described them is emptied the same way and kept, marked, so that
  the next import of its source writes nothing into it and no conflation
  makes a place of it again: the records linked now, and those the
  conflation unlinked from them (`last_place_id`: a record its source
  retired, a group held back). Retired records unlinked before that column
  existed name no place: the preview lists those within their kind's reach
  of the place (source, external id, kind, name, distance), and
  `--with-nearby` empties them too, once the list shows they are the
  place's and not a neighbour's. The submissions about the place lose
  their content, and those waiting are refused. The takedown is logged in `place_takedowns` with its reason code only
  (the table accepts the four codes and nothing else). Before it
  commits, it is written to the takedown journal outside the database
  (`/srv/data/place-takedowns`, one file per UTC day: the places' ids, the
  date, the reason code, the keyed hashes of the cells around the place,
  the secret's check value; no name, position or reason text), and the
  cells of its exclusion zone are stored, keyed with
  `LUNAWAY_TAKEDOWN_SECRET`. The API's
  role cannot take this step: a leak of its credentials must not empty the
  catalogue.
- **2. The community's content**, as the API's role, which writes it and
  owns the photo files: the reviews, photos (files included, unless
  another photo shows them), "still there?" answers and issue reports of
  the place and of the places merged into it are deleted, with the
  content reports and queue entries about them. It refuses to run before
  step 1; after step 1 the place accepts no contribution, so nothing
  arrives after it. Run it right after step 1: until then the photos stay
  served at the addresses devices and older packs hold. `lunaway stats`
  counts the places taken down whose community content is still there.
- **The devices.** The tombstone takes a new position in the change feed.
  Having no position, it goes to every device that syncs by box, whatever
  its box; a device that syncs a region gets it as gone from that region.
- **3. The packs.** The current pack of the place's region still holds it
  until `lunaway packs build --region <code> --takedown` (as the import
  role, which owns the packs) builds the region again and removes every
  file the manifest does not name.
- **Again.** Running step 1 again empties what was missed and keeps the
  first reason and date; step 2 again deletes what is left. A takedown is
  not undone: a spot that should come back is added again as a new place.
- **What stays.** The emptied records keep their source and external id
  (an OpenStreetMap element id, for instance): it is the key that keeps
  the next import out of them. OpenStreetMap's own history of that element
  is public and outside Lunaway.
- **A new listing of the same spot.** A new place, or a place moved, within
  125 m of a place taken down (never beyond 266 m: the cells of its zone)
  waits for a moderator instead of going live: `moderation list` shows it
  with the reason "near a taken-down place"; `moderation approve` publishes
  it and journals the decision, `moderation reject` leaves it held. The
  conflation worker reads the cells with `LUNAWAY_TAKEDOWN_SECRET`
  (`/etc/lunaway/takedown.env`); without the secret it holds nothing and
  logs a warning, and `conflate --take-down` refuses to run.
- **Backups.** The copies taken before the takedown still hold the place
  until they age out (see "Backups and restore"): the encrypted dumps (7 on
  the backend, 14 days on the ops server, 29 days on the Mac), the photos
  of deleted entries (26 days in `media-deleted/` on the backend and on
  the Mac), and the daily images of the backend's root disk. A restore of
  an older dump brings the place back: the takedown journal, copied off
  the server every hour, takes it down again after the restore
  (`lunaway-admin replay-takedowns`, see "Backups and restore").

### Points of interest

The layer "around me" (`plan/research/18-backend-poi.md`): 314 671 points
on 2026-10-06, 1,908,026 visible on 2026-10-08 with Europe (shops, vending
machines, water, fuel, health, services) from
the OpenStreetMap extract, joined by id to the fuel price feed, La Poste's
calendar and FINESS. The API serves it as PostGIS vector tiles:

- `GET /poi/tiles.json`: the TileJSON, cached 60 s. Its tile URLs name the
  API's public URL, `LUNAWAY_PUBLIC_URL` in `/etc/lunaway/media.env`,
  which `infra/server/api.sh` derives from the photos' base URL
  (`https://api.lunaway.net`).
- `GET /poi/{version}/{z}/{x}/{y}.mvt`: points from zoom 13, clusters per
  category from 6 to 12, every category but the food and the sights.
- `GET /poi/all/tiles.json` and `GET /poi/{version}/all/{z}/{x}/{y}.mvt`:
  the same version with every category, which the app reads while it
  shows the food or the sights. Measured in production on 2026-10-09,
  version 41 against 43, on 670 tiles (zoom 6 to 8 over France, 10 to 14
  around 14 cities; `plan/research/86-categories-poi.md`): the default
  tiles moved by -5.0 to +0.9 % (gzip, per zoom; their clusters lost the
  tourist offices, a sight now), the tiles of every category by +30 to
  +39 % below zoom 13, +112 % at 13 and +145 % at 14. The current
  version is cached a year (`immutable`); any other version gets the
  current data for 5 minutes.
  204 outside the layer's bounds.

A cluster stands for the points of one category in one cell of a 32 by 32
grid aligned on its tile, so that a cell is exactly four cells of the next
zoom; its position is the barycentre of those points (floored to the tile's
unit) and `count` their number. The food vending machines are counted again
per kind in `poi_vending_clusters`. Positions are integers on a grid of
2^28 cells a side over Web Mercator (`lunaway_grid_x` and `_y`, the
spherical formula of EPSG:3857, which put each of the 200,961 places of
2026-10-08 in the same pixel as `ST_Transform` at every zoom from 2 to 9).
Until 2026-10-08 the cells were centred on the grid lines
(`ST_SnapToGrid`), so a cell on a tile's edge was cut in two.

**Clusters counted at publication.** The clusters of zooms 6 to 9 are
read from `poi_cluster_cells` (one row per zoom, cell, category or vending
kind, with the count and the sums of the positions; 1,413,994 rows, 160 MB
with its key, for the 1,908,026 visible points of 2026-10-08). When the
worker publishes a version (`pois::publish_layer`, at most every 6 hours,
or `publish_layer_now` after a moderator's hide), the same transaction
counts every visible point again (`poi_cluster_cells_computed`) and a
`MERGE` writes the cells that changed: 7.8 s on a copy of production with
no change, most of it reading the 2.4 GB of `pois`, under the POI writers'
lock. The tiles of zooms 6 to 9 change with the version and only then; from
zoom 10 a tile counts its own points when it is built (the densest of zoom
10 held 22,275 points).

| points, every tile holding one (2026-10-08) | tiles | production, slowest of 3 sampled, before | copy before: p50 / p95 / max | copy after: p50 / p95 / max |
|---|---|---|---|---|
| z6 | 84 | 10,363 ms | 18.7 / 690 / 1,182 ms | 0.6 / 5.3 / 8.5 ms |
| z7 | 244 | 758 ms | 9.5 / 220 / 522 ms | 0.6 / 5.2 / 8.1 ms |
| z8 | 780 | 1,183 ms | 4.4 / 77 / 256 ms | 0.3 / 3.0 / 5.5 ms |
| z9 | 2,545 | 1,171 ms | 2.6 / 27 / 302 ms | 0.2 / 1.5 / 6.8 ms |
| z10 | 8,145 | 438 ms | 3.0 / 14 / 218 ms | 2.5 / 9.4 / 161 ms |
| z11 | 25,034 | 169 ms | 1.9 / 6.6 / 163 ms | 1.9 / 4.8 / 102 ms |
| z12 | 71,386 | 72 ms | 0.7 / 2.2 / 37 ms | 0.7 / 2.1 / 42 ms |

The build time is the database's (plan and execution), one tile after the
other, outside the API's memory. The copy is a PostgreSQL 18 + PostGIS 3.6
container on the maintainer's Mac holding `places`, `pois` and
`poi_join_records` of production (`pg_dump --data-only`); production took
0.9 to 14 times as long for the same tiles before the change (4 times for
most of the places' tiles), the slowest reading heap pages from the disk.
Before the change the API answered 503 to 18 tiles of zoom 6 in a day (its
4 s limit). The copy's cluster tiles came out 1 to 5% smaller (5% at zoom
6), fewer clusters being cut by an edge.

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
| `ingest overture --country FR --country MC` (the maintainer's Mac, 2026-10-10) | 4 min 52 s, one file of 621 MB downloaded; 2 min 58 s again, nothing new | 213 MiB | 768 MiB soft, 1 GiB |

The places import reads the extract with the same reader and peaked at
2.5 GiB with its page cache the same day; its cap went from 2 to 3 GiB.
The database grew from 323 MB to 994 MB (`pois` 591 MB, the joins 73 MB);
the cache holds 12 MB of fuel feed, 41 MB of La Poste pages and 49 MB a
month of FINESS.

**Establishments.** After the points and their hours, `ingest pois` reads
the same extract again for every named shop, service and venue the
search finds (`Layer::Establishments`, `in_tiles = false`; `--no-establishments`
skips it). It reads the extract twice, the shops then the rest, so it holds
half the points at once: on the maintainer's Mac on 2026-10-10, France
gave 513,808 establishments, the whole `ingest pois --extract france`
took 3 min 26 s on an unchanged database (60 s for the points, 2 min 21 s
for the establishments, nothing written), with a resident peak of
2,051 MiB against 2,391 MiB in one read. The migration
`20261010135000_poi_search` fills the search table of every live point
(985,572 rows in 20 s on that Mac). The tiles, "around this place", the
search along a route and the hours worker leave the establishments out
through the predicate of their partial indexes (`AND in_tiles`). At its
end the import clears the search words no live point bears any more
(`search words no point bears any more, cleared: n`). The first import
after the release of the establishments rewrites the data of most points
of the tiles (their new fields: Wikidata, Commons, Panoramax, internet
access, cuisine), so the next publication is a new tiles version for
every device, and its count of the clusters reads a heap about twice as
large.

The Overture import spends its time in PostgreSQL: each place it keeps is
looked up among OpenStreetMap's points around it (`lunaway_db::pois::twins`,
500 a statement, under a second in central Paris), 0.5 to 0.8 ms a place on
the Mac against France's 985,572 points; reading the files took 31 s of CPU
for France. Europe and Morocco, estimated from the release's files (five in
the cache, two read over HTTPS for their columns only): 2,506,691 places
pass the rules (Italy 432,895, the United Kingdom 405,984, France 334,223,
Germany 328,114, Spain 233,994; Morocco 2,385), so about half an hour of
lookups at the Mac's pace, and some 700,000 written if a quarter to a third
pass the deduplication as in France; Morocco's places meet no OpenStreetMap
point (its extract is not imported) and are all written. Its files take 4.7
GB of the data volume (115 GB free on 2026-10-06), once per release. Its
rows take about 1.5 kB each in `pois` (141 MB for France's 94,586, the raw
payload and the record), so about 1 GB for Europe at the estimate above.

### Places layer

The places as map tiles, so the web app shows them without syncing every
place into its WebAssembly SQLite (about a minute at the first load on
2026-10-07, 15 s before the points showed on a second load). The app filters
the tiles with a MapLibre filter expression, on the device, without a
request; a tap reads `place(id)`; the list beside the map is
`places(bbox, near:)`, nearest to the map's centre first. The API serves
(`lunaway-api/src/tiles.rs`, the same code as the points, one endpoint per
layer; `lunaway-db/src/place_tiles.rs`):

- `GET /places/tiles.json`: the TileJSON (3.0.0), cached 60 s, its tile
  URL under `LUNAWAY_PUBLIC_URL`, `minzoom` 2, `maxzoom` 14, the layer's
  bounds (`BOUNDS`, every place on 2026-10-07 lies inside), the attribution
  of the sources places are made of (OpenStreetMap, Lunaway contributors,
  Atout France with its positions from the Base Adresse Nationale and IGN
  BD TOPO, DATAtourisme, and "Source communautaire externe", whose places
  and names the tiles carry since 2026-10-07) and every field of both
  layers.
- `GET /places/{version}/{z}/{x}/{y}.mvt`, as `/poi/`: the current
  version cached a year (`immutable`), an older version the current data
  for 5 minutes, a version newer than the one the API read (it reads again
  at most every 200 ms) the current data with `no-store`, so a tile that
  still shows a place taken down is kept by nobody; an ETag and 304, 204
  for an empty tile or outside the bounds, 404 below zoom 2, above 14 (maps
  draw zoom 14 beyond) and for coordinates not written in digits (`+12`
  would escape Caddy's log mask); the CORS headers of `https://lunaway.net`,
  gzip when the client accepts it.

| layer | zooms | one feature per | properties |
|---|---|---|---|
| `places` | 10 (`PIN_ZOOM`) to 14 | live place | `id`, `kind`, `night`, `s`, `price`, `h`, `r`, `o1`, `o2`; `name` and `city` (the address's town, else the commune's) from zoom 12 |
| `place_dots` | 2 (`DOTS_MIN_ZOOM`) to 9 | set of properties, a MultiPoint of one point per pixel of a 512 px tile, the margin included (below) | `kind`, `night`, `s` (bits 0 to 8), `price`, `h`, `r` (cut to 30, 40, 45), `o1`, `o2` |

`kind` and `night` are the domain's codes (`motorhome_area`,
`tolerated`...). `s` is the services mask, bit i for the i-th
`lunaway_domain::Service` (drinking water 0 ... winter caravanning 16; the
stored column `places.services_mask`, and a test pins every bit). `price`
is 0 when the parking is free, 1 when it is paid, absent when unknown. `h`
is the height limit in whole centimetres, absent when unknown. `r` is the
rating the filters use (`places.filter_rating`, `Place.ratingForFilters`)
in tenths, 33 for 3.3, absent when nobody rated the place: every rating
the place's page shows, Lunaway users' and the other sources', each rating
weighing the same (the SQL function `lunaway_filter_rating`; one user's 4
beside 246 ratings of 3.3 elsewhere gives 33). The worker computes the
other sources' part again at most every `--place-layer-every-mins`,
before it publishes a version, and keeps it in `place_other_ratings`
(empty after the migration `20261010140500` until the worker's first
pass, minutes after a deploy: a rating given meanwhile counts alone
until that pass), so
a Lunaway user's rating changes the place's at once with its summary
(`lunaway_db::place_ratings`, 1.2 to 1.5 s over the 200 961 places of
2026-10-08); on that day 98 525 places had one, 83 525 of 3 or more,
51 627 of 4 or more, 24 544 of 4.5 or more. In the dots `r` is the highest
step of the app's minimum rating the place reaches (`DOTS_RATING_STEPS`:
45 from 4.5, 40 from 4, 30 from 3), absent below 3: a filter at a step
keeps a dot exactly when it keeps one of its places, and the exact tenths
would multiply the distinct dots. `o1` and `o2` are the ranges of the
place's season (`places.opening_season`, `Place.openingSeason`), each as
first day * 1000 + last day in days of a leap year (92305 for 1 April
to 31 October, 1366 for the whole year), absent when its hours are no
season (`lunaway_domain::season`): the filter on the dates of a stay
(`openDays`) keeps a place without a season, and one whose ranges hold
every range of the stay. The columns came without a refill of the dots
(migrations 20261009020100 and 20261009020110, after the layer's lock):
no place had a season then, the new key is built while the API reads
on, and a publication of the release before that falls between the key's
change and the new release fails and is done again by the new worker. A
taken-down or deleted place is in no tile. The first refresh after the column's migration writes every rated
place, 98 525 on 2026-10-08, each with a new position in the change feed:
devices that keep regions download them again with their next sync, and
every pack is built again (its selection changed). The time of that first
write was not measured; it holds the writers' lock, not the API's reads,
and is expected to take seconds, far below the import role's 10 minutes of
`statement_timeout`.

**Filters on the dots.** A server cluster with a count cannot answer the
app's filters: any subset of kinds, a subset of overnight statuses, groups
of services where one of each must be present (a dump station is grey or
black water), free only, a vehicle height, a minimum rating. So the low
zooms carry every place, and two places merge into one dot only when they
fall in the same pixel with the same properties. A filter on those properties keeps a dot
exactly when it keeps at least one of the places it stands for, and a
pixel shows a dot exactly when one of its places passes: the map is the
same as with every place drawn. `s` keeps bits 0 to 8 in the dots, the
services the filters offer; a filter on another service would be wrong
below zoom 10, and the app offers none. The length, width and weight
limits are in no tile; the app filters on the height only. The same
semantics hold in `places(filter:)` (`overnight`, `serviceGroups`,
`freeOnly`, `vehicleHeightM`, `kinds`, `services`, `overnightOk`,
`minRating`: `r >= 10 * minRating`, a place without `r` never;
`openDays` on `o1` and `o2`), and
`lunaway-api/tests/place_tiles.rs` checks, filter by filter, that the list
and the tile keep the same places.

What `r` costs, measured on 2026-10-08 on production (read-only: the tile
queries with and without `r`, the rating computed from
`external_ratings`; gzip at level 6), over Annecy:

| tile | without `r`, raw / gzip | with `r`, raw / gzip |
|---|---|---|
| dots z5 16/11 | 236 762 / 146 824 B | 301 620 / 186 372 B |
| dots z7 66/45 | 38 893 / 25 422 B | 49 768 / 30 455 B |
| dots z9 264/182 | 6 568 / 4 172 B | 8 703 / 4 989 B |
| pins z10 529/364 | 22 882 / 8 640 B | 23 592 / 9 274 B |

**Measurements** (2026-10-07, a throwaway cpx22 with PostgreSQL 18.1 and
PostGIS 3.6.1, the 86 111 places of the 34 public regional packs loaded
into `places`; build times measured inside the database; gzip at level 6,
what the API's compression uses):

| pins, densest tile of Europe | places | with names, raw / gzip | without names, raw / gzip |
|---|---|---|---|
| z10 | 197 | 17 932 / 6 828 B | 12 736 / 4 136 B |
| z11 | 100 | 8 828 / 3 716 B | 6 576 / 2 218 B |
| z12 | 57 | 5 116 / 2 169 B | 3 740 / 1 368 B |
| z14 | 29 | 2 288 / 866 B | 1 909 / 667 B |

| pins at z10, over | with names, raw / gzip | without, raw / gzip |
|---|---|---|
| Annecy | 4 690 / 2 277 B | 3 434 / 1 430 B |
| the Gulf of Morbihan | 7 496 / 3 318 B | 5 448 / 2 027 B |
| Paris | 1 978 / 978 B | 1 722 / 739 B |

Names add 60 to 70% to a tile at zooms 10 to 12, where a map draws no
label for a pin anyway: they travel from zoom 12 (`NAME_MIN_ZOOM`), where
the densest tile weighed 2.2 KB gzip on 2026-10-07, before the town
travelled with the name. The town travels with it: from
that zoom the app's list beside the map reads the pins in view rather than
ask the API (nothing of the view leaves the device beyond the tiles), and a
row names an unnamed place by its town. The 7 337 tiles of zoom 10 hold
3.3 MB gzip in all, built in 1.9 s together (30 ms the slowest).

| every tile holding a place, Europe | tiles | dots: build, all / slowest | dots: gzip, all / largest | clusters per kind: gzip, all / largest |
|---|---|---|---|---|
| z2 | 3 | 391 ms / 245 ms | 62.9 / 46.6 KB | 7.8 / 4.9 KB |
| z3 | 5 | 625 / 519 ms | 90.8 / 63.0 KB | 19.1 / 11.4 KB |
| z4 | 13 | 680 / 410 ms | 122.8 / 67.4 KB | 45.3 / 17.4 KB |
| z5 | 26 | 689 / 149 ms | 160.8 / 32.9 KB | 100.8 / 16.6 KB |
| z6 | 78 | 686 / 58 ms | 212.4 / 16.3 KB | 192.4 / 12.9 KB |
| z7 | 236 | 753 / 24 ms | 295.9 / 6.6 KB | 302.0 / 6.3 KB |
| z8 | 745 | 854 / 8 ms | 454.0 / 3.4 KB | 441.0 / 3.6 KB |
| z9 | 2 416 | 1 226 / 3 ms | 795.9 / 1.4 KB | 703.6 / 1.4 KB |

The clusters are those of the points (a 32 by 32 grid per kind, with a
count), measured for comparison only. From zoom 6 the dots weigh what the
clusters do; below, two to five times more, for a map that stays right
under every filter. The choices behind these numbers, on the tile of zoom 2
to 5 over France:

- one MultiPoint per set of properties instead of one point feature per
  dot: 47 KB gzip at zoom 2 instead of 132 KB;
- the points of a MultiPoint row by row: 33 KB gzip at zoom 5 instead of
  51 KB in the database's order (a Morton order gave about the same size
  and cost three times the time);
- a 512 unit extent (one per pixel); 256 units would save a third at
  zooms 2 to 4 but merge places two pixels apart;
- the services mask stored (`places.services_mask`, migration
  `20261008090000`, 1.5 s on the 86 111 places): computing it per place
  took 230 of the 390 ms of the zoom 2 tile.

Zoom 2 is the lowest because its three tiles weigh less than those of zoom
3 or 4 (pixels merge more places) and show the whole of Europe; zoom 10 is
the first with pins because the densest tile there holds 197 places, 4.1
KB gzip, against 7.7 KB (360 places) at zoom 9.

**Dots kept per version.** Since 2026-10-08 a dots tile reads its rows of
`place_dots` (one row per tile, pixel and set of properties, with the
number of places in it, the margin included: 1,480,623 rows, 216 MB with
its key, for the 200,961 places of that day) instead of every place of its
square. The key's order is the order a tile is written in, so the database
reads a tile from the index alone, without a sort. A publication of the
layer (`place_tiles::publish_layer`, `publish_layer_now`) applies, in the
transaction that moves the version, the places written since
`place_layer.dots_seq`: it takes away the dots of each such place as
`place_dot_members` remembers them (each live place as the current version
shows it, 25 MB) and adds those of its state now; a dot goes with its last
place. On the copy below, 2,000 places written without a change of their
dots cost 69 ms, 2,000 places moved 0.4 s (20,155 dots written, 9,833
removed). `dots_seq` is kept apart from `published_seq` so that a version
published by a release that does not keep the dots (the worker of the
release before, until the deploy restarts it, or a rollback) is caught up
by the next publication of a release that does: the worker publishes when
the feed went past either position. The views
`place_dot_sources` (a live place as a dot) and `place_dots_computed` (every
dot, from the places) say what the table must hold: the migration fills it
from them, and `lunaway-db/tests/place_tiles.rs` checks after each kind of
write that the publications keep it equal. A migration that changes what a
dot is made of without writing the places fills both tables again.

| dots, every tile holding a place (2026-10-08) | tiles | production, slowest of 3 sampled, before | copy before: p50 / p95 / max | copy after: p50 / p95 / max | raw bytes of all tiles, before / after |
|---|---|---|---|---|---|
| z2 | 3 | 1,988 ms | 194 / 483 / 515 ms | 24 / 35 / 36 ms | 324 / 375 KB |
| z3 | 5 | 1,948 ms | 26 / 440 / 504 ms | 2.3 / 39 / 44 ms | 403 / 445 KB |
| z4 | 13 | 1,786 ms | 4.5 / 289 / 448 ms | 0.4 / 29 / 50 ms | 478 / 504 KB |
| z5 | 26 | 1,539 ms | 4.6 / 153 / 418 ms | 0.5 / 13 / 35 ms | 576 / 602 KB |
| z6 | 78 | 775 ms | 1.8 / 77 / 146 ms | 0.2 / 6.6 / 11 ms | 721 / 756 KB |
| z7 | 236 | 291 ms | 1.3 / 61 / 94 ms | 0.1 / 2.5 / 5.6 ms | 935 / 981 KB |
| z8 | 746 | 133 ms | 0.7 / 28 / 49 ms | 0.1 / 0.9 / 2.9 ms | 1,258 / 1,315 KB |
| z9 | 2,418 | 69 ms | 0.5 / 2.9 / 20 ms | 0.1 / 0.3 / 0.7 ms | 1,843 / 1,920 KB |

Same copy and method as the points' table ("Points of interest"). The
margin makes the tiles 4 to 16% larger (16% at zoom 2, where the edge on
the meridian of Greenwich crosses France).

**Margin.** MapLibre Native (Android, iOS) draws a tile's features inside
the tile only: a dot of the next tile that spills over the edge is cut, and
the dots of the view of France showed a straight seam on the meridian of
Greenwich (audit of 2026-10-08). A dots tile therefore carries the dots of
its neighbours up to 8 px past its edge, at coordinates -8 to 519
(`DOTS_MARGIN`; the format allows coordinates outside the extent), the
points of a MultiPoint still row by row. The largest dot the app draws is
5 px of radius with a rim of 1.4 px (`MapLook.touchDotRadius`,
`dotStrokeWidth`), and a tile of zoom z is drawn at 1 to 2 screen pixels a
unit (zoom z to z + 0.99): a dot reaches at most 6.4 units past the edge, 8
with the pixel of antialiasing. MapLibre GL JS does not cut, so the web
draws such a dot twice, once per tile, one over the other: at the dots'
opacity of 0.95 the second one changes nothing visible.

**Tiles stored per version.** Since 2026-10-10 the publication that moves
the version also builds, in its transaction, the dots tiles whose dots it
changed (`place_dot_tiles`, the bytes of each tile holding a dot, each
built by a lateral subquery: the same build through an SQL function called
per tile ran 20 minutes in production without finishing, cause not
established), and marks the version
(`place_layer.dot_tiles_version`); the API reads a stored tile instead of
building it. Built at a request, the tiles of zooms 2 to 5 had grown to
255,000 dots and 1 MB each (3/4/2, eastern Europe) and took the production
database 1 to 7 s, past the API's 4 s: on 2026-10-09 at 22:44 UTC the API
answered 3/4/2 with a 503 (`a tile ran out of time z=3`), the warm-up of
that version had stopped on its first tile of zoom 2 at 22:40, and a first
launch of the Android app showed the east of Europe without places for 40
to 90 s (2026-10-10). The 6,000 tiles of zooms 2 to 9 (75 of them of
zooms 2 to 5) hold 25 MB in all on 2026-10-10; a publication rebuilds
the tiles it touched, every
one when the stored tiles are not those of the version before (the first
publication after one by a release that does not store them, which the
API meanwhile serves by building from `place_dots` as before). The
migration `20261010150120_place_dot_tiles_fill` builds them all once: 63.5 s
in production on 2026-10-10 (`_sqlx_migrations.execution_time`), 35 s for
the same statement run alone on that server before, the figure its header
gives. A publication that rebuilds every tile holds `place_layer` as long.
`lunaway-db/tests/place_tiles.rs` compares the stored tiles with a build
from the dots after each kind of write.

**Built ahead.** When the API sees a new version of the layer, it reads
every dots tile that holds a dot (listed from `place_dot_tiles`, or from
`place_dots` when they are not stored for the version), lowest zoom first,
into its memory, one at a time and only while another builder stays free
for the clients (`LUNAWAY_POI_TILE_CONCURRENCY`, 4, shared by both layers);
it stops when a newer version arrives. Before the dots were kept per version, a run
took the production database 21 to 26 s, and in the 24 hours before 04:30
UTC on 2026-10-08 three runs stopped on a tile that ran out of time
(`places layer: a tile built ahead ran out of time`); on the copy the tiles
of the list now build in about a second together. About 3 MB of memory (64 MiB per layer,
`LUNAWAY_POI_TILE_CACHE_MB`). `LUNAWAY_PLACE_TILE_WARM=0` turns it off.

**Logs.** Each tile the API builds logs one line with the layer, the zoom,
the time in milliseconds and whether it was built ahead, never its x and
y: `a tile built slowly` at the info level from 300 ms (`SLOW_BUILD` in
`tiles.rs`), `a tile built` at the debug level below. `sudo journalctl -u
lunaway-api | grep 'a tile built'` lists the slow ones; every build shows
with `RUST_LOG=info,lunaway_api::tiles=debug` in the unit, a change of
configuration made only for a measurement.

**The list.** `places(bbox, filter, first, after, near)`: with `near`
(rounded by the server to 0.01 degree before any use), the places come
nearest first from the GiST index (`ORDER BY geom <-> point, id`), the
cursor carries the last place's distance and id, and the viewport may be
any size, `first` (500 at most) bounding the page. The cursor's condition
is not served by the index: a page walks every place nearer than its
cursor, so the last page of Europe reads all of them. Measured on the same
database: the first page of 200 around Lyon over all of Europe in 10 ms, a
page 500 km out in 40 ms, `totalCount` of France (32 549 places) 51 ms and
of Europe (86 111) 38 ms, 30 ms with three filters. No cap on the count;
the statement timeout and the per-client budget bound the rest.
`overnight: []` and an empty group of `serviceGroups` are refused: they
would keep nothing.

**Version.** `place_layer` holds the version and the change feed's
position it covers. The conflation worker publishes a new version after a
run when a place was written since (`max(places.updated_seq)` past the
stored position, so no writer marks anything) and the last version is
older than `--place-layer-every-mins` (15 by default, the unit keeps the
default). `conflate --take-down` (and `takedowns replay`) publishes at
once after its commit, so a place taken down leaves every tile of the new
version; a device shows it until its TileJSON (60 s) names that version.
After a restore, the restored version number comes back with the dump: a
device may hold tiles of a later version built before the restore, until
the next version. The API's tile cache is keyed by version, as for the
points.

The migrations `20261008210000_place_layer_dots_seq` (the column, an
instant) and `20261008210100_tile_pyramids` fill `place_dots`,
`place_dot_members` and `poi_cluster_cells` and move the versions of both
layers, since the dots now reach past the edge and the clusters' cells
moved while a device keeps a tile of the current version a year. The fill
took 11.6 s on the copy of 2026-10-08 (200,961 places, 1,908,026 points);
production ran the same reads 0.9 to 14 times as long (above), so expect
from 10 s to under 3 minutes (an estimate, not measured). Meanwhile the
writers of points (imports, the fuel poller, the worker) and the
publications of both layers wait for it: it holds the POI writers' lock and
locks `place_layer` against its writers. The writers of places and the
API's reads do not wait; a place written during the fill is applied again
by the next publication. Between the commit and the restarts, a few
seconds, the API of the release before may build a tile of a new version
the old way (dots without the margin, clusters on the old cells), and the
worker of the release before may publish a version without updating the
tables: a device keeps such a tile until the next version, the next
publication by the new worker catches the dots up (`dots_seq`), and the
next version of the points counts their clusters again.

The rating of the filters (`r`) reached the dots in the same release:
`20261008230000_place_dots_rating` adds it to `place_dot_members` and
`place_dots`, cut to the steps of `DOTS_RATING_STEPS` in
`place_dot_sources` exactly as the dots tiles cut it when they read the
places, writes both tables again and moves both versions once more. It
runs after `20261008220000_place_filter_rating` in either order of
application: on a new database the dots' migrations (2100xx) come first,
on the production database of 2026-10-08 the rating's (2200xx) were
already applied and sqlx applies the older pending versions after them,
in order (`lunaway-db/tests/migrations_on_data.rs` runs both). On a copy
of production's places of 2026-10-08 (198,310 live, 98,524 rated) the
refill took 13 s (1,539,241 dots, 231 MB with the key), and a dots tile
with `r` took p95 45 ms at zoom 2, 13 ms at zoom 5 and 0.4 ms at zoom 9,
against 553, 192 and 2.8 ms for the query of the release before on the
same copy. A rating that changes moves the place in the change feed
(`place_ratings`, the summary of a review, a takedown), and the next
version of the layer carries it to the dots.

**Towns of the search.** With each new version, and whenever the table is
empty (a fresh database, the first run after the migration), the worker
rebuilds `place_towns` from the live places (`lunaway_db::towns::refresh`,
one statement: the roles have no TEMPORARY privilege): the towns
`searchAll(towns)` lists with every place they hold, one per commune by
its INSEE code, the homonyms of two departments apart. 4 to 5 s on
production on 2026-10-08 (200 961 places, 41 791 towns), writing only the
rows that changed.

**Compression.** The API gzips a tile when the client accepts gzip (every
browser and MapLibre Native do): measured through Caddy 2.11.7 in front of
the API, the zoom 3 tile went out as 63 123 B gzip instead of 107 112 B.
Caddy's `encode zstd gzip` leaves an encoded answer alone and does not
encode the vector tile type at all, so a client that accepts only zstd or
brotli gets the tile as is; zstd would save 0.5% on that tile and 7% on a
pin tile, not worth a C dependency in the API. `api.lunaway.net` answers
HTTP/2 (`curl --http2`: `2 200`) and advertises HTTP/3
(`alt-svc: h3=":443"`); the Mac's curl has no HTTP/3 to try it.

Caddy passes `GET`, `HEAD` and `OPTIONS` under `/places/` to the API with
a body of 1 KiB at most, 405 otherwise, and logs the zoom only
(`/places/{version}/{z}/x/y.mvt`), like `/poi/`; the API's own request
span masks the same (`tiles::loggable_path`).

### Europe, the regional packs, fuel and speed cameras

Installed on 2026-10-06 with the release of `main` at 38adf3d; the backend's
report is `plan/research/23-backend-europe-packs.md`, the deployment's
`plan/research/13-basemap.md` ("Déploiement Europe, carburant et radars").

**Imports.** France and 23 other extracts (`osm_extract::EUROPE`, 27.8 GB of
Geofabrik files on 2026-10-06), each read one at a time, each record stored
under the country of its position; a run retires only in the countries it
read, and in a country where it saw less than half of what is stored (10
records or more) it retires nothing and fails after storing the rest. The
product owner's decision on the download volume (2026-10-06): France every
day, the others once a week, which makes about 58 GB a week instead of 195
for a daily European run.

| when (UTC) | units | extracts | files, 2026-10-06 |
|---|---|---|---|
| daily 03:00, 03:45 | `lunaway-ingest-osm`, `lunaway-ingest-pois` | France (Monaco) | 5.1 GB |
| Monday 05:00, 05:45 | `lunaway-ingest-osm-europe@Mon`, `lunaway-ingest-pois-europe@Mon` | Germany | 4.9 GB |
| Tuesday | `...@Tue` | Netherlands, Belgium, Luxembourg, Austria, Switzerland, Liechtenstein | 3.5 GB |
| Wednesday | `...@Wed` | Spain, Canary Islands, Portugal, Andorra, Italy | 4.2 GB |
| Thursday | `...@Thu` | United Kingdom, Ireland, Denmark | 3.2 GB |
| Friday | `...@Fri` | Norway, Sweden, Finland | 3.0 GB |
| Saturday | `...@Sat` | Poland, Czechia, Slovenia, Croatia, Greece | 3.9 GB |

The groups are `infra/files/usr/local/share/lunaway/osm-extracts.env`
(`LUNAWAY_EXTRACTS_<Day>`, installed in `/usr/local/share/lunaway/`); the
`pipeline` step enables one timer pair per key and disables a day removed,
and `infra/verify.sh` checks that the groups hold every European extract
but France once. Sunday is left to the routing graph and the speed cameras.
A run downloads a file older than 20 hours (`--max-age-hours`), so a group
run the day after a European run by hand reads the cache. A run that stops
resumes after the last extract it stored, unless another run (France's
daily one included) ran in between: `osm-extract/runs/places.json` holds
one run.

**Germany.** On 2026-10-06 Geofabrik answered `germany-latest.osm.pbf` with
`307 Temporary Redirect` to `https://ftp5.gwdg.de/pub/misc/openstreetmap/download.geofabrik.de/germany-latest.osm.pbf`
(from the backend and from the Mac), and every other extract with a
redirect to a dated file on its own host. The importers follow a redirect
only to the host first asked or to `REDIRECT_HOSTS`
(`lunaway-ingest/src/http.rs`), which does not name that mirror, so the
European run stopped on Germany. Germany's first import came from
OpenStreetMap France's copy instead (`--mirror
https://download.openstreetmap.fr/extracts --extract germany`, a host the
code and `docs/data-sources.md` already allow; 5.9 GB, its cut wider than
Geofabrik's, the elements outside Germany left out by position). Until the
backend follows Geofabrik's mirror, Monday's group and the reading of
OpenStreetMap's cameras after a new graph (`--europe`, Germany sixth in the
list) fail on Germany; the status page shows it (Places imports).

**First run** (2026-10-06, 19:23 to 21:21 UTC, the release's binary on the
backend; `lunaway-admin`, memory sampled every 2 s in the unit's cgroup):

| step | records or points | duration | memory, peak |
|---|---|---|---|
| places, France (cache) | 17 100 records | 4 min 31 s | 269 MiB anonymous; the cgroup at its 2.5 GiB soft cap with page cache |
| places, Spain, Canary Islands, Portugal, Italy | 16 559 | 4 min 41 s | |
| places, the 18 others (Geofabrik) | 38 673 | 55 min 30 s, 38 min of it Poland's download (2.1 GB at about 1 MB/s; the others at about 50 MB/s) | 170 MiB anonymous |
| places, Germany (OpenStreetMap France) | 12 488, 198 pitches folded | 5 min 28 s (download 45 s, 120 MB/s) | |
| places, France again (its retirement after its neighbours) | 17 100 unchanged, 0 retired | 4 min 35 s | |
| points, 19 extracts | 1 040 675 points | 16 min 40 s | 1.07 GiB anonymous, 2.5 GiB with page cache |
| points, Germany (OpenStreetMap France) | 365 392 points (9 856 outside Germany left out) | 8 min 3 s | 2.01 GiB anonymous |
| points, France, Poland, Czechia, Andorra | 501 913 points, 1 retired | 10 min 10 s (France 6 min 11 s) | 1.55 GiB anonymous |
| speed cameras of OpenStreetMap, 23 extracts and Germany | 40 604 cameras (5 341 in France, none in Switzerland) | 10 min 28 s and 2 min 41 s | 137 MiB anonymous |
| full build of the zones and points | 37 685 cameras: 2 643 French zones, 26 092 points, 8 456 unplaced, 217 items retired | 7 min 38 s, 59 231 engine calls | 98.6 MB |

After it: 84 820 live OpenStreetMap records (17 100 in France and Monaco,
none without a country), 86 262 live places in 32 sync regions with places,
1 907 980 points of interest (none without a country); the database grew
from 1.0 GB to about 3.4 GB (`pois` 2.7 GB with 83 394 dead rows, `source_records` 144 MB,
`places` 109 MB). The worker
conflated the records as they came (`conflate` afterwards found nothing),
and evaluated the opening hours of the new points over its next runs.

**Packs.** `lunaway-packs.service` (`lunaway packs build`, the import role
and user, loopback only, `/srv/data/packs` writable, 768 MB soft cap, 1 GB)
after each conflation that follows a places import, and daily at 06:30 UTC.
`/srv/data/packs` is `lunaway-ingest:caddy` 2750: the packs come out 0640,
readable by Caddy and nobody else. The builder reads the sync epoch for the
packs' cursors, which no migration of 38adf3d grants the import role:
`GRANT SELECT ON sync_epoch TO lunaway_ingest` was applied by hand on
2026-10-06 (the first build failed with `permission denied for table
sync_epoch`), and `test-grants.sh` expects it until a migration carries it.
First full set: 34 regions, 86 111 places, 9.15 MB gzip (Germany 1.41 MB the largest), 105 MB decompressed, 198.9 MB memory peak.
Caddy serves `/packs/places/` on `api.lunaway.net` (see "The domain"); the
previous pack of a region stays until the next build. A takedown is
`lunaway-admin packs build --region <code> --takedown`
(`docs/region-packs.md`). Nothing to back up: each build writes the packs
again. No shared cache may sit in front of `/packs/` without a purge.

**Fuel along a route.** `Query.fuelAlongRoute` measures detours with the
engine's matrix (`POST /sources_to_targets`): `infra/routing/valhalla.json`
serves the action with `max_matrix_distance` 60 000 m for `auto` (a test of
the API fails when the action is served with more; on 2026-10-06 the engine
refused a pair from Lyon to Marseille with error 154, "Path distance
exceeds the max distance limit: 60000 meters"). Its quota is
`LUNAWAY_QUOTA_FUEL_ROUTE` (10 every ten minutes, the default). The fuel
poller fills `fuel_price_days` at each run, 30 days kept.
`Query.alongRoute` (places and points of interest along a route) measures
its detours the same way, one page at a time; its quota is
`LUNAWAY_QUOTA_ALONG_ROUTE` (20 at once, then one every 15 s, the
default).

**Speed cameras** (`docs/speed-cameras.md`). `lunaway-enforcement.timer`
(05:30 UTC) starts `lunaway-enforcement.service` (`lunaway enforcement
build`), which pulls in `lunaway-cameras.service` (`lunaway ingest cameras
--refresh`, the official lists) first and runs whether a list failed
or not. After each new routing graph, `lunaway-routing-refresh` queues
`lunaway-enforcement-full.service` (`enforcement build --full`), which pulls
in `lunaway-cameras-osm.service` (`lunaway ingest cameras-osm --europe`,
without `--refresh`: the cached extracts, at most a week old, so the
download plan holds). The builds load `LUNAWAY_ZONE_SECRET` from
`/etc/lunaway/zone.env` (see "Private settings") and call the engine on
loopback; `/var/lib/lunaway-enforcement/built` dates the last build that
succeeded. First runs: the lists in 6 s (France 3 664 rows, 3 204 cameras,
458 routes of the radar cars left out, 2 within 1 km of Switzerland not
stored; Poland 623, Luxembourg 39, Catalonia 230, Norway 461), 49.6 MB; the
daily build in 12 min 4 s, 34 473 engine calls on the France graph, 2 809
French zones, 891 camera points (Poland, Catalonia, Luxembourg), 751
cameras unplaced (Norway's zones need a graph of Norway), 23.9 MB;
the full build after OpenStreetMap's cameras in 7 min 38 s, 98.6 MB.

**The first build after the review of the rules of 2026-10-09** runs by
hand with `--allow-retire` (`sudo lunaway-admin enforcement build --full
--allow-retire`), then the timers take over. Italy turns from zones to
points and Andorra from off to points: an Italian zone becomes its point in
its own row, under the same id (an update, which the phones fetch, never a
retirement). What goes: the Greek points the engine cannot turn into zones
(the graph does not cover Greece), which may pass a tenth of the items, and
the guard refuses that without the flag
(`the_review_of_the_rules_retires_only_what_it_cannot_build`). The items of
the Catalan list, which is suspended (`docs/data-sources.md`, "Speed
cameras"), are retired by the migrations themselves. Every zone
is also written again with the neutral category (`DANGER_ZONE`), so every
phone fetches the whole set once.

**Disk.** On 2026-10-06 after the first run, the data volume held 34.1 GB of
157 GB (115 GB free): 28.8 GB of extracts (Germany from OpenStreetMap
France; Geofabrik's Germany will add 4.9 GB once followed), 5.1 GB of
PostgreSQL, 16 MB of packs. No resize: the status page turns red at 80%.

### The external community feed

The source `extcom` (`docs/feeds.md`): a partner's community spots,
reviews and photos under a written agreement, shown as "Source
communautaire externe". Its producer, a crawler kept in a private
repository, runs on the ops server; the backend receives the feed, checks
it, imports it and serves it. The partner is named nowhere in this
repository, its photo host included (`/etc/lunaway/extcom.env`, see
"Private settings").

**Drop.** The producer pushes each feed over the private network as
`extcom-drop`, a backend account with a locked password and one key,
accepted from 10.42.0.3 only and forced to `rrsync -wo
/srv/data/extcom-inbox` (`restrict`, and `AllowUsers
extcom-drop@10.42.0.3` in `/etc/ssh/sshd_config.d/13-extcom-drop.conf`):
write only, no read, no shell. The account owns the inbox, so what lands
there is the producer's to shape; the import trusts none of it (names,
links and checksums are checked, below). A replacement of a file was
refused when the producer's deployment tried it on 2026-10-07 (rsync
3.5.0: `delete_file: unlink(4) failed: Operation not permitted`), so each
push takes a new name. The account, its key, that drop-in and the
tmpfiles rule `/etc/tmpfiles.d/extcom-inbox.conf` (the inbox
`extcom-drop:lunaway-ingest` 2750, files removed after 4 days) come from
the producer's private deployment, not from `infra/`: the `harden` and
`ops-access` steps leave them alone, and the `pipeline` step warns when
the inbox's owner, mode or tmpfiles rule differ. The imports' user reads
the files (0640), nobody else. A feed arrives as `extcom-<UTC
stamp>.jsonl.gz`, then its checksum file `<name>.sha256` (`<64 hex>
<name>`).

**Import.** `lunaway-ingest-extcom.path` starts
`lunaway-ingest-extcom.service` when a file lands in the inbox (a file
written, then renamed, started it twice on 2026-10-07), and
`lunaway-ingest-extcom.timer` hourly, for a file that landed while the
service ran. The unit's condition (`lunaway-extcom-inbox pending`) stops
it at once unless a feed waits: the newest feed whose checksum file
exists, newer than the name kept in `/srv/data/ingest/extcom-inbox.last`;
a symbolic link is no feed. A complete feed replaces everything before it:
of the feeds that wait, the newest complete one is imported, then the
deltas after it (`complete: false` in their header, or a header that
cannot be read), in order; when none is complete, every one in order. The
producer sends complete feeds today (the header of its test feed, and its
report). `lunaway-extcom-inbox import` reads the checksum file (it must
name the feed), compares the
SHA-256, and runs `lunaway ingest extcom --file` with the agreement's
settings, holding `/srv/data/ingest/extcom.lock`. A mismatch or a failed
import fails the unit and keeps the name of the last feed imported, so the
next hourly run takes the same feed again: the importer resumes after its
last stored batch, except when the half rule refused the removals (below),
where it clears its progress first, so every retry reads the whole feed and
fails the same way until a newer feed comes. A feed dated more than an hour
ahead of the server's clock, or a recorded last feed newer than every
feed of the inbox, fails the condition itself (exit 255) rather than
skipping in silence. A failed import, or a failed purge of its photos,
turns the status page's "External community feed" check red (the health
probe's `extcom`), which the Mac's nightly job turns into the GitHub
issue `ops: alerte`; `systemctl status lunaway-ingest-extcom` and its
journal say why. The check stays red until a run of the unit succeeds,
retries included (`/var/lib/lunaway-unit-result/extcom-import.result`).
Fixed another way (the feed imported by hand, the inbox emptied), the
record goes with `sudo rm
/var/lib/lunaway-unit-result/extcom-import.result`; switching the feed
off removes it. The unit sees of
`/srv` the inbox, read-only, and the import cache, reaches PostgreSQL on
loopback and nothing else, and is capped at 1 GiB. A file named otherwise
(a test feed) is never taken: import it by hand with `lunaway-admin ingest
extcom --file`.

**Merge, packs, tiles.** After an import, and only then, the unit starts
`lunaway-conflate.service` (which starts `lunaway-packs.service` after
it) and `lunaway-extcom-purge-media.service`. This is an `ExecStartPost=`
line: a condition that stops the unit skips it, where `OnSuccess=` would
still fire (measured on the backend's systemd 257). The conflation worker
also takes flagged records within 5 minutes, and publishes a new version
of the places layer at most every 15 minutes. A region pack that carries
values of the source says so in its licence (`docs/data-sources.md`,
"Licences of the places database"); the partner's reviews, ratings and
photos are in no pack and no tile.

**Photos.** None is downloaded at import. The API's proxy
(`/external-photos/`, see "Photos") fetches one when a device first asks
for it. The API's unit refuses the private, shared and link-local ranges
(the private network, the metadata service); nftables lets its user open
HTTPS and DNS connections only (`/etc/nftables.d/lunaway-api-egress.nft`,
installed by the `api` step); the proxy itself holds every URL and
redirect to the hosts of the agreement in force, resolved to public
addresses only, at most 5000 downloads a UTC day, all clients together,
and 300 a day for one client (`docs/feeds.md`).
Those hosts are a column the import writes (`source_agreements`), so the
import role decides where the API may download from. A stored photo is a file under
`/srv/data/media/photos/`, backed up like an upload (encrypted copies, see
"Backups and restore").

**Purge.** `lunaway-extcom-purge-media.service` (`lunaway extcom
purge-media --yes`, as `lunaway-api` with the API's role, which wrote the
files; it sees `/srv/data/media` only and reaches PostgreSQL on loopback)
runs after each import and daily at 05:10 UTC: it removes the files of the
retired photos that no other photo uses, then their rows; then it forgets
the files of the live photos made without cutting the band of the source's
mark (`docs/feeds.md`, "What the product shows"): their rows are emptied,
the files no row names any more removed, and the proxy makes them again,
cut, at their next view. The encrypted copies of a removed file leave the
backups within 29 days, as for any photo.

**Deletions passed on.** What a feed removes is removed at its import: a
spot absent from a complete feed (unless the feed lists less than half of
the spots stored: then nothing is removed and the import fails, for a
person to look), a line marked `"deleted": true`, a review or a photo
absent from the list of its spot's line (a line without the list leaves
them as they are). The spot's record is emptied, its reviews and
rating deleted, its photos retired; the conflation takes it off its place,
the change feed hands the change to the devices, the next pack of its
region is built without it, and the purge removes the photo files.

**Erasure of one author**, for a request the partner forwards:

```bash
sudo lunaway-admin extcom erase-author - --yes   # then paste the id: it is not echoed
sudo lunaway-admin extcom purge-media --yes      # or the next daily run
```

The id comes on standard input: sudo writes a command line to the journal,
which keeps it for weeks, and a shell keeps its history. It is an argument
of the CLI only while that runs (a few seconds, visible to `ps`). The
command first waits for an import of the feed that runs (30 minutes at
most), before the id is an argument of anything, then takes the import's
lock without waiting, so that it never removes a cached feed under a
running import. Each batch of an import reads the erased authors again
under the writers' lock, which the erasure takes too: the reviews and
photos an erasure deletes stay deleted even when it runs beside an
import without this command (the removal of the cached feeds is then the
part the lock no longer guards). It deletes the author's reviews, retires
their photos, removes the feeds kept in the import cache, and keeps the
SHA-256 of the id so that later feeds do not bring them back; the purge
removes the files. What still holds the author's texts afterwards, and for
how long: the feeds in the inbox until tmpfiles removes them (4 days; `sudo
rm` of every feed of the inbox, by literal names, shortens it: removing the
last one imported alone, while older ones stay, makes the import's
condition fail every hour until they expire), the dumps (29 days at most),
and the producer's working copy on the ops server until it reads the list
of erased authors (below): before its next feed, so within 3 hours while it
reads pages, at its next daily run otherwise.
A dump restored from before the erasure brings the reviews back and holds
no trace of the erasure: apply the erasures received since that dump
again. The producer keeps every hash it has read, so its feeds still leave
the author out meanwhile.

**Erasures passed on to the producer.** After each erasure (`lunaway-admin
extcom erase-author --yes` starts it) and hourly,
`lunaway-extcom-erasures.service` writes the SHA-256 of every erased author
id, one per line and nothing else, into
`/srv/data/extcom-erasures/erased-authors` (`lunaway extcom erasures`, the
import role, loopback only, the file replaced in one rename). The
directory is the imports' user's, setgid `lunaway-pull`, the file 0640: the
only reader is `lunaway-pull`, through a key of the producer's own, accepted
from 10.42.0.3 only and forced to `/usr/local/sbin/lunaway-extcom-erasures`,
which prints the file whatever the client asks (no shell, no forwarding:
`restrict`). The producer's private deployment makes that key on the ops
server and leaves its public half in
`/etc/lunaway-ops/extcom-erasures_ed25519.pub`, which `infra/configure.sh
backend` reads; the `ops-access` step installs it. The producer reads the
list when a run starts and before each feed, keeps every hash, deletes
those authors' reviews from its working copy, drops them from every page
it reads later, and removes the feeds it kept on disk; its feeds never
carry them again. The backend still never connects to the ops server.

**First import** (2026-10-07, plan/research/67-extcom-production.md): the
producer's regional test feed (`test-ardeche-extcom.jsonl.gz`: 3 287 spots,
32 979 reviews, 2 623 rating summaries, 6 770 photos, every photo on the
configured host), imported by hand at 22:54 UTC in 35 s, memory peak 51
MiB (the cgroup's `memory.peak`, 53 469 184 bytes); then `lunaway-admin conflate` in 13 s: 2 828 places created, 459
updated, 2 absorbed; 459 of the records merged with another source's, 128
left alone with a pair in review, 2 700 alone. The packs of the three
regions concerned, rebuilt in 34 s with all the others: FR-ARA from 2 947 to
5 299 places (513 to 1 770 KB gzip), FR-OCC from 3 572 to 3 966, FR-PAC from
1 515 to 1 595.

**First full feed** (2026-10-08, plan/research/69-extcom-suites.md): 124 319
spots across Europe (79 356 in France), a delta (`complete: false`), 72 MB
compressed. Its first import (00:50 UTC) was cut at line 91 501 when
unattended-upgrades restarted PostgreSQL (01:36:47); the hourly retry
resumed there and ended at 02:18:54. The photos' retirement then read the
whole photos table at each line; with it split in two indexed statements,
the same feed imports again in 278 s, a delta of 10 607 spots (271 705
reviews, 36 031 photos written) in 128 s. The regional packs grew from
12.0 to 40.6 MB in all, from 5.6 to 24.4 MB for France, which the app
downloads whole at its first launch.

## Status page

Gatus on the ops server checks the backend from another server in another
datacenter, every one to fifteen minutes, and serves the result at
`https://status.lunaway.net/`, through Caddy with automatic TLS. Its API, `/api/v1/endpoints/statuses`, is what the
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
| public | Regional packs manifest | `{ regions { code pack { url bytes } } }`: more than 30 regions, the first (FR-ARA) naming a pack under `https://<api host>/packs/places/` of more than 10 000 bytes |
| public | Routing | `{ routing { available graph { builtAt } } }` answers `available: true`: an active graph, and the engine answers |
| public | Witness route | every 15 minutes, a 3.3 m motorhome on Rue Maurice Utrillo in Limoges: `status OK` and more than 1000 m, round the 2.7 m bridge (four routes an hour, against a quota of 30 every ten minutes) |
| public | Road events (DIR feed read) | `roadEventSources`: the DIR, first in the list, read less than 15 minutes ago |
| public | Road events (DiaLog read) | DiaLog, second, read less than 45 minutes ago |
| public | Road events feed | `roadEvents(first: 1)` answers a cursor within 3 s |
| public | Addresses (France) | every 10 minutes, `searchAll` of "20 avenue de segur 75007 paris" (a ministry): complete, the first address "20 Avenue de Ségur", within 2 s (the Géoplateforme through the backend's Caddy) |
| public | Addresses (Europe) | the same for "unter den linden berlin" near Berlin: complete, the first address in Germany (photon@europe) |
| public | Addresses (Morocco) | the same for "rue de fes rabat" near Rabat: complete, the first address in Morocco (photon@morocco) |
| backend | Conflation worker | the probe: `lunaway-conflate-worker` active, its queues measured less than 5 minutes ago, nothing waiting there for 15 minutes |
| backend | Photo backup | the probe: the encrypted copy of the photos brought up to date less than 26 hours ago |
| backend | Account deletion journal backup | the probe: the encrypted copy of the account deletion journal written less than 3 hours ago (hourly) |
| backend | Takedown journal backup | the probe: the encrypted copy of the takedown journal written less than 3 hours ago (hourly) |
| backend | PostgreSQL | the health probe reports `pg_isready` on loopback |
| backend | Data volume | mounted, under 80% full; root disk under 80% (it holds the routing graphs) |
| backend | Tile volume | mounted, under 80% full once the planet builds not served are counted as free (the refresh removes them first; after a refresh the volume itself is about 90% full, by design) |
| backend | Nightly dump | succeeded less than 26 hours ago, no failure recorded after it |
| backend | Basemap build | the tile volume is mounted and the planet served is less than 35 days old (a refresh failed otherwise) |
| backend | Offline packs | the probe: the packs' manifest names one pack per outline, its build is less than 35 days old and is the planet served (or the planet switched less than a day ago) |
| backend | Fuel prices | the probe: the fuel price feed was stored less than 2 hours ago (eight runs of `lunaway-ingest-fuel` in a row failed otherwise) |
| backend | Routing graph | the probe: `valhalla.service` active, serving a graph built less than 10 days ago (weekly build, daily refresh) |
| backend | Places imports (France and Europe) | the probe: France's OpenStreetMap places read less than 30 hours ago, every other country's less than 8 days ago (`imports.json`), and no failed unit among the places and points imports, `lunaway-packs`, `lunaway-cameras*` and `lunaway-enforcement*` (a truncation guard that refuses a country fails its import) |
| backend | Regional packs of places | the probe: no sync region has waited more than two days for a pack with its changes, and at least one pack exists |
| backend | Points layer publication | the probe: no change of the points layer has waited more than 8 hours for its version (published every 6 hours) |
| backend | Speed camera lists | the probe: the seven official lists each checked less than 30 hours ago (each downloaded at its own pace, its cached copy read in between) |
| backend | Danger zones build | the probe: the zones and points built less than 30 hours ago (`/var/lib/lunaway-enforcement/built`) |
| backend | External community feed | the probe: neither `lunaway-ingest-extcom` (a checksum that does not match, a refused or failed import, a feed dated in the future) nor `lunaway-extcom-purge-media` nor `lunaway-extcom-erasures` (the list of erased authors its producer reads) is failed, nor did its last finished run fail (`/var/lib/lunaway-unit-result/*.result`, written by `lunaway-unit-result` from each unit's `ExecStopPost=`: a failed import retried hourly reads "activating" while the retry runs) |
| ops | Ops replica volume | the ops server's own probe, over SSH on its loopback: the replica volume mounted and under 80% full, its root disk under 80% |

The ops check reads the ops server's own disks the same way: Gatus can
only check what answers over the network, so its probe key is also accepted
by the ops server's `lunaway-pull` account, from 127.0.0.1 and ::1 only,
forced to `/usr/local/sbin/lunaway-ops-health` (`infra/server/ops-replica.sh`).

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

What the page checks are the public names of `infra/lib.sh` (each can be
overridden in the private settings), rendered by `infra/configure.sh ops
ops-status`:

- `LUNAWAY_API_HOST`: the API's name, `api.lunaway.net`.
- `LUNAWAY_WEB_URL`: the website and web app, `https://lunaway.net`.
- `LUNAWAY_TILES_URL`: the basemap's base URL, `https://tiles.lunaway.net`.
- `LUNAWAY_STATUS_DOMAIN`: the page's own name, `status.lunaway.net`, the
  only name Caddy serves on the ops server.

Every backend check opens one SSH connection to the backend, and the
hourly ones start with the others: 15 connections within about 20 seconds.
The backend's limit of 10 new SSH connections a minute per source dropped
the last two every hour until 2026-10-07, when the ops server's private
address, arriving on the private interface, was exempted from it
(`infra/files/etc/nftables.conf`), as it is from fail2ban.

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
   no failure recorded after the last success. What is older than 29 days
   is dropped at the start of the run, before the pull, and again after
   it, so no dump outlives an account deleted after it by more than 30
   days even on a night the pull fails; the job also runs at the start of
   the session (`RunAtLoad`), after the Mac was off. What comes from the
   ops server (markers, names) reaches the issue only when it has the
   expected form;
3. reads every check of the status page;
4. checks the Mac itself: at least 50 GB free on its disk, and, once the
   weekly routing build is installed (`infra/ops/mac-routing/`), that its
   last run did not fail, that one succeeded less than 8 days ago, and that
   the hourly sweep did not have to delete a leftover build server in the
   last 24 hours;
5. when anything failed, opens the GitHub issue `ops: alerte` on
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
systemctl list-timers 'lunaway*'             # dump, imports, conflation, retention, basemap refresh and packs (backend), replica (ops)
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

The `lunaway.net` sites are in `infra/caddy/lunaway.net.caddy`, enabled on
2026-10-06 at about 20:08 UTC (`infra/enable-domain.sh`; A and AAAA records
DNS only at Cloudflare, `status.lunaway.net` on the ops server; Let's
Encrypt certificates for the five names, valid until 2027-01-04):

| address | served from | notes |
|---|---|---|
| `api.lunaway.net` | lunaway-api | `/health`, `/graphql`, `/upload`, the tiles under `/poi/` and `/places/`; `/media/` below; anything else 404 |
| `api.lunaway.net/media/` | `/srv/data/media` | a present file is served with a one-year immutable cache and a sandboxing CSP; a missing file or a directory is a plain 404, never listed |
| `api.lunaway.net/packs/places/` | `/srv/data/packs/places` | the regional packs of places (`docs/region-packs.md`): only a name of the form `<region>-<seq>-<12 hex>.sqlite.gz`, written exactly so in the request (no `//`, `./`, percent-encoding or query string), a year of immutable cache, byte ranges, CORS for `https://lunaway.net`; GET, HEAD, OPTIONS; the work directory, a listing or any other name is a 404; logged as `/packs/places/[pack]` |
| `lunaway.net/` | `/srv/lunaway/site` | website, script-free except `/account/delete` (its own CSP); `/privacy`, `/account/delete`, `/about` map to `privacy.html` or `privacy/index.html`; hashed assets cached a year, the rest five minutes |
| `lunaway.net/app/` | `/srv/lunaway/web` | Flutter web build; the app's routes (`/app/place/42`) fall back to `/app/index.html`, a missing file (under `assets/`, `fonts/`, `canvaskit/`, `icons/`, or any name with an extension) is an empty 404, so a fallback font Flutter asks for never gets HTML; revalidated on every load; its CSP allows `tiles.lunaway.net` as the only tile host |
| `www.lunaway.net` | | permanent redirect to `https://lunaway.net` |
| `tiles.lunaway.net` | pmtiles serve, `/srv/tiles` | the basemap (see "Basemap") |

`infra/tests/caddy-layout.sh` runs this configuration in the
Caddy release the servers run (2.11.7: native binaries pinned by hash on
macOS and Linux x86_64, bound to loopback; the Docker image with
`LUNAWAY_CADDY_DOCKER=1`), with plain HTTP and test roots, and checks each
route and header, and that the logs mask client addresses, tile
coordinates and photo paths, and that the main Caddyfile alone (the
domain not enabled) holds no site; run it after editing `infra/caddy/`.
Once the A and AAAA records of the four names point at the backend (DNS
only, not proxied, so the HTTP-01 challenge reaches Caddy):

```bash
infra/enable-domain.sh              # checks DNS from 1.1.1.1 and 8.8.8.8, enables, waits for the certificates
infra/enable-domain.sh --disable
```

Caddy uses Let's Encrypt only (no fallback CA), so a CAA record
`0 issue "letsencrypt.org"` on `lunaway.net` matches it. The API answers
CORS requests from `https://lunaway.net` only (the web app's origin);
`LUNAWAY_DEV_CORS=1` in its environment adds pages served from
`localhost` and `127.0.0.1`, for development, never on the server. Enabled
on 2026-10-06: the status page, its checks and `infra/verify.sh` use the
public names, and the API names `https://api.lunaway.net` in the points'
TileJSON and the packs' URLs. The photos' rows hold paths relative to the
media root, so no row changed.

Until 2026-10-07 each server also answered a provisional name derived from
its IPv4 address on sslip.io. They are retired: no script, template or
check uses them (`infra/deploy-api.sh` checks `https://api.lunaway.net`,
`infra/fdroid/publish.sh` reads the repository back from
`https://lunaway.net/fdroid/repo`, the Mac's nightly job reads
`https://status.lunaway.net`), Caddy holds no site for them, so HTTPS to
them fails at the TLS handshake, and `infra/verify.sh` checks that. Port 80
still answers any name with Caddy's redirect to HTTPS, which then fails the
same way. On a new backend nothing is served until `infra/enable-domain.sh`.

### Deploying the landing site and the web app

```bash
python3 tool/site/build.py                 # regenerates infra/web/site/ from tool/site/src/
infra/deploy-web.sh site infra/web/site     # index.html at the root
infra/deploy-web.sh app --build           # build_web.sh, fvm flutter build web --base-href /app/ --no-web-resources-cdn, then deploy
LUNAWAY_DRY_RUN=1 infra/deploy-web.sh app --build   # the same build and checks, nothing uploaded
infra/deploy-web.sh app app/build/web     # an existing build
```

Each deploy lands in `/srv/lunaway/releases/<site|app>/<date>-<commit>/` and
switches the `/srv/lunaway/site` or `/srv/lunaway/web` symlink. Without
`--no-web-resources-cdn` the app would load CanvasKit from `www.gstatic.com`,
which the CSP refuses. A previous release comes back with
`sudo ln -sfn /srv/lunaway/releases/app/<name> /srv/lunaway/web` on the server.
The guidance engine's WebAssembly (`app/web/lunaway_nav/`) is not committed:
`--build` makes it from source first (`app/packages/lunaway_nav/tool/build_web.sh`,
which needs the `wasm-bindgen` CLI of the crate's `Cargo.lock`), and the
script refuses an app build that lacks it, since such an app runs but cannot
guide.

The app is built with `--wasm`: Chrome runs the dart2wasm build with skwasm,
every other browser (and one without WasmGC) the dart2js build with
CanvasKit, both in the same release. Before uploading it, the script runs
`app/tool/web/fingerprint.py --compress`: the startup files (the Dart
program, CanvasKit, MapLibre GL JS, the page's scripts) get names that carry
their digest (`name.<12 hex>.js`, `canvaskit-<12 hex>/`), listed in the
build's `hashed.txt`, which `/app/` serves `immutable` for a year, and every
text or WebAssembly file gets a Brotli copy (`.br`, quality 11) that Caddy
serves to browsers that accept it. `infra/server/install-web.sh` copies the
renamed files of the last twenty app releases into the new one, so a page
that a service worker still serves from an older build finds them. Pointing
the symlink back at an older release carries nothing: a browser whose worker
already serves a newer build then loads that build's renamed files from its
HTTP cache, or deploy the older commit again instead. On the web, starting
offline rests on the HTTP cache for the renamed files. Then the
script writes the service worker, `lunaway_sw.js`, with
`app/tool/web/service_worker.py`: it names every other file of the build and
a digest of them all, so a second visit is served from the browser's cache
without a round trip per file (those files are served `no-cache`, their
names carrying no content hash); the renamed files it leaves to the HTTP
cache, where the browser also keeps their compiled code. A new deploy is a new
worker: browsers install it in the background at their next visit and use
the new build from the one after. The worker also answers the TileJSON of
the places, the points of interest and the basemap from its copy while it
fetches a fresh one, so a place taken down may show one visit longer on the
web. The worker of a build never comes out by deleting `lunaway_sw.js`:
browsers keep the worker they have when its file answers 404. To take it out
of every browser, deploy a build after `python3
app/tool/web/service_worker.py --remove <build dir>`, whose worker empties its
caches, unregisters itself and reloads the pages it held.

To try a build against the real API before deploying it, build it with
`--dart-define=LUNAWAY_API_URL=http://127.0.0.1:18793` and serve it with
`app/tool/web/serve_csp.py --api https://api.lunaway.net/graphql`: the
production headers, the API's paths forwarded, the API's address in its
answers given as the local one. `app/tool/web/marks_photos_check.py --serve
app/build/web` runs the route preview and a guidance in Chromium, Firefox
and WebKit and fails when the route maps fetch no photo for their marks;
`--url https://lunaway.net/app/` runs it on production. Two other setups
show no photo for reasons production does not have. A build on a local
origin that asks `api.lunaway.net` itself gets no answer at all: the API
answers browsers from `https://lunaway.net` only (CORS, the GraphQL
included). A build whose API is the local address, served by a proxy that
passes the API's JSON as it is, receives photo URLs on `api.lunaway.net`,
which the app refuses to fetch: it fetches a photo from its own API's
address only (`ImageFetcher.accepts`).

## Backups and restore

Each nightly dump in four places; the plaintext stays on the backend's
data volume, every other copy is encrypted:

| copy | where | kept |
|---|---|---|
| plaintext dump and roles | backend data volume, `/srv/data/backups/postgresql/` (postgres, 0700) | 7 |
| age-encrypted, on the root disk | backend, `/var/backups/lunaway/postgresql/`, captured by Hetzner's daily server backup (7 images, taken between 06:00 and 10:00 UTC); until 2026-10-07 these were plaintext copies, and the images taken before then hold them for 7 more days | 3 |
| age-encrypted | backend `/srv/data/backups/offsite/` (7), pulled at 01:15 UTC into the ops server's volume in nbg1 (14 days), pulled at 04:30 local into the Mac's `~/Backups/lunaway/` (29 days); both prune before they pull, so a failed pull leaves no copy past its days | |
| photos, age-encrypted | backend `/srv/data/backups/offsite/media/`, the ops server's `/srv/data/backups/postgresql/media/`, the Mac's `~/Backups/lunaway/media/` | as long as the photo exists, then until 26 days after its deletion date |
| account deletion journal | backend `/srv/data/account-deletions/` (outside the dumps: one file per UTC day, account ids and times only; `lunaway-api:lunaway-deletions` 2750), age-encrypted every hour at :55 into one file, `/srv/data/backups/offsite/account-deletions/account-deletions.jsonl.age` (`lunaway-deletions-offsite.timer`), written again at each run; pulled with the dumps at 01:15 UTC into the ops server's and then the Mac's `account-deletions/`, where each pull replaces it | 45 days at most on the server (`LUNAWAY_DELETION_JOURNAL_DAYS`, 31 at least, a day's last lines going up to a day sooner), longer than any dump copy; up to a day more on the ops server and the Mac, until their next pull |
| the F-Droid keys, age-encrypted | backend `/srv/data/backups/offsite/fdroid-keys-<stamp>.tar.age`, the ops server's replica, the Mac's `~/Backups/lunaway/` | every copy, never pruned (see "F-Droid repository") |
| takedown journal | backend `/srv/data/place-takedowns/` (outside the dumps: one file per UTC day, places' ids, date, reason code and the keyed hashes of the cells only; `lunaway-ingest:lunaway-takedowns` 2750), age-encrypted every hour at :55 into one file, `/srv/data/backups/offsite/place-takedowns/place-takedowns.jsonl.age` (`lunaway-takedowns-offsite.timer`), written again at each run; pulled with the dumps into the ops server's and then the Mac's `place-takedowns/` | for ever on the server (a few lines a year; the cells must outlive every restore); each pull replaces the copies |
| the takedown secret, age-encrypted | backend `/srv/data/backups/offsite/takedown-secret.env.age` (root:lunaway-pull 0640, written by the `pipeline` step when missing), the ops server's replica, the Mac's `~/Backups/lunaway/` | never pruned |
| the routing graph's signing key, age-encrypted | backend `/srv/data/backups/offsite/routing-signing-key-<stamp>.age` (written by `infra/ops/mac-routing/install.sh backup`), the ops server's replica, the Mac's `~/Backups/lunaway/` | every copy, never pruned |
| the danger zones' secret, age-encrypted | backend `/srv/data/backups/offsite/zone-secret.env.age` (root:lunaway-pull 0640, written by the `pipeline` step when missing), pulled with the dumps into the ops server's replica and the Mac's `~/Backups/lunaway/` | never pruned (the pulls prune dumps by name) |
| the external community source's settings, age-encrypted | backend `/srv/data/backups/offsite/extcom-env.age` (root:lunaway-pull 0640, written again by the `pipeline` step whenever `/etc/lunaway/extcom.env` is newer), pulled with the dumps into the ops server's replica and the Mac's `~/Backups/lunaway/` | the latest, replaced at each pull |

Sizes: a dump of the database with Europe takes 351,238,506 bytes
(`pg_dump --format=custom --compress=zstd:6`, 62 s, 2026-10-07; 40 MB with
France alone, 2026-10-06), for a database of 4.4 GB on disk. The ops
server's volume (20 GB, 19.8 GB free on 2026-10-07) holds 14 of them, 15
during a pull, about 5.3 GB: it fills when a dump reaches 1.3 GB. The Mac
holds 29 (30 during a pull), about 10.5 GB, with 470 GiB free. The status
page watches the ops volume (Ops replica volume, red at 80%); the nightly
job fails under 50 GB free on the Mac.

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
- A dump restored would bring back the accounts deleted after it was
  taken. Every deletion (`deleteAccount`, the recovery-code page,
  `lunaway accounts delete`) is first written and synced to the deletion
  journal, outside the database (`LUNAWAY_DELETION_JOURNAL`, the API and
  `lunaway-admin accounts` both write there); the API refuses a deletion
  it cannot journal (`UNAVAILABLE`), and refuses to start when it cannot
  write the journal's directory. After a restore, `lunaway accounts
  replay-deletions` deletes again, exactly as `deleteAccount` did, every
  account the journal names that the restored database holds. The journal
  on the data volume covers every restore that keeps the volume (a bad
  migration, a corrupted database); when the volume itself is lost, the
  off-site copy holds the deletions up to its last pull by the ops server
  (01:15 UTC): a deletion made after it comes back with the dump, as
  everything written after the dump is lost.
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

Then apply again the account deletions made since the dump. Once the
restored database is the one the API's `DATABASE_URL` names, with the API
and the conflation worker stopped (the worker would otherwise publish a
pending submission of an account deleted after the dump) and the photos
restored (below), so that the replay also removes the photo files of the
accounts it deletes:

```bash
sudo systemctl stop lunaway-api lunaway-conflate-worker
sudo lunaway-admin accounts replay-deletions --dry-run   # the accounts the journal names, still in this database
sudo lunaway-admin accounts replay-deletions
```

The replay refuses a journal that names no deletion (`JournalError::Empty`):
on a new data volume the API's first start leaves only an empty file for
the day, and replaying that would bring back every deletion since the dump.
`--allow-empty` accepts it when the journal really is empty (no deletion in
45 days).

Then the takedowns made since the dump, still with the API and the worker
stopped: the import role puts back the cells of every journaled takedown,
conflates what waits, and takes down again every journaled place the dump
brought back; the API's role deletes their community content; the packs of
their regions are built again. `lunaway-admin replay-takedowns` runs the
three in order:

```bash
sudo lunaway-admin replay-takedowns --dry-run   # the places the journal would take down again
sudo lunaway-admin replay-takedowns             # takedowns replay, moderation purge-taken-down --yes, packs build --region <code> --takedown
sudo systemctl start lunaway-api lunaway-conflate-worker
```

A line "... is merged with ... which the journal does not name" asks for a
look by hand: an old merge may have joined a neighbour to a place taken
down, and nothing of that family was emptied. Like the deletions, the
replay refuses a journal that names no takedown unless `--allow-empty`
(no takedown was ever made).

When the data volume was lost too, put the journal back from the off-site
copy before the API's first start on the new volume (a deletion the API
journals meanwhile would let a partial journal pass the replay's check):
after `infra/configure.sh backend api` has created
`/srv/data/account-deletions/` again, with the API still stopped, decrypt
the copy on the Mac like the dumps and import it. Each deletion goes back
into the day it was made, so it leaves at its own time:

```bash
age --decrypt --identity ~/.config/lunaway/backup-age.key \
  ~/Backups/lunaway/account-deletions/account-deletions.jsonl.age \
  | ssh -F ~/.config/lunaway/ssh_config lunaway 'umask 077; cat > restore-deletions.jsonl'
# on the backend
sudo systemctl stop lunaway-api
sudo lunaway-admin accounts import-deletions < restore-deletions.jsonl
rm restore-deletions.jsonl
```

The takedown journal comes back the same way, before any takedown on the
new volume, then `replay-takedowns` as above:

```bash
age --decrypt --identity ~/.config/lunaway/backup-age.key \
  ~/Backups/lunaway/place-takedowns/place-takedowns.jsonl.age \
  | ssh -F ~/.config/lunaway/ssh_config lunaway 'umask 077; cat > restore-takedowns.jsonl'
# on the backend
sudo lunaway-admin takedowns import < restore-takedowns.jsonl
rm restore-takedowns.jsonl
```

Until the journal is back, the hourly copy writes nothing: a journal that
names no deletion never makes a first copy, and one that lost a day younger
than 30 days stops the run (the days of the last copy are kept on the root
disk, `/var/lib/lunaway-deletions-offsite/days`), so the copies on the ops
server and the Mac are not replaced by an empty or partial one. When the
copy put back is older than the journal that was lost (deletions made
between the last pull and the loss), the run keeps stopping on those days;
once the journal is back, let it through once, deliberately:

```bash
sudo env LUNAWAY_DELETIONS_ALLOW_LOSS=1 /usr/local/sbin/lunaway-deletions-offsite
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

The danger zones' secret (`LUNAWAY_ZONE_SECRET`, `docs/speed-cameras.md`)
never changes once zones are served: every zone's cut and id come from it,
so a new secret moves every zone, and two versions of a zone give away
where its camera stands. A dump does not hold it. When `/etc/lunaway/zone.env`
is lost (a new server, a rebuilt disk), the `pipeline` step refuses to
generate another while `zone-secret.env.age` is on the data volume; put
the old one back from the Mac before that step, without the plaintext
touching a disk:

```bash
age --decrypt --identity ~/.config/lunaway/backup-age.key ~/Backups/lunaway/zone-secret.env.age \
  | ssh -F ~/.config/lunaway/ssh_config lunaway 'sudo install -m 0600 -o root -g root /dev/stdin /etc/lunaway/zone.env'
```

When the data volume is lost too, do the same before the first
`infra/configure.sh backend`: a step that finds neither the secret nor its
copy generates a new secret, and every zone moves at the next build.

The takedown secret (`LUNAWAY_TAKEDOWN_SECRET`) the same way: the cells
stored around every place taken down are keyed with it, and the journal's
lines carry its check value, so `takedowns replay` refuses another secret.
The `pipeline` step refuses to generate one while
`takedown-secret.env.age` is on the data volume:

```bash
age --decrypt --identity ~/.config/lunaway/backup-age.key ~/Backups/lunaway/takedown-secret.env.age \
  | ssh -F ~/.config/lunaway/ssh_config lunaway 'sudo install -m 0600 -o root -g root /dev/stdin /etc/lunaway/takedown.env'
```

The external community source's settings (`/etc/lunaway/extcom.env`) are
in no dump either. The `pipeline` step stops while `extcom-env.age` is on
the data volume and the file is missing; put it back the same way:

```bash
age --decrypt --identity ~/.config/lunaway/backup-age.key ~/Backups/lunaway/extcom-env.age \
  | ssh -F ~/.config/lunaway/ssh_config lunaway 'sudo install -m 0600 -o root -g root /dev/stdin /etc/lunaway/extcom.env'
```

After restoring a dump, apply again the erasures of authors of that source
received since the dump was taken ("The external community feed"): the
dump brings their reviews back and no journal holds those erasures.

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

### How long things are kept

What the privacy page states, as the servers apply it (2026-10-07):

| what | where | kept at most | how |
|---|---|---|---|
| web access log | backend and ops server, `/var/log/caddy/access.log` | about 14 days a line, plus 7 days in the backend's server images | Caddy rolls the file every day (`roll_interval 24h`, and at 50 MiB within a busy day) and drops a rolled file 12 days after it was rolled (`roll_keep_for 288h`): a day or two in the current file (a restart of Caddy may start the day again), then 12 (`infra/caddy/Caddyfile`, `status.Caddyfile`). The file is on the root disk, which Hetzner's daily images of the backend capture |
| system journal, the routing engine's lines included | both servers | six weeks at most, plus 7 days in the backend's server images | a new file every week (`MaxFileSec=1week`), removed once its last entry is a month old (`MaxRetentionSec=1month`) and journald next clears, 1 GB in all (`infra/files/etc/systemd/journald.conf.d/lunaway.conf`). The engine's lines carry the request's number, time, status and size, never a position; its long-request threshold is an hour in `infra/routing/valhalla.json`, so a slow request is never written out |
| plaintext dumps | backend data volume | 7 nights | `lunaway-pgdump` |
| encrypted dumps | backend off-site directory (7), root disk (3) and its Hetzner images (7 days), ops server (15 days: a dump dated D goes at the 01:15 UTC run of D+15), Mac (30 days: at the 04:30 run of D+30) | 30 days on the Mac | the ops server prunes before and after each pull (`lunaway-replica`, 01:15 UTC); the Mac prunes at each run of its nightly job, before the pull: at 04:30, at wake when it slept through, at the start of the session when it was off (`RunAtLoad`) |
| copies of deleted photos | ops server and Mac, `media-deleted/<day>/` | 26 days after the deletion day | the same two prunings |
| account deletion journal | backend | 45 days | the API (`LUNAWAY_DELETION_JOURNAL_DAYS`); copies replaced at each pull |
| takedown journal | backend and copies | no limit | a few lines a year, ids, codes and keyed hashes only; the cells must outlive every restore |
| contributions: issue reports, resolved content reports and moderation entries, "still there?" answers, refused or withdrawn submissions, a banned account's key hash | PostgreSQL | 90 days, a year after the decision, two years, 30 days, two years after the deletion | `lunaway retention`, daily at 03:40 UTC as the API's role (`lunaway-retention.timer`, installed by the `api` step once the release has the command); the durations are constants of `backend/crates/lunaway-db/src/retention.rs`. After a restore, the next run brings the restored rows back within them |
| machine translations of reviews and descriptions | PostgreSQL, `translations` | as long as the original, unchanged | a review's translations are deleted with it, or when its text changes or empties (a withdrawal, a ban), by triggers of the migration `20261009090000_translations.sql`, whoever writes; `lunaway retention` deletes what a race left and the translations of descriptions a refresh changed. The translation server keeps nothing (see "Translation") |

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

| URL, on `tiles.lunaway.net` | what | cache |
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
that Caddy fills in with the site's base URL, so no file on disk names a
host. The TileJSON works the same way.

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
`https://tiles.lunaway.net/packs/manifest.json`:

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

Checked from the Mac on 2026-10-06 against the backend's provisional
sslip.io name (retired since): the manifest
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
refresh and its files, `/srv/routing` and the build keys. The step enables
the daily timer once a graph serves.

One graph covers the countries of the European import and Morocco
(`infra/routing/europe-extracts.txt`), France with IGN's heights; it
replaced the France-only graph on 2026-10-07
(plan/research/35-routage-europe-prod.md).

```
 maintainer's Mac, Sundays 03:00 local (infra/ops/mac-routing/, launchd)
   waits for Geofabrik's 25 extracts of one day, then hcloud creates
     lunaway-routing-build-<stamp> (ccx33, purpose=routing-build, own firewall)
       25 dated extracts ─ osmium merge ─ IGN BD TOPO sections (WFS)
       lunaway routing prepare ─ osmium apply-changes ─ Valhalla build ─ route tests
   ◄── bundle over SSH (host key pinned), server deleted
   sums recomputed, signed (routing-signing_ed25519), gh release upload
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
2. `lunaway routing prepare`: one reading of the extract writes
   `fixes.osc.gz`, the tags Valhalla must read differently (limits in
   canonical form, `maxweightrating` copied into `maxweight`, `motorhome=*`
   copied into `motorcar`, IGN limits on the ways they match, the lowest
   value winning; a "sauf desserte" plate written as the
   `maxweight:conditional=none @ destination` Valhalla reads, a "sauf
   livraisons" one removed; IGN weights on motorways and on lanes closed
   to the public set aside; the roads without a limit that only a "sauf
   desserte" zone leads to, within 500 m of it, given the zone's limit and
   plate, so that the engine grants a trip ending there the right on its
   first pass, and written as restrictions flagged `enclosed` that the
   check joins to the zone and never tells: up to eight passes over the
   ways blocks, 1 152 areas and 2 303 roads for France on 2026-10-08,
   about 30 s on the maintainer's Mac), `restrictions.ndjson.gz` (841 651 restrictions
   for Europe, 266 389 for France: OpenStreetMap ways and nodes, IGN
   sections, each with its geometry and certainty), `prepare.json` and
   `build.json`.
   IGN covers France only, so its heights only reach French ways;
3. `osmium apply-changes` (Debian's osmium-tool in `osmium.Dockerfile`);
4. Valhalla's build in the pinned image (`valhalla-build.sh`): roads only,
   no time zones, no elevation;
5. the route tests of `test-routes.json` on the new graph: the Limoges
   bridge of Rue Maurice Utrillo at 2.5, 2.71 and 3.3 m, the Pas Redon
   bridge (signed with `maxweightrating` alone) at 3.5 and 4.5 t,
   `motorhome=no` on Route de Grandchamp, an `hgv=no` road a motorhome may
   take, the 3.4 m porch of Rue Braille that only IGN measures, Brive to
   Ussel, and trips across borders and in Spain, Portugal, Italy and
   Morocco; a 3.8 t motorhome on the A8 at Rousset and the A54, where IGN
   marks 3.5 t, and a 4.5 t one into and past the "sauf desserte" of the
   D937 (plan/research/61-limites-urbaines.md); a 3.5 t motorhome to the
   aire of Goult and a 4.5 t one to the Calvaire aire, each behind a "sauf
   desserte" street, found on the engine's first pass (`first_pass`: the
   case fails on a route of the relaxed second pass, warning 401, which
   ignores every plate). On the raw France graph
   three of the France cases fail (the porch, the weight rating,
   `motorhome=no`): what the preparation exists for;
6. the bundle, the graph in gzip parts under 1.9 GB (a release asset may not
   exceed 2 GiB).

The weekly run is `infra/ops/mac-routing/lunaway-routing-build.sh run`,
started by launchd on the Mac (`legal.p2p.lunaway.routing-build`, Sundays
at 03:00 local time):

1. it waits, before creating anything, until Geofabrik's `state.txt` gives
   one date for all 25 extracts and the dated file of that day
   (`<name>-YYMMDD.osm.pbf`) exists for each, 12 hours at most. The dated
   files, not `-latest`: Geofabrik sends `-latest` of Germany to a mirror
   that served the extract of 2026-10-04 at 23:08 UTC on 2026-10-06, a day
   after Geofabrik's own `state.txt` and dated file had moved to
   2026-10-05; merging two days leaves two versions of the objects changed
   in between. Nothing is built when the published graph already has that
   date (`--force` builds anyway);
2. it creates a firewall and a server named `lunaway-routing-build-<stamp>`,
   labelled `purpose=routing-build`: a ccx33 in fsn1 (8 dedicated vCPU,
   32 GB, 240 GB, 0.2219 EUR an hour excl. VAT), else in nbg1, else a cx53.
   The firewall lets SSH in from the admin sources only, and lets out DNS,
   NTP, HTTP and HTTPS only (packages, crates, the images, Geofabrik, IGN);
   the server is on no private network. Its ed25519 host key is generated
   on the Mac, handed over by cloud-init and pinned before the first
   connection, as for `infra/build/remote-build.sh`;
3. the server fetches the commit at the head of `main` of the public
   repository and runs `infra/routing/europe-build.sh <YYMMDD>` under
   `systemd-run` (killed by systemd after 6 hours): the 25 dated extracts,
   three at a time, each checked against its MD5, their replication
   timestamps compared (equal, or the build stops), `osmium merge`, then
   `build-graph.sh --area eu --threads 8 --refresh-ign`;
4. the Mac reads the run's state every 5 minutes; after 7 hours of the
   server's life, or 30 minutes without an answer, it gives up. Whatever
   happens, the server and its firewall are deleted (an exit trap, a
   signal included). If the Mac itself dies mid-run, the hourly sweep
   (`legal.p2p.lunaway.routing-sweep`) deletes any server or firewall
   labelled `purpose=routing-build` older than 8 hours, and the nightly job
   reports it;
5. it copies the bundle back over SSH, deletes the server at once, checks
   the copy against the server's sums, then repeats the checks of the old
   publish job: `build.json` is the CLI's flat object, its id ends in `-eu`
   and its build time falls within the server's life, its data date is the
   extracts' date, every route test passed. It recomputes `SHA256SUMS` from
   the files received, signs it (`ssh-keygen -Y sign`, namespace
   `lunaway-routing-graph`), checks the signature against
   `routing-signers`, and uploads the parts, then the signed sums, then
   `build.json` to the release `routing-graph` as the gh account
   `poka-IT`; stale assets go. The 8 GB copy is removed; the metadata and
   the logs stay in `~/Library/Logs/lunaway-routing/<stamp>/`;
6. it writes `~/Library/Application Support/Lunaway/routing/state`
   (`last_success`, `last_run`, `swept`), which the nightly job reads.

The build server receives no Hetzner token, no GitHub token and no signing
key: everything that needs one happens on the Mac.

```bash
infra/ops/mac-routing/install.sh keys     # the signing key, once
infra/ops/mac-routing/install.sh backup   # its age-encrypted copy into the backup chain
infra/ops/mac-routing/install.sh          # the script and both launchd agents
infra/ops/mac-routing/install.sh run      # one build now (launchctl kickstart)
"$HOME/Library/Application Support/Lunaway/routing/lunaway-routing-build.sh" run --dry-run
                                          # what a run would do now: leftovers, the extracts' date, the
                                          # published graph; creates nothing, never waits, records nothing
tail -f ~/Library/Logs/lunaway-routing-build.log
launchctl print gui/$(id -u)/legal.p2p.lunaway.routing-build | grep -E 'state|last exit'
hcloud --context lunaway server list -l purpose=routing-build   # nothing, outside a run
```

Measured (`plan/research/31-routage-europe.md`, `35-routage-europe-prod.md`):

| what | France (cpx42, 4 threads, 2026-10-06) | Europe (ccx33, 8 threads) |
|---|---|---|
| extract | 5.09 GB | 25 extracts, 28.0 GB, merged 28.8 GB |
| `lunaway routing prepare` | 3 min | 14 min 43 s, 4.3 GB resident |
| Valhalla build | 19 min | 2 h 11 min, 16.5 GiB anonymous memory at the peak |
| disk, peak | 16.1 GiB of work files | about 171 GB with the merged extract |
| graph | 3.59 GB | 20.3 GB of tiles; bundle of 8.3 GB in 5 parts |
| whole run | 28 min | 3 h 26 min with downloads and merge (2026-10-06) |

The France graph was built by a GitHub Actions workflow
(`routing-graph.yml`, run 37433921370 on 2026-10-06: 64 minutes on a
4 vCPU, 16 GB runner). A standard runner cannot build Europe (16 GB of
memory against 16.5 GiB anonymous, 105 GB of free disk against 171 GB), and
larger runners need a GitHub Team plan; the workflow was retired once the
first Europe graph served. The Mac does not build: one filled its disk on
2026-10-06.

When a run fails, `~/Library/Logs/lunaway-routing-build.log` says where,
and the server's own log is in `~/Library/Logs/lunaway-routing/<stamp>/`
when it got that far. A run can be started again at once
(`install.sh run`); the backend keeps serving the previous graph, and the
status page turns red only when the graph served is 10 days old.

- The IGN read is tried three times, five minutes apart: the WFS once cut
  a page off after 102 s (an HTTP/2 stream reset) that it served in 18 s
  ten minutes later.
- An extract is tried three times, five minutes apart.

### The build keys

The Mac signs `SHA256SUMS` with an ed25519 key,
`~/.config/lunaway/routing-signing_ed25519` (`ssh-keygen -Y sign`,
namespace `lunaway-routing-graph`); the backend accepts a graph only when
`ssh-keygen -Y verify` finds that signature by the identity
`lunaway-routing` in `/etc/lunaway/routing-signers`, installed from
`infra/routing/routing-signers`. The key was generated on the Mac on
2026-10-07 by `infra/ops/mac-routing/install.sh keys`, without a passphrase
(launchd runs the build unattended), 0600 in the 0700 directory of the
other keys. Its copy is age-encrypted to the backup recipient
(`install.sh backup`): `routing-signing-key-<stamp>.age` at the top of the
backend's off-site directory, pulled with the dumps by the ops server and
the Mac, never pruned. Restoring it:

```bash
age --decrypt --identity ~/.config/lunaway/backup-age.key \
  -o ~/.config/lunaway/routing-signing_ed25519 ~/Backups/lunaway/routing-signing-key-<stamp>.age
chmod 0600 ~/.config/lunaway/routing-signing_ed25519
ssh-keygen -y -f ~/.config/lunaway/routing-signing_ed25519 > ~/.config/lunaway/routing-signing_ed25519.pub
```

Why the Mac signs, rather than the old GitHub job from a bundle the Mac
would hand over: the Mac already holds a gh login that can push to `main`
and run any workflow, so a key kept in GitHub would not protect the graph
from a compromised Mac; signing where the files are received saves a
second 8 GB transfer through GitHub and a job that sometimes waited 13
minutes for its environment. Rotation is a new pair, the new line in
`routing-signers`, `infra/configure.sh backend routing`, then a build:

```bash
mv ~/.config/lunaway/routing-signing_ed25519 data/tmp/routing-key-old   # out of the way, then removed
infra/ops/mac-routing/install.sh keys      # prints the new allowed-signers line
infra/ops/mac-routing/install.sh backup
# replace the old line in infra/routing/routing-signers, commit, then:
infra/configure.sh backend routing && infra/ops/mac-routing/install.sh && infra/ops/mac-routing/install.sh run
```

Graphs signed by a removed key stop installing as soon as the new
`routing-signers` is on the backend; the graph already served keeps
serving meanwhile.

### Serving on the backend

- `valhalla.service` (Quadlet unit `infra/routing/valhalla.container`):
  the official image pinned by digest, run by Podman, `Network=host` with a
  listener on 127.0.0.1:8002 only, read-only, no capability, a 6 GB memory
  cap (Europe without a cap settled at 5.95 GB after 400 varied routes; with
  3 GB the kernel read the tiles again and again, plan/research/31), and an
  IP filter to loopback: the engine receives every route's
  positions and reaches nothing. Its configuration is the repository's
  `infra/routing/valhalla.json` (route, trace_attributes, sources_to_targets
  and status only; a matrix's points 60 km apart at most, for the fuel
  search's detours),
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
  activates the restrictions (`lunaway routing activate`), then queues
  `lunaway-enforcement-full.service`: the danger zones follow the roads of
  the graph served, so they are all built again (also after `--rollback`).
  A failure before the switch serves nothing new; after it, the previous
  graph comes back.
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
  memory-mapped and read at random, and can be rebuilt. A Europe graph
  takes 20.4 GB unpacked and 8.3 GB to download; two graphs, a download and
  the graph being unpacked take about 70 GB at the peak of a refresh, of the
  root disk's 150 GB. The refresh stops before downloading when the root
  disk has less free than 3.5 times the parts' 2 GiB plus 5 GB (40 GB for
  five parts). The status page turns red when the root disk is 80% full.
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

`Query.route` validates the request (points in the area the API declares
covered, `lunaway_domain::routing::coverage`: the Geofabrik outlines of
the 25 extracts of `infra/routing/europe-extracts.txt`; 5 waypoints, 2
alternatives, `MAX_TRIP_M` in a straight line, at most the engine's
`service_limits.auto.max_distance` in `infra/routing/valhalla.json`, the
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
each leg included. A weight, axle, length or width limit that spares local
access ("sauf desserte", `route_restrictions.except_destination`) only
warns on the run of such limits that reaches a stop, gaps of 500 m at most
between them, the roads enclosed behind the zone joining it
(`route_restrictions.enclosed`, an aire on a service road behind a "sauf
desserte" street), and blocks elsewhere. A limit the vehicle exceeds blocks the
route: the engine is asked again with a 5 m ring excluded at each
blocker, three calls at most; a recalculation that moves a stop more than 30 m, or loses the road
it lies on, ends there (a stop asked again with a search radius, below,
may land anywhere within it). A route with a blocker never reaches the app;
`NO_SAFE_ROUTE` names the blockers. A trip that fails because a stop's
road is closed to the vehicle by a restriction within 250 m of the point
is asked again with a search radius of 100, then 150 m, for that stop
alone, and for another stop too when the trip asked again meets such a
restriction beside it; the answer then says where the stop went
(`movedStops`). The vehicle's own position is asked again within 25 m
only (as far as the nearest road when none lies that close), without a
course, and never told as moved; with a course, never. The answer
carries the OSRM JSON Ferrostar reads, typed warnings with their
position, and the graph's dates and IGN edition. Tested end to end on the prepared France graph
(`infra/routing/e2e.sh`, which needs Docker: run it on a build machine,
never on the maintainer's Mac).

A blocker the engine does not see by itself (a height barrier mapped on a
node, a port's lane) costs a second engine call. The API looks for them
ahead from public data only (`routing::public`): a minute after it
starts, then whenever the active graph or the restrictions outside the
graphs (DiaLog's, the community's) changed, read every ten minutes, it
routes the pairs of capitals of the graph's countries within the longest
trip for a typical vehicle of each of three classes (vans up to 2.6 m,
low motorhomes up to 3.0 m, the rest), one engine call at a time and
only while another slot stays free, and keeps the barriers and road
limits other than clearances that those routes meet more than 10 km from
their ends. The first call of a trip then excludes the kept ones that lie
in the box of its stops widened by 1 degree, more than 10 km from each
stop, and stop its vehicle; a trip left without a safe route that way is
asked again without them. Nothing a client asks enters the list. The
journal says `restrictions kept ahead computed again` with the graph, the
pairs, the calls and the seconds it took; until then, after a start or a
new graph, trips exclude nothing ahead.

Each route writes one line to the API's journal, `route computed`, with
where its time went: `queue_ms` (waiting for a slot), `engine_ms` and
`engine_calls`, `corridor_ms` (the corridor queries and the sampling
around them), `check_ms` (the matching), `limits_ms` (the wait for the
speed-limit traces once the check is over: they are traced one at a time
during the check, in pieces of 150 km, 40 at most), the routes kept and
`osrm_bytes`; durations and
counts only, no position. `journalctl -u lunaway-api | grep "route
computed"` reads them. On 2026-10-07 the engine took most of the time of
a long route: about 1 to 2.4 s a call on the backend's shared vCPU, 2.9
times what a ccx23 (dedicated vCPU) took for the same calls on the same
graph (`plan/research/48-latence-itineraires.md`).

## Geocoding

The map's search gives postal addresses, streets, towns and postcodes under
the places (`Query.searchAll`, `docs/data-sources.md`, "Addresses of the
map's search"). The app asks the API; the API asks the geocoders through
Caddy on the backend's loopback (`infra/caddy/geocoders.caddy`,
`127.0.0.1:8486`), so the API's own sandbox still reaches nothing outside
the host:

```
 app ── searchAll ──► lunaway-api ── 127.0.0.1:8486 (Caddy, no access log)
                                     /ban/...            ─► https://data.geopf.fr/geocodage/...   France
                                     /photon/europe/...  ─► 10.42.0.4:2322  photon@europe         Europe
                                     /photon/morocco/... ─► 10.42.0.4:2323  photon@morocco        Morocco
```

The API's unit names the three (`LUNAWAY_GEOCODE_BAN_URL`,
`LUNAWAY_GEOCODE_PHOTON_URL`); it waits 700 ms at most for each, sends 40
requests a second at most to the Géoplateforme (which allows 50 per address
and blocks five seconds beyond) and stops for as long as a 429 says, and
counts 300 searches every ten minutes per client (`LUNAWAY_QUOTA_GEOCODE`).
A geocoder late or down leaves the places on time, without its addresses
(`addressesComplete: false`). Neither the API nor Caddy nor Photon logs the
text searched.

### The geocoding server

`lunaway-geocode-1` (cx43, 8 vCPU, 16 GB, 160 GB local NVMe, fsn1, private
address 10.42.0.4), role `geocode` of `infra/lib.sh`, without a volume:
everything on it is downloaded again in an hour. Its Hetzner firewall opens
SSH to the admin sources only; nftables opens Photon's two ports to the
backend's private address only (`infra/files/roles/geocode/nftables.nft`).

```bash
infra/provision.sh geocode       # the server, on lunaway-net as 10.42.0.4
infra/configure.sh geocode       # harden, then geocode: Java 21, Photon, units, refresh
infra/configure.sh backend caddy api   # the backend's way to it, and the API's settings
infra/deploy-gatus.sh            # the three address checks of the status page
```

The step `geocode` (`infra/server/geocode.sh`) installs the Photon jar
pinned in `infra/geocode/version.sh` (checked by its SHA-256), the units
`photon@europe` and `photon@morocco` (`infra/geocode/photon@.service`,
sandboxed, listening on 10.42.0.4 only), and `lunaway-photon-refresh` with
its monthly timer (first Sunday, 02:30 UTC). The first databases come from
`sudo systemctl start lunaway-photon-refresh` (about an hour), then the step
again, which enables the instances and the timer.

The refresh keeps two slots per instance under `/srv/photon/<instance>/`
(`a`, `b`, and `current` pointing at the one served), fills the other one,
switches, restarts the instance and checks searches in Germany, Spain and
Italy (Morocco: Chefchaouen and Rabat); when they fail, the previous slot
serves again. Europe is GraphHopper's ready-made Photon database (checked
against its published MD5); Morocco, which it does not hold, is imported on
the server from GraphHopper's Africa dump with `-country-codes ma`.

Measured on 2026-10-07 on a test server (ccx33) under memory caps standing
for the server types (plan/research/58-recherche-adresses.md):

| | measure |
|---|---|
| Europe database | 32 GB to download, 48.1 GB (44.8 GiB) unpacked, 52 min download and unpacking at the source's pace (about 10 MB/s) |
| Morocco import | 160 439 places, 168 s from the download to the end, 113 MB |
| start | Photon answers 4.5 s after its start |
| memory | under a 7 GB cap (heap 2 GB) as under 15 GB (heap 4 GB): 400 varied searches, four at a time, median 40 ms, p95 218 ms from a cold cache, p95 77 ms warm |
| precision | 26 of 30 European addresses found at once (the misses: two typos, a Greek street typed in Latin letters, "Grand Rue Luxembourg") |

A cx33 (8 GB, 80 GB) would serve as fast at this load, but holds one copy
of the Europe database, not two: its refresh would stop the European
addresses for an hour each month.

### Addresses of the places

`lunaway addresses` gives an address to the places no source gives a
street or a town, by a reverse geocoding of their position on the same
Photon, through the same Caddy on the loopback (`docs/data-sources.md`,
"Addresses of the places"). `lunaway-addresses.timer` runs it hourly at
:20 for 50 minutes at most, as the import role, one request every 50 ms
(`--rate 20`): the first runs give their address to the places of the
catalogue, about 108 000 on 2026-10-10 (90 minutes of requests, so two
runs), the later ones to the new places and those that moved by more than
25 m. Each page of 100 places is asked without the writers' lock, then
written under it; a stopped run resumes with the places still without an
answer. The change feed carries each address written, and the packs
built after it hold them.

```bash
infra/configure.sh backend pipeline     # lunaway-addresses.service and its timer
sudo systemctl start lunaway-addresses  # a run now, rather than at :20
journalctl -u lunaway-addresses         # "addresses: N places asked, ..."
```

## Translation

`Query.translate` translates a review or a description into the reader's
language on Lunaway's own server, with open models: no third-party service
sees a text (`docs/architecture.md`, "Translation"). The API asks the
translation server through Caddy on the backend's loopback, as it asks
Photon:

```
 app ── translate(kind, id) ──► lunaway-api ── 127.0.0.1:8486/translator/translate (Caddy, no access log)
                                     │            ─► 10.42.0.4:2324  lunaway-translate (geocoding server)
                                     └── translations (PostgreSQL): kept while the original stands
```

- **Engine.** OPUS-MT models of the University of Helsinki (Marian, CC BY
  4.0), converted to CTranslate2 (MIT) int8 on the server, one direct
  model per pair between the app's six languages
  (`infra/translate/models.txt`, 28 pairs), through English for a pair
  without its own: Italian to Dutch and Dutch to Italian, which have no
  bilingual model. The study that chose them, against the Firefox
  Translations models and Argos Translate, measured on real reviews:
  `plan/research/77-traduction.md`.
- **What is sent and kept.** The API reads the stored text under the
  rules of the screen that shows it and sends it with its language and the
  language asked; it never translates a text a client sends. The server
  keeps nothing and logs no text, no address; Caddy's site on 8486 has no
  access log. The API keeps each translation (`translations`) with the
  SHA-256 of its original, the engine and the model, and deletes a
  review's translations with the review (see "How long things are kept").
- **Limits.** 300 texts translated every ten minutes per client
  (`LUNAWAY_QUOTA_TRANSLATE`; only a translation made counts: a kept
  one, a refusal, a server stopped, late or answering badly gives the use
  back, while a text the model gave back as it came counts, and is kept
  as the verdict that no model reads it, which later requests read without
  asking the model; a request the client leaves still finishes its translation in a
  task of its own, which keeps it for the next reader and counts it, so
  leaving frees no slot of the server), one `translate` per request, four
  texts at once for all clients (`LUNAWAY_TRANSLATE_AT_ONCE`), two slots
  per address (IPv4, /64; half of `LUNAWAY_TRANSLATE_AT_ONCE`, at least
  one, `client_at_once` in `translate.rs`) and all of them but one for an
  IPv6 /48 when there are several, so a client asking again and again for
  a text the server always fails at, which costs it no use, leaves the
  other slots to everyone else; a text waits for its client's slot and for
  the API's within the same 2 s (`LUNAWAY_TRANSLATE_QUEUE_WAIT_MS`), then
  is refused as busy (`RATE_LIMITED`, `retryAfterSeconds` 2). The slots
  are counted per address: a person with several (an IPv4 and an IPv6)
  holds more. Two at once on the server, 15 s for one text
  (`LUNAWAY_TRANSLATE_TIMEOUT_MS`), 14 s on the server, which then stops
  between two batches of sentences.
- **Sandbox.** `lunaway-translate.service` runs as `translate`, reads its
  models only, listens on 10.42.0.4:2324, connects to nothing; nftables
  opens the port to the backend's private address only
  (`infra/files/roles/geocode/nftables.nft`). CPU weight 20 against
  Photon's 100, four cores at most, 4.5 GB of memory at most.

```bash
infra/configure.sh geocode translate    # Python packages by hash, models by SHA-256, the unit
infra/configure.sh backend caddy api    # the backend's way to it, and LUNAWAY_TRANSLATE_URL
infra/configure.sh ops ops-status       # the status page's "Translation" check
```

The step `translate` (`infra/server/translate.sh`) installs Python's
`venv` from Debian, the packages of `infra/translate/requirements.txt`
(wheels only, each checked against its hash) in
`/opt/lunaway-translate/venv-<pins>`, the server, and
`lunaway-translate-models.service`, which downloads each archive of
`models.txt` as `translate`, checks its SHA-256, converts it and switches
`/srv/translate/models/<pair>/current` to it; a pair already installed is
left alone. A new model is a line of `models.txt` and the step again.

Measured on 2026-10-08 on `lunaway-geocode-1`, with the first ten models
(commands in `plan/research/77-traduction.md`):

| | measure |
|---|---|
| models | 10 archives, 4.0 GB to download; 1.1 GB once converted (`du -sh /srv/translate/models`); 1 min 41 s from the start of the installation to the server answering |
| memory | 1.33 GB resident after a start, 1.47 to 1.69 GB after 120 translations (`ps -o rss`); 1.56 to 2.15 GB at the peak with the model files' pages (`MemoryPeak` of the unit) |
| latency, through `https://api.lunaway.net` from the maintainer's Mac, final server | a review of 60 to 200 characters: median 504 ms, p95 758 ms German to French, median 520 ms, p95 882 ms French to English (20 each); a description of 1 500 to 2 000 characters, French to English: median 2 937 ms, p95 3 517 ms (20); a kept translation: median 91 to 95 ms, as `{ apiVersion }` (88 to 105 ms) |
| Photon beside it | 200 searches four at a time through the backend's Caddy: median 23 ms, p95 80 ms before; median 23 ms, p95 84 ms after; 200 searches not asked before, during translations: median 26 ms, p95 108 ms |

The same measures on 2026-10-09, after the 18 models towards German,
Spanish, Italian and Dutch:

| | measure |
|---|---|
| models | 18 archives more, 5.6 GB; 2.7 GB once converted for the 28; 2 min 48 s to install the 18 (journal of `lunaway-translate-models`), 4 s for the server to load the 28 |
| memory | 3.15 GB resident after a start, 3.17 GB once every pair translated a review, 3.28 GB once every pair translated a text of 1 700 characters (`RssAnon`); the cgroup sits at `MemoryHigh` (4 GB) with the model files' pages, which it gives back first. The server's available memory went from 8 565 to 6 863 MB (`free -m`), and the cgroup of `photon@europe` from 11.6 to 9.5 GB, its heap of 3.9 GB and its page cache (`MemoryCurrent`) |
| threads | 60 after a start, 114 once every pair has been asked: each model starts its own threads on first use. glibc then keeps a heap arena per thread: without `MALLOC_ARENA_MAX=2` the long texts took the process to 4.03 GB resident and 1.29 GB swapped |
| latency, as above | a review of 60 to 200 characters (20 each): French to German, transformer-big, median 549 ms, p95 919 ms; Dutch to Italian, through English, median 575 ms, p95 686 ms; a kept translation: median 91 ms, as `{ apiVersion }` |
| through English | two models instead of one: on the server, a review of about 280 characters takes 0.52 to 0.70 s from Italian to Dutch and back, 0.22 to 0.45 s between two languages with their own base model (two runs) |
| Photon beside it | same 200 searches: median 20 ms, p95 79 ms before; median 23 ms, p95 75 ms after; 200 searches not asked before: median 19 ms, p95 78 ms before, median 19 ms, p95 81 ms after, median 21 ms, p95 85 ms during translations |
| quality, graded by hand on 10 real reviews per pair (scale of the study) | French to German 3.6, to Spanish 3.0, to Italian 3.7, to Dutch 3.8; English to German 3.1; Dutch to Italian through English 3.3, where English loses what it makes ambiguous (`stroom`, electricity, becomes `potere`, political power; `sanitair` becomes `impianto idraulico`, plumbing) |

The unit's cap went from 3 to 4.5 GB rather than loading the rarely asked
models on first use. The ten models between German, Spanish, Italian and
Dutch hold about 0.9 GB, a saving gone once each has been asked unless
idle models are unloaded again. At the worst of Photon's monthly refresh
(its unit capped at 3 GB) beside this server at its `MemoryHigh`,
`photon@europe` keeps about 7.4 GB, more than the 7 GB it answered as fast
under ("Geocoding").

The status page checks the server through the backend's probe
(`translate.ok`, `translate.pairs` of `lunaway-health`): a public check of
`Query.translate` would read a kept translation and say nothing of it.

## F-Droid repository

Until the official F-Droid carries the app, Lunaway publishes its own
repository, with the `fdroid` flavour (no Google Play Services):

| | |
|---|---|
| address | `https://lunaway.net/fdroid/repo` |
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
`/srv/lunaway/fdroid` on lunaway.net only (the `fdroid_repo` snippet): GET and HEAD only, a sandbox CSP, the index files
revalidated on every read, an APK cached a day. Old releases stay until
removed by name.

First publication, 2026-10-06: Lunaway 0.1.0-fdroid, versionCode 1, built
from `main` at 69f9c98, a universal APK of 100,563,315 bytes (arm64-v8a,
armeabi-v7a, x86_64; minSdk 24, targetSdk 36; 0 Play Services class; every
64-bit library aligned on 16 KB), served by release `20261006T130528Z-1`.
An APK signed by another key, put in the archive of a test working copy,
stopped the publication before anything was uploaded. Checked from the Mac with fdroidserver's own client code
(`index.download_repo_index_v2`, `data/tmp/fdroid/client-check.py`): the
index downloaded through the backend's provisional sslip.io name (retired
since) verifies against the fingerprint, a wrong fingerprint is refused, and the APK it lists has the
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
   and its automatic updates take the version from `pubspec.yaml`. From
   version 0.1.0+2 the `fdroid` flavour keeps that versionName as it is
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
backend step `pipeline` (the units and timers below) and the step
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
- `lunaway-road-events-ndw.service` and `.timer`: NDW's Dutch planning
  feed every three hours at :40 (`poll --only ndw`; the three-minute poll
  leaves it out), with a memory cap of 1 GB: 204 MB of XML read whole,
  17 202 events in 11.4 s and 443 MB at the peak (2026-10-06, Mac, debug
  build). The Dutch and Spanish events (DGT, in the three-minute poll) are
  stored but neither matched nor sent to the phones
  (`road_event_sources.routed`), a choice made while the routing graph
  covered France only; it covers both countries since 2026-10-07.
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
- Matching on the engine: an event the engine refuses
  (`400::Insufficient number of locations provided`, `500::leg_shape_index
  not set for intermediate location`, seen on 2026-10-06) stays unplaced
  with the engine's reason (`road_events.match_error`), a warning at its
  raw position, and the pass goes on with the others. It is asked again
  30 minutes after the first refusal and 2 hours after the second, never on
  that graph after the third; five refusals in a row end the pass (the
  engine itself is failing). `infra/verify.sh backend` counts the refusals
  of the last hour.
- The community's reports are weighed by the API every three minutes (a
  vote, its expiry, a ban), not by the poller: the importers' role reads no
  report's account (migration `20261006145517`).
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
| network | nftables on both: default drop in and forward, per-source limits on new SSH connections (the ops server's private address exempt, for its status checks) and on new and concurrent web connections (IPv6 per /64); only this table is reloaded, fail2ban's bans survive; the only filter of the private network |
| ops access | the ops server reaches the backend through two accounts, from one private address: `lunaway-pull`, with three keys each forced to one read-only command (the health probe, `rrsync -ro` on the encrypted dumps, and the list of the external community source's erased authors for its producer), and `extcom-drop`, one key forced to `rrsync -wo` into the external community feed's inbox (write new files only); the backend never connects to the ops server; the Mac's key on the ops server is forced to `rrsync -ro` on the replica and accepted from the admin sources only |
| backups | off-site copies encrypted with age to a key that exists only on the Mac; the ops server and the replica hold ciphertext |
| SSH | admin `ops` only (plus `lunaway-pull`, from 10.42.0.3 only on the backend, from the admin sources on the ops server, and `extcom-drop`, from 10.42.0.3 only on the backend), keys only, no root, `MaxAuthTries 3`, `LoginGraceTime 20`, no forwarding of any kind, post-quantum hybrid key exchange first, no NIST host key, RSA keys of 3072 bits or more |
| SSH | fail2ban `sshd` jail (aggressive mode, systemd backend, nftables action, increasing ban time); the admin sources (no range wider than /16 or /48) and, on the backend, the ops server's private address are exempt |
| system | unattended upgrades from Debian security, PGDG and Caddy; reboot at 02:30 UTC when needed; needrestart restarts services; the upgrade waits for a running dump |
| system | sysctl hardening (rp_filter, no redirects or source routing, syncookies, kptr and dmesg restriction, BPF and ptrace limits, protected links), unused protocols and filesystems blacklisted, no core dumps, AppArmor, chrony, persistent journal capped at 1 GB and six weeks at most (weekly files, removed a month after a file's last entry), swap on zram (compressed memory, never on a disk) |
| packages | the Caddy repository's signing key accepted only with its pinned fingerprint, the source line written from the repository; Gatus and the Rust build image pinned by digest |
| data | volumes mounted `nodev,nosuid,noexec`, their mount point immutable when unmounted; services require the mount |
| PostgreSQL | localhost only, SCRAM, a DDL owner and two row roles (API, imports) with timeouts and no default privileges: the migrations grant each table to the role that needs it, and `test-grants.sh` checks the exact list in production; the statistics views closed to them; connection caps under `max_connections` (API 25, imports 15, owner 5); data checksums, builtin C.UTF-8 collation (no glibc collation drift), slow-query log without bound values; passwords set with statement tracking and statement logging off |
| PostgreSQL | systemd sandbox over Debian's unit: runs as `postgres` with no capabilities, read-only system except its data, socket and log directories, syscall filter, W^X memory, loopback-only network |
| web | Caddy: automatic TLS from Let's Encrypt, HTTP/3, HSTS, strict CSP, `nosniff`, `no-referrer`, frame denial, request bodies of 64 KiB on `/graphql` (read whole before the API sees them), 10304 KiB on `/upload` (POST and OPTIONS only) and 1 MB elsewhere, header (10 s) and body (3 min) read timeouts, answers bounded to 3 min plus a second per 32 KiB sent, admin API on a private unix socket; access log and Caddy's own log with IPv4 truncated to /16 and IPv6 to /32, no port, no query string, no tile coordinates, photo paths as `/media/[photo]` and `/external-photos/[photo]`, no redirect target (`Location`), regional packs as `/packs/places/[pack]` (and any other spelling under `/packs/` with a capital letter as `/packs/[pack]`, any path with a percent-encoded character as `/[encoded]`), no file date (`Last-Modified`, `If-Modified-Since`), kept 14 days |
| API | systemd sandbox: static user `lunaway-api`, no capabilities, read-only system, of `/srv` only `/srv/data/media` visible and writable, private /tmp and devices, syscall filter, W^X memory, outbound connections refused to private, shared and link-local ranges, and limited by nftables to HTTPS and DNS for its user (for the external community source's photo proxy, which the code holds to the agreement's hosts, resolved to public addresses only, 5000 a day at most; the geocoders are reached through Caddy on the loopback, by configuration), may bind only 8484, memory capped at 1.5 GB; CORS for `https://lunaway.net` only, `/media/` included; `lunaway-admin` runs the moderation and account commands under the same user, role and limits |
| conflation worker | the imports' sandbox under `lunaway-ingest`, loopback only, restarted 15 s after a failure, stopped after 10 starts in 15 minutes (the status page then shows it); its queues measured every minute as `postgres` into a world-readable file of counts and ages |
| photo backups | one age-encrypted file per photo, to the key that exists only on the Mac; the job runs as root without capabilities; deleted photos leave every copy within 29 days of their deletion, whenever the ops server and the Mac run; a run that would remove more than 50 copies and 5% of them refuses, on the backend and on the Mac |
| imports | the same sandbox under a static user, outbound connections allowed except to private and link-local ranges (the private network, the metadata service), writes only to `/srv/data/ingest`, memory capped at 3 GiB for the extract readers and lower for the others; the external community feed imported under the same user with loopback only, seeing of `/srv` its inbox (read-only) and the import cache, its SHA-256 checked first, its settings (`/etc/lunaway/extcom.env`, root 0600) loaded by that unit alone; the regional packs built under the same user with loopback only, writing only `/srv/data/packs` (setgid `caddy`: files 0640, readable by Caddy alone); the speed camera builds with loopback only, the only units that load the zones' secret (`/etc/lunaway/zone.env`, root 0600; hidden from the routing refresh, which runs as root) |
| status page | Gatus under its own user with the same sandbox, listening on loopback; Caddy in front refuses anything but GET and HEAD |
| routing | Valhalla under Podman, loopback only (8002, 8003 for a graph under test), read-only, no capability, an IP filter to loopback, only the route, trace_attributes, sources_to_targets (60 km at most between a matrix's points) and status actions, its configuration from the repository; the API refuses an engine URL that is not loopback, and calls it with no proxy and no redirect, bounded in time, answer size, calls in flight and routes per client; the graph is built off the server, pulled over HTTPS, accepted only with a signature of the build key, newer than the one served and less than 30 days old, unpacked by fixed names, and tested before and after the switch |
| basemap | pmtiles under a dynamic user with the API's sandbox, loopback only (8485), the tile volume read-only and nothing else under `/srv`; its refresh as `lunaway-tiles`, writing only the archives, links and TileJSON, outbound HTTPS except to private ranges; the offline packs built as `lunaway-tiles` with no network at all, writing only `/srv/tiles/packs`; go-pmtiles and the fonts pinned by hash; Caddy accepts GET, HEAD and OPTIONS only on the tile routes, at most 64 requests to pmtiles at once; tile coordinates, byte ranges and pack names never logged |
| F-Droid repository | the index signed by a key, and the APK by another, that exist only on the Mac (age-encrypted copies in the backup chain); fdroidserver pinned with hashes; served as static files, GET and HEAD only, sandbox CSP; fdroidserver's run reports never published |
