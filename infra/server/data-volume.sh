#!/usr/bin/env bash
# Mounts the Hetzner Volume at /srv/data, run as root by setup.sh. The volume
# holds what must survive a rebuild or a resize of the server: the PostgreSQL
# cluster and the database dumps. Never formats anything: the volume is
# created formatted (provision.sh, --format ext4), and a volume without a
# filesystem is an error to look at, not a disk to wipe.
#
#   LUNAWAY_VOLUME_ID   the Hetzner volume id (provision.sh records it)
. "$(dirname "$0")/common.sh"
need_root
id="${LUNAWAY_VOLUME_ID:?set LUNAWAY_VOLUME_ID}"
dev="/dev/disk/by-id/scsi-0HC_Volume_$id"
mnt=/srv/data

[ -b "$dev" ] || die "volume device $dev not found: is the volume attached to this server?"
uuid="$(blkid -s UUID -o value "$dev" || true)"
fstype="$(blkid -s TYPE -o value "$dev" || true)"
[ -n "$uuid" ] && [ "$fstype" = ext4 ] || die "no ext4 filesystem on $dev; refusing to format a data volume"

# Hetzner's automount may have mounted it under /mnt/HC_Volume_<id>.
other="$(findmnt -n -o TARGET -S "UUID=$uuid" | grep -vx "$mnt" || true)"
if [ -n "$other" ]; then
  umount "$other"
  sed -i "\|$other|d" /etc/fstab
fi

if ! grep -q "^UUID=$uuid " /etc/fstab; then
  echo "UUID=$uuid $mnt ext4 defaults,nofail,nodev,nosuid,noexec,x-systemd.device-timeout=30s 0 2" >> /etc/fstab
  systemctl daemon-reload
  echo "    added $mnt to /etc/fstab"
fi

if ! mountpoint -q "$mnt"; then
  install -d -m 0755 "$mnt"
  # An immutable mount point: should the volume ever be missing at boot,
  # writes into /srv/data fail instead of quietly filling the root disk.
  chattr +i "$mnt"
  mount "$mnt"
fi
chmod 0755 "$mnt"
systemctl enable --quiet fstrim.timer
log "volume $id mounted at $mnt ($(df -h --output=size "$mnt" | tail -n 1 | tr -d ' '))"
