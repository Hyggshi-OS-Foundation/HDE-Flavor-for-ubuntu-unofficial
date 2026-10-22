#!/bin/bash
# 25-remove-gnome.sh — run inside the rootfs chroot: purge every GNOME desktop
# package listed in config/packages/gnome-purge.list. The flavor starts from a
# minimal base so these are usually not installed at all; the purge is the
# guarantee the user asked for ("ubuntude gỡ DE gnome") and keeps a GNOME
# leak from a seed change from ever reaching the ISO.

set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../common.sh"
ensure_flavor_config

REPO_DIR="${REPO_DIR:?}"
export DEBIAN_FRONTEND=noninteractive

step "purge GNOME packages (skip packages that are not installed)"
purged=""
skipped=""
while read -r pkg; do
    case "$pkg" in ""|\#*) continue ;; esac
    if dpkg-query -W -f='${db:Status-Status}\n' "$pkg" 2>/dev/null | grep -qx "installed"; then
        apt-get purge -y --allow-remove-essential "$pkg" || true
        purged="$purged $pkg"
    else
        skipped="$skipped $pkg"
    fi
done < <(awk '!/^#/ && NF { print }' "$REPO_DIR/config/packages/gnome-purge.list")

apt-get purge -y --allow-remove-essential 'gnome-shell-extension-*' 2>/dev/null || true
apt-get autoremove -y --purge >/dev/null
apt-get clean

step "result: purged=[$([ -n "$purged" ] && echo "$purged" || echo none)] skipped-present=$([ -n "$skipped" ] && echo yes || echo no)"
echo "25-remove-gnome.sh done"
