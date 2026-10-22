#!/bin/bash
# 20-install-base.sh — run inside the rootfs chroot: apt update, install the
# base package set (kernel + casper + X + SDDM + desktop infrastructure),
# update the initramfs so the casper hooks are inside it, and turn the system
# to the graphical target so the live medium boots to SDDM.

set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../common.sh"
ensure_flavor_config

ROOTFS="${ROOTFS:?}"
BASE_SUITE="${BASE_SUITE:?}"
REPO_DIR="${REPO_DIR:?}"

[ -d "$ROOTFS/proc" ] || die "chroot not mounted; the orchestrator mounts $ROOTFS before chroot stages"

export DEBIAN_FRONTEND=noninteractive

step "apt update"
apt-get update -qq
apt-get upgrade -y -qq

step "install base package set"
# Read the package list (plain names, comments skipped); the list is version
# controlled so nothing needs a denylist.
packages=$(awk '!/^#/ && NF { print }' "$REPO_DIR/config/packages/base.list")
# shellcheck disable=SC2086
apt-get install -y --no-install-recommends \
    --option=Dpkg::Options::="--force-confnew" \
    $packages

step "timezone and locale defaults (UTC + C.UTF-8 until the user installs)"
ln -sf /usr/share/zoneinfo/Etc/UTC /etc/localtime
echo "C.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen >/dev/null
localectl set-locale LANG=C.UTF-8 2>/dev/null || true

step "initramfs (casper hooks) + kernel polish"
depmod -a "$(ls -1 /lib/modules | sort -V | tail -n1)"
update-initramfs -u -k all

step "force graphical.target as the default boot target for the live medium"
ln -sf /lib/systemd/system/graphical.target /etc/systemd/system/default.target

step "enable the display manager (SDDM) for the live medium"
systemctl enable sddm.service 2>/dev/null || \
    ln -sf /lib/systemd/system/sddm.service /etc/systemd/system/display-manager.service

echo "20-install-base.sh done"
