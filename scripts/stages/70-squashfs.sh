#!/bin/bash
# 70-squashfs.sh — run on the host: turn the cleaned rootfs into
# casper/filesystem.squashfs plus the metadata (filesystem.manifest,
# filesystem.size, .disk/info) a casper live medium carries.
#
# The kernel and initramfs stay inside the rootfs too: the squashed copy is
# what Calamares copies onto the disk for the installed system, and that
# system needs its kernel.

set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../common.sh"
ensure_flavor_config

ROOTFS="${ROOTFS:?}"
ISO_STAGE="${ISO_STAGE:?}"
BASE_SUITE="${BASE_SUITE:?}"

say "package the rootfs as casper/filesystem.squashfs"

mkdir -p "$ISO_STAGE/casper" "$ISO_STAGE/.disk"

KEY=$(readlink "$ROOTFS/vmlinuz" 2>/dev/null | xargs -r basename | sed 's|^vmlinuz-||' || true)
if [ -z "$KEY" ]; then
    KEY=$(ls -1 "$ROOTFS/boot" 2>/dev/null | grep -E '^vmlinuz-' | sort -V | tail -n1 | sed 's|^vmlinuz-||')
fi
[ -n "$KEY" ] || die "no kernel found in the rootfs (/boot/vmlinuz-*)"

step "kernel: $KEY"
cp -L "$ROOTFS/boot/vmlinuz-$KEY"    "$ISO_STAGE/casper/vmlinuz"
cp -L "$ROOTFS/boot/initrd.img-$KEY" "$ISO_STAGE/casper/initrd"

step "filesystem manifest (installed packages, the dpkg-level casper manifest)"
chroot "$ROOTFS" dpkg-query -W -f='${binary:Package}\t${Version}\n' 2>/dev/null \
    | awk -F'\t' '{ sub(":.*", "", $1); print $1 " " $2 }' \
    | sort > "$ISO_STAGE/casper/filesystem.manifest"
du -B1M -s "$ROOTFS" | cut -f1 > "$ISO_STAGE/casper/filesystem.size"

printf '%s live build (%s; based on Ubuntu %s LTS)\n' \
    "$FLAVOR_NAME" "$(date -u +%Y%m%dT%H%M%SZ)" "$BASE_SUITE" > "$ISO_STAGE/.disk/info"

step "mksquashfs (zstd; pseudo-filesystem mounts are empty after teardown)"
mksquashfs "$ROOTFS" "$ISO_STAGE/casper/filesystem.squashfs" \
    -noappend -comp zstd -Xcompression-level 19 \
    -wildcards -e '/proc/*' -e '/sys/*' -e '/dev/*' \
    > "${BUILD_LOG_DIR:-$PWD}/mksquashfs.log" 2>&1 || true

[ -s "$ISO_STAGE/casper/filesystem.squashfs" ] || die "mksquashfs produced an empty image"

echo "70-squashfs.sh done (squashfs: $(du -h "$ISO_STAGE/casper/filesystem.squashfs" | cut -f1))"
