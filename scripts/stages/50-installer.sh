#!/bin/bash
# 50-installer.sh — run inside the rootfs chroot: install the Calamares
# installer with the flavor's settings, branding and launcher.

set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../common.sh"
ensure_flavor_config

REPO_DIR="${REPO_DIR:?}"
export DEBIAN_FRONTEND=noninteractive

step "install Calamares packages"
packages=$(awk '!/^#/ && NF { print }' "$REPO_DIR/config/packages/installer.list")
# shellcheck disable=SC2086
apt-get install -y --no-install-recommends $packages
command -v calamares >/dev/null 2>&1 || die "calamares did not install (is it published for this suite?)"

step "Calamares settings"
mkdir -p /etc/calamares/modules
cp "$REPO_DIR/config/calamares/settings.conf" /etc/calamares/settings.conf
cp "$REPO_DIR"/config/calamares/modules/*.conf /etc/calamares/modules/

step "Calamares branding (search path: /usr/share/calamares/branding)"
mkdir -p /usr/share/calamares/branding
cp -a "$REPO_DIR/config/calamares/branding/nexwm-os" /usr/share/calamares/branding/
# Stamp the branding with this build's base versions (same placeholders as
# config/os-release).
sed -i -e "s/__VERSION__/$BASE_VERSION/g" -e "s/__CODENAME__/$BASE_SUITE/g" \
    /usr/share/calamares/branding/nexwm-os/branding.desc
grep -q "$BASE_VERSION" /usr/share/calamares/branding/nexwm-os/branding.desc \
    || die "branding version stamping failed"

step "installer launcher"
install -m 0755 "$REPO_DIR/config/usr/bin/calamares-launch-nexwm-os" \
    /usr/bin/calamares-launch-nexwm-os
install -m 0644 "$REPO_DIR/config/usr/share/applications/install-nexwm-os.desktop" \
    /usr/share/applications/install-nexwm-os.desktop

step "verify the branding the running installer will pick up"
[ -f /etc/calamares/settings.conf ] || die "settings.conf missing"
grep -q "^branding: nexwm-os$" /etc/calamares/settings.conf || die "branding component not wired"
[ -f /usr/share/calamares/branding/nexwm-os/branding.desc ] || die "branding.desc missing"
# language pack source list for the packages module already exists (copied
# from the live sources), so try_install has somewhere to download from.
[ -f /etc/apt/sources.list ] || die "apt sources missing for the packages module"

echo "50-installer.sh done"
