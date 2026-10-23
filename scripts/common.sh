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
    [ -z "$missing" ] || die "live-runtime packages missing after this stage:$missing (apt marks these as manually installed: $(apt-mark showmanual 2>/dev/null | grep -E '^(casper|sddm|network-manager|metacity|linux-image-generic)' | tr '\n' ' '))"
}

# Purge -dev/-dbg packages WITHOUT dragging anything else down with them.
# `apt-get purge libfoo-dev` also removes every package that depends on it, and
# `apt-mark manual` does not stop that when the removal is requested by name
# (this is how casper, sddm and network-manager used to vanish). So: simulate
# first, and only purge the candidates whose removal plan contains nothing but
# -dev/-dbg packages. Anything that would take a runtime package with it stays.
safe_purge_dev_packages() {
    local re='-(dev|dbg)$'
    local -a cands=() safe=()
    local pkg name plan bad

    mapfile -t cands < <(dpkg-query -W -f='${db:Status-Status} ${binary:Package}\n' \
        | awk '$1 == "installed" { print $2 }' | grep -E -e '-(dev|dbg)(:[a-z0-9]+)?$' || true)
    [ "${#cands[@]}" -gt 0 ] || { echo "no -dev/-dbg packages installed"; return 0; }

    # collateral = names in an apt plan that are not -dev/-dbg packages.
    # `apt-get -s purge` prints "Purg <pkg>" lines ("Remv" for plain remove),
    # so both prefixes must be read. Runtime packages named in the plan always
    # count as collateral, whatever the prefix.
    _collateral() {
        printf '%s\n' "$1" | awk '/^(Remv|Purg) /{ n=$2; sub(/:.*/,"",n); print n }' \
            | grep -Ev -e "$re" || true
    }
    _plan_ok() {   # $1 = plan text; fail if apt printed no plan at all
        printf '%s\n' "$1" | grep -qE '^(Remv|Purg) ' || return 1
    }

    step "simulate purging all ${#cands[@]} -dev/-dbg packages together"
    plan=$(apt-get -s purge --allow-remove-essential "${cands[@]}" 2>&1) || true
    _plan_ok "$plan" || { printf '%s\n' "$plan" >&2; die "apt simulation produced no Remv/Purg lines; refusing to purge blind"; }
    bad=$(_collateral "$plan")
    if [ -z "$bad" ]; then
        safe=("${cands[@]}")
    else
        step "collateral removals found; testing each package on its own:"
        printf '  %s\n' $bad | sort -u | head -n 40
        for pkg in "${cands[@]}"; do
            plan=$(apt-get -s purge --allow-remove-essential "$pkg" 2>&1) || continue
            [ -z "$(_collateral "$plan")" ] && safe+=("$pkg") || echo "  keeping $pkg (removal would take runtime packages with it)"
        done
    fi

    [ "${#safe[@]}" -gt 0 ] || { echo "nothing safe to purge"; return 0; }

    # Final check on the exact set we are about to purge (independent removals
    # can still interact), then purge for real with output visible.
    plan=$(apt-get -s purge --allow-remove-essential "${safe[@]}" 2>&1) || true
    _plan_ok "$plan" || { printf '%s\n' "$plan" >&2; die "final apt simulation produced no plan; refusing to purge blind"; }
    bad=$(_collateral "$plan")
    [ -z "$bad" ] || die "safe -dev set still removes non-dev packages: $(echo $bad | tr '\n' ' ')"

    step "purging ${#safe[@]} -dev/-dbg packages"
    apt-get purge -y --allow-remove-essential "${safe[@]}"
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
