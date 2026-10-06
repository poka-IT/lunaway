#!/usr/bin/env bash
# Mounts the Hetzner Volume at /srv/data, run as root by setup.sh. The volume
# holds what must survive a rebuild or a resize of the server: the PostgreSQL
# cluster and the database dumps. Never formats anything (mount_volume in
# common.sh).
#
#   LUNAWAY_VOLUME_ID   the Hetzner volume id (provision.sh records it)
. "$(dirname "$0")/common.sh"
need_root
mount_volume "${LUNAWAY_VOLUME_ID:?set LUNAWAY_VOLUME_ID}" /srv/data
