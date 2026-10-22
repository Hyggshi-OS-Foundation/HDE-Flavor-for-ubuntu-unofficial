#!/bin/bash
# 10-bootstrap-rootfs.sh — create the Ubuntu base rootfs by debootstrapping
# the newest LTS suite. This takes the place of "download the Ubuntu ISO and
# strip GNOME": the flavor starts from the same per-suite base seeds the
# official images are built from, without ever shipping a GNOME layer to
# remove.
#
# Runs on the host (runner) as root. Expects $ROOTFS and $BASE_SUITE exported.

set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../common.sh"
ensure_flavor_config

ROOTFS="${ROOTFS:?}"
BASE_SUITE="${BASE_SUITE:?}"

say "bootstrap $BASE_SUITE base filesystem into $ROOTFS"

# debootstrap's --components takes a COMMA-separated list (it becomes the
# '|' alternation of a case pattern); a space-separated value is a shell
# syntax error there, and debootstrap's stderr (where it would be reported)
# goes only into its internal log. APT_COMPONENTS is space-separated for
# apt sources.list, so convert it here.
# --cache-dir keeps the downloaded .deb files outside the target so CI can
# reuse them across runs (see the job's APT cache in the workflow).
mkdir -p "$APT_CACHE_DIR"
if ! debootstrap \
    --arch=amd64 \
    --variant=minbase \
    --components="$(printf '%s' "$APT_COMPONENTS" | tr ' ' ',')" \
    --cache-dir="$APT_CACHE_DIR" \
    "$BASE_SUITE" "$ROOTFS" "$APT_MIRROR"; then
    echo "debootstrap failed; the tail of its internal log follows:" >&2
    tail -n 50 "$ROOTFS/debootstrap/debootstrap.log" 2>/dev/null || true
    exit 1
fi

# apt sources: debootstrap writes defaults; make them explicit for the suite.
cat > "$ROOTFS/etc/apt/sources.list" <<EOF
deb $APT_MIRROR $BASE_SUITE $APT_COMPONENTS
deb $APT_MIRROR $BASE_SUITE-updates $APT_COMPONENTS
deb $APT_MIRROR $BASE_SUITE-security $APT_COMPONENTS
deb $APT_MIRROR $BASE_SUITE-backports $APT_COMPONENTS
EOF

echo "10-bootstrap-rootfs.sh done"
