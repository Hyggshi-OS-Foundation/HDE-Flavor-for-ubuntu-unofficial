#!/bin/bash
# 40-branding.sh — run inside the rootfs chroot: put the flavor's own identity
# and live-session plumbing in place (os-release, SDDM defaults, casper
# configuration, live autologin unit, smoke-check unit, welcome text).

set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../common.sh"
ensure_flavor_config

REPO_DIR="${REPO_DIR:?}"
BASE_VERSION="${BASE_VERSION:?}"      # e.g. 24.04
BASE_SUITE="${BASE_SUITE:?}"

step "os-release / lsb-release / issue"
# Fill the placeholders of config/os-release with the Ubuntu base versions.
sed -e "s/__VERSION__/$BASE_VERSION/g" -e "s/__CODENAME__/$BASE_SUITE/g" \
    "$REPO_DIR/config/os-release" > /usr/lib/os-release
chmod 0644 /usr/lib/os-release
# On Ubuntu rootfs, /etc/os-release is a symlink to /usr/lib/os-release: the
# content above is already both. Only when something diverged (not a symlink)
# refresh /etc explicitly.
[ -L /etc/os-release ] || cp /usr/lib/os-release /etc/os-release
if command -v lsb_release >/dev/null 2>&1; then
    {
        echo "DISTRIB_ID=nexwmos"
        echo "DISTRIB_RELEASE=$BASE_VERSION"
        echo "DISTRIB_CODENAME=$BASE_SUITE"
        echo "DISTRIB_DESCRIPTION=\"$FLAVOR_PRETTY $BASE_VERSION (based on Ubuntu)\""
    } > /etc/lsb-release
fi
printf '%s %s \\n \\l\n\n' "$FLAVOR_PRETTY" "$BASE_VERSION" > /etc/issue
chown root:root /etc/issue 2>/dev/null || true
chmod 0644 /etc/issue

step "default session for SDDM (51 after the theme's own 50-hde-theme.conf)"
mkdir -p /etc/sddm.conf.d
cat > /etc/sddm.conf.d/51-nexwm-os-defaults.conf <<EOF
# Written by the NexWM OS flavor build. SDDM merges /etc/sddm.conf.d in
# lexicographic order; this file may only refine what login/sddm/install.sh
# already wrote. Session ids are the desktop-file ids without the
# .desktop suffix (the upstream default form, e.g. "plasma").
[Users]
DefaultSession=$HDE_DEFAULT_SESSION

[Autologin]
Session=$HDE_DEFAULT_SESSION
EOF

step "casper live configuration"
cat > /etc/casper.conf <<EOF
# Live medium configuration for $FLAVOR_PRETTY.
# FLAVOUR is set on purpose: casper would otherwise derive USERNAME and HOST
# from the first word of /cdrom/.disk/info.
export USERNAME="$LIVE_USERNAME"
export USERFULLNAME="$LIVE_USERFULLNAME"
export HOST="$LIVE_HOST"
export BUILD_SYSTEM="Ubuntu"
export FLAVOUR="$LIVE_FLAVOUR"
EOF
chmod 0644 /etc/casper.conf

step "live autologin (per-boot SDDM configuration)"
install -d /usr/lib/nexwm-os
install -m 0755 "$REPO_DIR/config/usr/lib/nexwm-os/live-autologin" /usr/lib/nexwm-os/live-autologin
install -m 0644 "$REPO_DIR/config/systemd/nexwm-os-live-autologin.service" \
    /etc/systemd/system/nexwm-os-live-autologin.service
mkdir -p /etc/systemd/system/multi-user.target.wants
ln -sf /etc/systemd/system/nexwm-os-live-autologin.service \
    /etc/systemd/system/multi-user.target.wants/nexwm-os-live-autologin.service

step "live desktop smoke check (used by the QEMU test on GitHub Actions)"
install -m 0755 "$REPO_DIR/config/usr/nexwm-os-live-check" /usr/bin/nexwm-os-live-check
install -m 0644 "$REPO_DIR/config/systemd/nexwm-os-live-check.service" \
    /etc/systemd/system/nexwm-os-live-check.service
mkdir -p /etc/systemd/system/graphical.target.wants
ln -sf /etc/systemd/system/nexwm-os-live-check.service \
    /etc/systemd/system/graphical.target.wants/nexwm-os-live-check.service

# netboot friendly: casper writes history; keep that default and nothing else.
verify_live_packages
echo "40-branding.sh done"
