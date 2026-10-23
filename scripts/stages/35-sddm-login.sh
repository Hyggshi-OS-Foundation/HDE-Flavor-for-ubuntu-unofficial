#!/bin/bash
# 35-sddm-login.sh — run inside the rootfs chroot: install the HDE SDDM login
# theme from login/sddm and let SDDM use it. Defaults to the full HDE session;
# the flavor-level default session (nexwm) is preselected by 40-branding.sh.

set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../common.sh"
ensure_flavor_config

SRC_IN_CHROOT="${SRC_IN_CHROOT:-/tmp/nexwm-src}"

step "install the HDE SDDM theme"
bash "$SRC_IN_CHROOT/login/sddm/install.sh"

if ! [ -d /usr/share/sddm/themes/hde ]; then die "HDE SDDM theme not installed"; fi

verify_live_packages
echo "35-sddm-login.sh done"
