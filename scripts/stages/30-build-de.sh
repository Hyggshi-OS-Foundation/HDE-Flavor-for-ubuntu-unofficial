#!/bin/bash
# 30-build-de.sh — run inside the rootfs chroot: build HDE (the NexWM desktop)
# from the NexWM repository and install it. The repository's own in-chroot
# builder (packaging/hyggshi-os/build-nexwm.sh) does the heavy lifting: build
# deps, make, make check-full, session metadata, runtime library retention
# and build-tool cleanup. This stage only wires the local source into it.

set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../common.sh"
ensure_flavor_config

SRC_IN_CHROOT="${SRC_IN_CHROOT:-/tmp/nexwm-src}"

step "apply the pinned-source patches carried by this repo"
# patches/ documents *why* each pinned-source change exists. They stay here
# until the fix lands in the upstream repository and the pinned ref picks it
# up; `patch --forward` is a no-op once the upstream source already has the
# change.
for p in /repo/patches/*.patch; do
    [ -e "$p" ] || continue
    command -v patch >/dev/null 2>&1 || die "patch(1) is not available in the chroot: cannot apply $(basename "$p")"
    patch --forward -d "$SRC_IN_CHROOT" -p1 < "$p" || die "$(basename "$p") did not apply to the pinned HDE source"
    echo "applied $(basename "$p")"
done

BUILD_SCRIPT="$SRC_IN_CHROOT/$HDE_BUILD_SCRIPT"

[ -f "$BUILD_SCRIPT" ] || die "HDE build script not found at $BUILD_SCRIPT (the orchestrator copies the checkout into the chroot)"

step "build HDE with the repository's own in-chroot builder"
export NEXWM_LOCAL_SRC="$SRC_IN_CHROOT"   # build the pinned checkout, no clone
export HDE_RUNTIME=full                   # network/volume/power features on
export DEBUG_MODE=true                    # verbose in the CI log
bash "$BUILD_SCRIPT"

step "verify the sessions a login screen sees"
ls -1 /usr/share/xsessions/
[ -f /usr/share/xsessions/hde.desktop ] || die "hde.desktop session missing"
[ -f /usr/share/xsessions/nexwm.desktop ] || die "nexwm.desktop session missing"
[ -f /usr/share/wayland-sessions/hde-wayland.desktop ] || true

echo "30-build-de.sh done"
