#!/bin/bash
# qemu-smoke.sh — boot a built ISO under QEMU and wait for the live desktop.
#
# The ISO's own nexwm-os-live-check unit prints NEXWMOS_SMOKE_OK on the serial
# console (and shuts the machine down) once the HDE desktop of the casper user
# is actually up; the firmware path is exercised twice:
#     ./test/qemu-smoke.sh path/to/iso bios
#     ./test/qemu-smoke.sh path/to/iso uefi
#
# Probe logic: when /dev/kvm exists the machine uses it (fast), otherwise it
# falls back to TCG with the same timeouts. Exit code 0 = the desktop came up.

set -uo pipefail

ISO="${1:?usage: qemu-smoke.sh <iso> [bios|uefi]}"
MODE="${2:-both}"
MARKER="NEXWMOS_SMOKE_OK"
BOOT_TIMEOUT="${NEXWMOS_QEMU_BOOT_TIMEOUT:-540}"     # kernel + initramfs + squashfs unpack
DESKTOP_TIMEOUT="${NEXWMOS_QEMU_DESKTOP_TIMEOUT:-900}"  # reboot-to-desktop wait

say() { printf '\n===== %s =====\n' "$*"; }
die() { printf '\nFATAL: %s\n' "$*" >&2; exit 1; }

[ -f "$ISO" ] || die "ISO not found: $ISO"
command -v qemu-system-x86_64 >/dev/null 2>&1 || die "qemu-system-x86_64 is missing"

TMPDIR=$(mktemp -d /tmp/nexwm-qemu.XXXXXX)
trap 'rm -rf "$TMPDIR"' EXIT

ACCEL="kvm:tcg"
[ -e /dev/kvm ] || ACCEL="tcg"
echo "acceleration: $ACCEL"
SCRATCH="$TMPDIR/disk.qcow2"
qemu-img create -f qcow2 "$SCRATCH" 2G >/dev/null || die "could not create scratch disk"

run_firmware() {
    local mode="$1"
    local log="$TMPDIR/serial-$mode.log"
    local -a cmd

    cmd=(qemu-system-x86_64
        -machine "pc,accel=$ACCEL"
        -cpu max
        -m 4096 -smp 4
        -display none
        -serial "file:$log"
        -monitor none
        -no-reboot
        -drive "file=$SCRATCH,if=virtio,format=qcow2"
        -drive "file=$ISO,media=cdrom,readonly=on"
        -boot d)

    if [ "$mode" = "uefi" ]; then
        local ovmf_code ovmf_vars
        ovmf_code="$(listing_ovmf_code)"
        ovmf_vars="$(find /usr/share/OVMF /usr/share/ovmf -maxdepth 1 -name 'OVMF_VARS*.fd' 2>/dev/null | head -n1)"
        [ -n "$ovmf_code" ] || die "no OVMF firmware found (install the ovmf package)"
        cp "$ovmf_vars" "$TMPDIR/OVMF_VARS.fd" 2>/dev/null \
            || printf '' > "$TMPDIR/OVMF_VARS.fd"
        cmd+=(
            -drive "if=pflash,format=raw,readonly=on,file=$ovmf_code"
            -drive "if=pflash,format=raw,file=$TMPDIR/OVMF_VARS.fd"
        )
    fi

    say "$mode boot start"
    : > "$log"
    "${cmd[@]}" &
    QEMU_PID=$!

    # Wait for either the desktop marker, a timeout, or QEMU exiting early.
    local waited=0
    while kill -0 "$QEMU_PID" 2>/dev/null; do
        if grep -q "$MARKER" "$log" 2>/dev/null; then
            echo "$mode: desktop marker seen after ${waited}s"
            sleep 3
            kill "$QEMU_PID" 2>/dev/null || true
            return 0
        fi
        sleep 5; waited=$((waited + 5))
        if [ "$waited" -ge $((BOOT_TIMEOUT + DESKTOP_TIMEOUT)) ]; then
            echo "$mode: TIMEOUT" >&2
            tail -n 80 "$log" >&2 || true
            kill "$QEMU_PID" 2>/dev/null || true
            return 1
        fi
    done
    # QEMU exited without the marker: boot failure or a kernel panic.
    echo "$mode: QEMU exited without the desktop marker (waited ${waited}s)" >&2
    [ -s "$log" ] && tail -n 80 "$log" >&2
    return 1
}

listing_ovmf_code() {
    for candidate in \
        /usr/share/OVMF/OVMF_CODE.fd \
        /usr/share/ovmf/OVMF_CODE.fd \
        /usr/share/OVMF/OVMF_CODE.secboot.fd; do
        [ -f "$candidate" ] && { printf '%s' "$candidate"; return 0; }
    done
    printf ''
}

STATUS=0
case "$MODE" in
    bios|uefi)
        run_firmware "$MODE" || STATUS=1 ;;
    both)
        run_firmware bios  || STATUS=1
        run_firmware uefi  || STATUS=1 ;;
    *) die "unknown mode: $MODE (use bios|uefi|both)" ;;
esac

# Keep the last serial logs around for the CI artifact uploader even on pass.
mkdir -p artifacts
cp "$TMPDIR"/serial-*.log artifacts/ 2>/dev/null || true
echo "smoke summary: firmware tests completed; exit=$STATUS"
exit "$STATUS"
