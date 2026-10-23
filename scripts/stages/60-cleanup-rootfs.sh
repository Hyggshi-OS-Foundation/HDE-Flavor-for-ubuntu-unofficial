#!/bin/bash
# 60-cleanup-rootfs.sh — in-chroot: strip package-manager and runtime cruft so
# the squashfs (and therefore the ISO) stays small, and unmask service starts
# again (this file deletes the policy mask installed by build.sh).

set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../common.sh"
ensure_flavor_config

step "rootfs hygiene before squashfs"
rm -f /usr/sbin/policy-rc.d
# SDDM/live machinery installs sudo as a dependency; autoremove below then
# tries to remove it and sudo's own pre-removal script refuses, which halts
# dpkg half-way through the -dev purge. Mark it (and the live runtime it
# serves) as wanted before purging.
apt-mark manual sudo 2>/dev/null || true
# Compiler toolchain leftovers from the HDE build (-dev packages have no
# runtime role in an installed desktop system).
apt-get purge -y --allow-remove-essential \
    $(dpkg-query -W -f='${binary:Package}\n' | grep -E '(-dev|-dbg)$') 2>/dev/null || true

step "protect the live runtime before autoremove"
# casper, the display manager, the desktop and the network stack were all
# installed manually by earlier stages, but marks can be rewritten when
# dependency graphs change under the -dev purge above: state it explicitly so
# autoremove keeps them.
apt-mark manual casper sddm metacity network-manager linux-generic \
    linux-image-generic 2>/dev/null || true

step "autoremove plan preflight"
# autoremove has removed live-runtime packages before; ask it for its plan
# first and refuse to run it when it lists any of the packages the live
# system needs. The printed plan also documents HOW apt came to see them as
# removable (orphan dependency). It names every entry and halts.
PLAN=$(apt-get --assume-no autoremove --purge 2>/dev/null || true)
if printf '%s\n' "$PLAN" | grep -qE '\b(casper|sddm|network-manager|metacity|linux-image-generic)\b'; then
    printf '%s\n' "$PLAN" | grep -E 'REMOV|casper|sddm|network-manager|metacity|linux-image' | head -n 20 >&2
    die "autoremove is planning to remove live-runtime packages (see the plan above)"
fi
apt-get autoremove -y --purge || true

step "verify the live runtime survived the cleanup"
# A purged casper, display manager or network manager turns the build into an
# ISO that boots to no session and cannot install anything; verify_live_packages
# names the entry and halts with the stage in the log.
verify_live_packages
rm -rf /var/lib/apt/lists/*
# NOTE: the apt archives dir is bind-mounted to the CI-shared cache while the
# chroot stages run; build.sh unmounts it and empties the chroot-side copy
# after this stage. Do NOT apt-get clean or rm the archives here: it would
# erase the shared cache and cost a full re-download next run.
journalctl --rotate --vacuum-time=1s 2>/dev/null || rm -rf /var/log/journal
rm -rf /tmp/* /var/tmp/* /root/.cache/* 2>/dev/null || true
: > /var/log/dpkg.log
: > /var/log/apt/term.log
: > /var/log/apt/history.log
rm -rf /tmp/nexwm-src   # provenance lives in the build logs, not the ISO

echo "60-cleanup-rootfs.sh done"
