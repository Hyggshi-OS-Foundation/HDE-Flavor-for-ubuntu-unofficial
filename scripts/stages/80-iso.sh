#!/bin/bash
# 80-iso.sh — run on the host: assemble the bootable live medium.
#
#   BIOS:  isolinux (isolinux.bin + ldlinux.c32) with the isohybrid MBR
#          (isohdpfx.bin) so the same ISO also boots from USB storage.
#   UEFI:  a standalone GRUB x86_64 image inside a FAT ESP image that is
#          attached both as an El Torito entry (CD boot) and as a GPT basic
#          data partition (USB boot).
#   Result: one hybrid ISO, verified by the QEMU smoke test on both paths.

set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../common.sh"
ensure_flavor_config

ISO_STAGE="${ISO_STAGE:?}"
ISO_OUT_DIR="${ISO_OUT_DIR:?}"
ISO_NAME="${ISO_NAME:?}"

step "locate bootloader material"
find_loader_file() {
    for candidate in \
        "/usr/lib/ISOLINUX/$1" \
        "/usr/share/ISOLINUX/$1" \
        "/usr/lib/syslinux/modules/bios/$1" \
        "/usr/share/syslinux/$1" \
        "/usr/lib/syslinux/$1" \
        "/usr/share/syslinux/modules/bios/$1"; do
        if [ -f "$candidate" ]; then
            printf '%s' "$candidate"
            return 0
        fi
    done
    die "syslinux loader file '$1' not found (install the isolinux / syslinux-common packages on the host)"
}

ISOLINUX_BIN=$(find_loader_file isolinux.bin)
MBR=$(find_loader_file isohdpfx.bin)
LDLINUX=$(find_loader_file ldlinux.c32)
step "loader files: $ISOLINUX_BIN / $MBR / $LDLINUX"

step "staging tree layout"
mkdir -p "$ISO_STAGE/isolinux" "$ISO_STAGE/EFI/BOOT"
cp "$ISOLINUX_BIN" "$ISO_STAGE/isolinux/isolinux.bin"
cp "$LDLINUX"      "$ISO_STAGE/isolinux/ldlinux.c32"

step "isolinux.cfg (BIOS path, serial console included for CI visibility)"
cat > "$ISO_STAGE/isolinux/isolinux.cfg" <<'CFG'
SERIAL 0 115200
DEFAULT genmenu
TIMEOUT 500
PROMPT 0

LABEL genmenu
  MENU LABEL NexWM OS
  KERNEL /casper/vmlinuz
  APPEND initrd=/casper/initrd boot=casper console=ttyS0,115200 console=tty0 quiet splash

LABEL safe
  MENU LABEL NexWM OS (safe graphics)
  KERNEL /casper/vmlinuz
  APPEND initrd=/casper/initrd boot=casper console=ttyS0,115200 console=tty0 nomodeset
CFG

step "grub.cfg used by the standalone UEFI image"
cat > "$ISO_STAGE/EFI/BOOT/grub.cfg" <<'CFG'
set timeout=10
set default=0

menuentry 'NexWM OS (live)' --id live {
    search --no-floppy --label --set=root "NEXWMOS"
    linux /casper/vmlinuz boot=casper console=ttyS0,115200 console=tty0 quiet splash
    initrd /casper/initrd
}

menuentry 'NexWM OS (safe graphics)' --id safe {
    search --no-floppy --label --set=root "NEXWMOS"
    linux /casper/vmlinuz boot=casper console=ttyS0,115200 console=tty0 nomodeset
    initrd /casper/initrd
}
CFG

step "standalone GRUB x86_64-efi image (includes grub.cfg in its memdisk)"
grub-mkstandalone \
    --format=x86_64-efi \
    --output="$ISO_STAGE/EFI/BOOT/BOOTX64.EFI" \
    --locales= --themes= --fonts= \
    "boot/grub/grub.cfg=$ISO_STAGE/EFI/BOOT/grub.cfg"
[ -s "$ISO_STAGE/EFI/BOOT/BOOTX64.EFI" ] || die "grub-mkstandalone produced no UEFI image"

step "pack the ESP image efi.img (mtools, no loop mount needed)"
ESP_SIZE=$(( ( ($(du -sk "$ISO_STAGE/EFI/BOOT" | cut -f1) + 2048) / 32 ) * 32 ))
mkfs.vfat -n EFI -C "$ISO_STAGE/efi.img" "$ESP_SIZE" >/dev/null
# mtools does not create intermediate directories: make the ESP layout first,
# then copy the bootloader in place (a UEFI firmware looks for the fallback
# path /EFI/BOOT/BOOTX64.EFI on ESP-formatted media).
mmd -i "$ISO_STAGE/efi.img" ::/EFI ::/EFI/BOOT
mcopy -i "$ISO_STAGE/efi.img" -s "$ISO_STAGE/EFI/BOOT/." ::/EFI/BOOT/ >/dev/null
mdir -i "$ISO_STAGE/efi.img" ::/EFI/BOOT/

step "md5 checksums of the staged tree (casper integrity check)"
( cd "$ISO_STAGE" && find . -type f ! -name 'md5sum.txt' -print0 | sort -z \
  | xargs -0 md5sum | sed 's|  \./|  |' ) > "$ISO_STAGE/md5sum.txt"

step "xorriso: single hybrid ISO (BIOS + UEFI, CD + USB)"
xorriso -as mkisofs \
    -noCache \
    -joliet-long -r -J \
    -V "$FLAVOR_ISO_LABEL" \
    -isohybrid-mbr "$MBR" \
    -b isolinux/isolinux.bin -c isolinux/boot.cat \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    -eltorito-alt-boot \
    -e efi.img \
    -no-emul-boot \
    -isohybrid-gpt-basdat \
    -partition_cyl_align on \
    -o "$ISO_OUT_DIR/$ISO_NAME" \
    "$ISO_STAGE"

step "sha256 sidecar"
(cd "$ISO_OUT_DIR" && sha256sum "$ISO_NAME" > "$ISO_NAME.sha256")
ls -lh "$ISO_OUT_DIR/$ISO_NAME" "$ISO_OUT_DIR/$ISO_NAME.sha256"

echo "80-iso.sh done"
