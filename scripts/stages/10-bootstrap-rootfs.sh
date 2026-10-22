#!/bin/bash
# 10-bootstrap-rootfs.sh — create the Ubuntu base rootfs by debootstrapping
# the newest LTS suite. This takes the place of "download the Ubuntu ISO and
# strip GNOME": the flavor starts from the same per-suite base seeds the
# official images are built from, without ever shipping a GNOME layer to
# remove.
#
# Runs on the host (runner) as root. Expects $ROOTFS and $BASE_SUITE exported.

set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"
ensure_flavor_config

ROOTFS="${ROOTFS:?}"
BASE_SUITE="${BASE_SUITE:?}"

say "bootstrap $BASE_SUITE base filesystem into $ROOTFS"

debootstrap \
    --arch=amd64 \
    --variant=minbase \
    --components="$APT_COMPONENTS" \
    "$BASE_SUITE" "$ROOTFS" "$APT_MIRROR"

# apt sources: debootstrap writes defaults; make them explicit for the suite.
cat > "$ROOTFS/etc/apt/sources.list" <<EOF
deb $APT_MIRROR $BASE_SUITE $APT_COMPONENTS
deb $APT_MIRROR $BASE_SUITE-updates $APT_COMPONENTS
deb $APT_MIRROR $BASE_SUITE-security $APT_COMPONENTS
deb $APT_MIRROR $BASE_SUITE-backports $APT_COMPONENTS
EOF

echo "10-bootstrap-rootfs.sh done"
