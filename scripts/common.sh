#!/bin/bash
# common.sh — shared helpers for every build stage. Sourced, never executed.

BUILD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

say()  { printf '%s\n' "===== $* ====="; }
step() { printf '%s\n' "----- $*"; }
die()  { printf '%s\n' "FATAL: $*" >&2; exit 1; }

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "required command '$1' is missing; install it and re-run"
}

# Chroot stages call this after any step that removes or reconfigures
# packages: if one of the packages the live session honestly needs is gone,
# fail here with the stage's name in the log instead of at the QEMU boot or
# the manifest check, where the cause is two stages away and untraceable.
verify_live_packages() {
    local missing=""
    for p in casper sddm metacity network-manager linux-image-generic; do
        dpkg-query -W -f='${db:Status-Status} ${binary:Package}\n' "$p" 2>/dev/null \
            | grep -qx "installed $p" || missing="$missing $p"
    done
    [ -z "$missing" ] || die "live-runtime packages missing after this stage:$missing"
}

# Load config values (flavor.conf) unless the caller already did.
ensure_flavor_config() {
    # shellcheck disable=SC1091
    . "$BUILD_ROOT/config/flavor.conf"
}

# Probe the archive for a published suite.
verify_suite_available() {
    local suite="$1"
    curl -fsSL -o /dev/null --max-time 30 --retry 3 \
        "$APT_MIRROR/dists/${suite}/Release" 2>/dev/null
}

# Resolve the Ubuntu suite to build the rootfs from.
#   $NEXWM_BASE_SUITE set outside  -> used verbatim after a probe
#   UBUNTU_BASE=AUTO_LTS (default) -> first suite of UBUNTU_LTS_SUITES that is
#                                     published, i.e. the newest stable LTS
#                                     without editing every two years (the
#                                     list in flavor.conf is maintained).
# Printed to stdout.
resolve_base_suite() {
    local suite="${NEXWM_BASE_SUITE:-${UBUNTU_BASE:-AUTO_LTS}}"
    if [ "$suite" != "AUTO_LTS" ] && [ "$suite" != "AUTO" ]; then
        verify_suite_available "$suite" || die "suite '$suite' is not published on $APT_MIRROR"
        echo "$suite"
        return 0
    fi
    local candidate suites
    suites="${UBUNTU_LTS_SUITES:-noble}"
    for candidate in $suites; do
        if verify_suite_available "$candidate"; then
            echo "$candidate"
            return 0
        fi
        echo "note: suite '$candidate' is not published on $APT_MIRROR; trying the next one" >&2
    done
    die "could not resolve an Ubuntu suite on $APT_MIRROR; set NEXWM_BASE_SUITE=<codename> explicitly"
}

# Run a command inside the rootfs chroot.
chroot_run() {
    # $1 = rootfs dir, rest = command
    local root="$1"; shift
    chroot "$root" /bin/bash -lc "$*"
}

# Best-effort recursive unmount helper for chroot pseudo-filesystems.
teardown_mounts() {
    local root="$1"

    mountpoint -q "$root/dev/pts" 2>/dev/null && umount -l "$root/dev/pts" 2>/dev/null || true
    mountpoint -q "$root/dev/shm" 2>/dev/null && umount -l "$root/dev/shm" 2>/dev/null || true
    mountpoint -q "$root/proc"    2>/dev/null && umount -l "$root/proc"    2>/dev/null || true
    mountpoint -q "$root/sys"     2>/dev/null && umount -l "$root/sys"     2>/dev/null || true
    mountpoint -q "$root/run"     2>/dev/null && umount -l "$root/run"     2>/dev/null || true
    mountpoint -q "$root/dev"     2>/dev/null && umount -l "$root/dev"     2>/dev/null || true
    mountpoint -q "$root/repo"    2>/dev/null && umount -l "$root/repo"    2>/dev/null || true
    mountpoint -q "$root/var/cache/apt/archives" 2>/dev/null && umount -l "$root/var/cache/apt/archives" 2>/dev/null || true
    # Belt and braces: anything still mounted under the rootfs path.
    local mounts
    while true; do
        mounts=$(awk -v r="$root" '$2 ~ r { print $2 }' /proc/mounts 2>/dev/null | sort -r)
        [ -n "$mounts" ] || break
        echo "$mounts" | while read -r m; do umount -l "$m" 2>/dev/null || true; done
        sleep 1
    done
}
