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
check_manifest_pkg() {
    local pkg="$1"
    if ! grep -qE "^${pkg}[0-9.a-zA-Z-]* " "$ISO_STAGE/casper/filesystem.manifest"; then
        echo "manifest entries starting with '${pkg:0:4}' (diagnostic):" >&2
        grep -E "^${pkg:0:4}" "$ISO_STAGE/casper/filesystem.manifest" | head -n 10 >&2 || echo "  (none)" >&2
        die "expected package '$pkg*' missing from filesystem.manifest"
    fi
}
for pkg in casper sddm metacity network-manager linux-image; do
    check_manifest_pkg "$pkg"
done

step "the shipped initrd can find and mount the live medium"
if command -v lsinitramfs >/dev/null 2>&1; then
    INITRD_LIST="$BUILD_LOG_DIR/initrd-list.txt"
    lsinitramfs "$ISO_STAGE/casper/initrd" > "$INITRD_LIST" 2>"$BUILD_LOG_DIR/lsinitramfs.err" \
        || { head -n 5 "$BUILD_LOG_DIR/lsinitramfs.err" >&2; die "lsinitramfs could not read casper/initrd"; }
    grep -qE '(^|/)scripts/casper$' "$INITRD_LIST" \
        || die "casper/initrd has no scripts/casper: it cannot find the live medium (kernel panics: Attempted to kill init)"
    # Modules may legitimately be built into the kernel, so these only warn.
    for mod in squashfs overlay isofs sr_mod ata_piix virtio_blk; do
        grep -qE "/${mod}\.ko" "$INITRD_LIST" || echo "warning: ${mod}.ko is not in the initrd (fine only if built into the kernel)" >&2
    done
else
    echo "warning: lsinitramfs not found on the host (initramfs-tools-core); initrd content not inspected" >&2
fi

step "HDE binaries are inside the squashfs"
# List the image ONCE into a file and grep the file (a `| grep -q` pipeline
# under pipefail can also fail spuriously via SIGPIPE). NOTE: squashfs-tools
# 4.6.x has no `-list` option (older releases accepted it as an abbreviation);
# it prints its usage text and exits non-zero. The valid spelling is `-ls`
# (`-l` is the same). Errors are kept visible, not sent to /dev/null.
SQUASH_LIST="$BUILD_LOG_DIR/squashfs-list.txt"
unsquashfs -no-progress -ls "$ISO_STAGE/casper/filesystem.squashfs" > "$SQUASH_LIST" 2>"$BUILD_LOG_DIR/unsquashfs.err" \
    || { head -n 5 "$BUILD_LOG_DIR/unsquashfs.err" >&2; die "unsquashfs could not list the image"; }
[ -s "$SQUASH_LIST" ] || die "unsquashfs produced an empty listing"

check_squash() {   # $1 = ERE, $2 = human name
    if ! grep -qE "$1" "$SQUASH_LIST"; then
        echo "squashfs entries that look related (diagnostic):" >&2
        grep -iE '(hde|nexwm)' "$SQUASH_LIST" | grep -E '(/bin/|/sbin/|sessions/|/opt/)' | head -n 30 >&2 \
            || echo "  (none)" >&2
        die "$2 missing from the squashfs"
    fi
}
check_squash 'sbin/init$'                 "/sbin/init (without it the live boot panics: Attempted to kill init)"
check_squash 'lib/systemd/systemd$'       "systemd (usr/lib/systemd/systemd)"
check_squash 'bin/hde-session$'      "usr/bin/hde-session"
check_squash 'bin/nexwm$'            "usr/bin/nexwm"
check_squash 'sessions/hde.desktop$' "hde.desktop session"

step "checksum"
(cd "$ISO_OUT_DIR" && sha256sum --check "$ISO_NAME.sha256")

echo "90-report.sh done"
