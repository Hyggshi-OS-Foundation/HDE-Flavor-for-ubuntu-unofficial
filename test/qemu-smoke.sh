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
# /dev/kvm can exist yet be unusable ("Permission denied"); only ask for it
# when this user can really open it, otherwise go straight to TCG.
{ [ -r /dev/kvm ] && [ -w /dev/kvm ]; } || ACCEL="tcg"
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
        find_ovmf || { ls -l /usr/share/OVMF /usr/share/ovmf 2>&1 >&2 || true
                       die "no matching OVMF CODE/VARS pair found (install the ovmf package)"; }
        echo "uefi firmware: $OVMF_CODE_PATH + $OVMF_VARS_PATH"
        cp "$OVMF_VARS_PATH" "$TMPDIR/OVMF_VARS.fd" || die "could not copy $OVMF_VARS_PATH"
        cmd+=(
            -drive "if=pflash,format=raw,readonly=on,file=$OVMF_CODE_PATH"
            -drive "if=pflash,format=raw,file=$TMPDIR/OVMF_VARS.fd"
        )
    fi

    say "$mode boot start"
    : > "$log"
    "${cmd[@]}" &
    QEMU_PID=$!

    show_log() {   # the cause of a boot failure is at the top; the tail is a stack trace
        echo "----- first 120 lines of the $mode serial log" >&2
        head -n 120 "$log" >&2 || true
        echo "----- last 25 lines" >&2
        tail -n 25 "$log" >&2 || true
    }

    # Wait for either the desktop marker, a panic, a timeout, or QEMU exiting early.
    local waited=0
    while kill -0 "$QEMU_PID" 2>/dev/null; do
        if grep -qE 'Kernel panic - not syncing|Gave up waiting for root|Unable to find a (medium|live)' "$log" 2>/dev/null; then
            echo "$mode: boot failure detected after ${waited}s (not waiting for the timeout)" >&2
            show_log
            kill "$QEMU_PID" 2>/dev/null || true
            return 1
        fi
        if grep -q "$MARKER" "$log" 2>/dev/null; then
            echo "$mode: desktop marker seen after ${waited}s"
            sleep 3
            kill "$QEMU_PID" 2>/dev/null || true
            return 0
        fi
        sleep 5; waited=$((waited + 5))
        if [ "$waited" -ge $((BOOT_TIMEOUT + DESKTOP_TIMEOUT)) ]; then
            echo "$mode: TIMEOUT" >&2
            show_log
            kill "$QEMU_PID" 2>/dev/null || true
            return 1
        fi
    done
    # QEMU exited without the marker: boot failure or a kernel panic.
    echo "$mode: QEMU exited without the desktop marker (waited ${waited}s)" >&2
    show_log
    return 1
}

# Find a matching OVMF CODE/VARS pair. Ubuntu 24.04's ovmf package ships the
# 4 MiB images (OVMF_CODE_4M.fd + OVMF_VARS_4M.fd); older releases ship
# OVMF_CODE.fd + OVMF_VARS.fd. CODE and VARS must be the same size class, so
# they are only ever taken as a pair. The non-secboot variants are used: the
# ISO's standalone GRUB is not signed.
find_ovmf() {
    local dir pair code vars
    for dir in ${NEXWMOS_OVMF_DIRS:-/usr/share/OVMF /usr/share/ovmf}; do
        for pair in OVMF_CODE_4M.fd:OVMF_VARS_4M.fd OVMF_CODE.fd:OVMF_VARS.fd; do
            code="${pair%%:*}"; vars="${pair##*:}"
            if [ -f "$dir/$code" ] && [ -f "$dir/$vars" ]; then
                OVMF_CODE_PATH="$dir/$code"; OVMF_VARS_PATH="$dir/$vars"
                return 0
            fi
        done
    done
    return 1
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
