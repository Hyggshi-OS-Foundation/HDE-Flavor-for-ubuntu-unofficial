#!/bin/bash
# 60-cleanup-rootfs.sh — in-chroot: strip package-manager and runtime cruft so
# the squashfs (and therefore the ISO) stays small, and unmask service starts
# again (this file deletes the policy mask installed by build.sh).

set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../common.sh"
ensure_flavor_config

step "rootfs hygiene before squashfs"
rm -f /usr/sbin/policy-rc.d
# Compiler toolchain leftovers from the HDE build (-dev packages have no
# runtime role in an installed desktop system).
apt-get purge -y --allow-remove-essential \
    $(dpkg-query -W -f='${binary:Package}\n' | grep -E '(-dev|-dbg)$') 2>/dev/null || true
apt-get autoremove -y --purge || true
apt-get clean
rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*.deb /var/cache/apt/archives/partial
journalctl --rotate --vacuum-time=1s 2>/dev/null || rm -rf /var/log/journal
rm -rf /tmp/* /var/tmp/* /root/.cache/* 2>/dev/null || true
: > /var/log/dpkg.log
: > /var/log/apt/term.log
: > /var/log/apt/history.log
rm -rf /tmp/nexwm-src   # provenance lives in the build logs, not the ISO

echo "60-cleanup-rootfs.sh done"
