#!/bin/bash
# 90-report.sh — run on the host: preflight checks on the finished medium so a
# broken build fails loudly in CI instead of shipping a bad artifact.

set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../common.sh"
ensure_flavor_config

ISO_OUT_DIR="${ISO_OUT_DIR:?}"
ISO_NAME="${ISO_NAME:?}"
ISO_STAGE="${ISO_STAGE:?}"
BUILD_LOG_DIR="${BUILD_LOG_DIR:-/tmp}"

step "artifact exists and is plausibly large"
[ -s "$ISO_OUT_DIR/$ISO_NAME" ] || die "no ISO file"
ISO_BYTES=$(stat -c '%s' "$ISO_OUT_DIR/$ISO_NAME")
[ "$ISO_BYTES" -gt 500000000 ] || die "suspiciously small ISO ($ISO_BYTES bytes)"

step "ISO tree (written to log for review)"
xorriso -indev "$ISO_OUT_DIR/$ISO_NAME" -find / -type f \
    | sed 's/^/  /' > "$BUILD_LOG_DIR/iso-tree.txt" || true
tail -n 5 "$BUILD_LOG_DIR/iso-tree.txt"

for required in \
    /casper/vmlinuz \
    /casper/initrd \
    /casper/filesystem.squashfs \
    /casper/filesystem.manifest \
    /casper/filesystem.size \
    /isolinux/isolinux.bin \
    /isolinux/ldlinux.c32 \
    /isolinux/isolinux.cfg \
    /efi.img \
    /md5sum.txt; do
    xorriso -indev "$ISO_OUT_DIR/$ISO_NAME" -find "$required" 2>/dev/null \
        | grep -q . || die "ISO is missing $required"
done

step "casper metadata (installed packages)"
[ -s "$ISO_STAGE/casper/filesystem.manifest" ] || die "filesystem.manifest is empty"
for pkg in casper sddm metacity network-manager linux-image; do
    grep -qE "^${pkg}[0-9.a-zA-Z-]* " "$ISO_STAGE/casper/filesystem.manifest" \
        || die "expected package '$pkg*' missing from filesystem.manifest"
done

step "HDE binaries are inside the squashfs"
unsquashfs -list "$ISO_STAGE/casper/filesystem.squashfs" 2>/dev/null \
    | grep -qE 'bin/hde-session$' || die "usr/bin/hde-session missing from the squashfs"
unsquashfs -list "$ISO_STAGE/casper/filesystem.squashfs" 2>/dev/null \
    | grep -qE 'bin/nexwm$' || die "usr/bin/nexwm missing from the squashfs"
unsquashfs -list "$ISO_STAGE/casper/filesystem.squashfs" 2>/dev/null \
    | grep -qE 'sessions/hde.desktop$' || die "hde.desktop session missing from the squashfs"

step "checksum"
(cd "$ISO_OUT_DIR" && sha256sum --check "$ISO_NAME.sha256")

echo "90-report.sh done"
