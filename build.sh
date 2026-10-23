#!/bin/bash
# build.sh — orchestrate a full NexWM OS ISO build from this repository.
#
# Usage:
#   sudo ./build.sh [--base-suite SUITE] [--workdir DIR] [--fresh]
#
# Env overrides:
#   NEXWM_BASE_SUITE   codename of the Ubuntu suite (overrides the config default)
#   HDE_REPO_REF       branch or tag of HDE/NexWM to build (default from flavor.conf)
#
# Everything is created under WORKDIR (default /srv/nexwm-os-build):
#   rootfs/   the debootstrapped, desktop-enabled Ubuntu base system
#   iso/      the staged casper medium (pre-xorriso tree)
#   out/      the built ISO plus its sha256 sidecar
#   logs/     one log per build stage (kept as CI artifacts)
#   hde/      the pinned HDE (NexWM) source checkout the DE is built from
#
# Stages (scripts/stages/):
#   host, 10   debootstrap the Ubuntu base rootfs
#   chroot,20  install the base package set + casper initramfs
#   chroot,25  purge the GNOME packages (the flavor's own safety net)
#   chroot,30  build HDE with the repository's in-chroot builder
#   chroot,35  install the HDE SDDM login theme
#   chroot,40  flavor identity, casper live configuration, smoke-check units
#   chroot,50  install the Calamares installer with flavor settings
#   chroot,60  rootfs hygiene before squashing
#   host, 70   squashfs + casper metadata
#   host, 80   bootloaders + xorriso: the final hybrid ISO
#   host, 90   preflight checks on the medium

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
REPO_DIR="$PWD"

# shellcheck disable=SC1091
. scripts/common.sh
ensure_flavor_config

WORK_DIR="${WORK_DIR:-/srv/nexwm-os-build}"
BASE_SUITE="${NEXWM_BASE_SUITE:-}"
WANT_FRESH=0
while [ $# -gt 0 ]; do
    case "$1" in
        --base-suite) BASE_SUITE="$2"; shift 2 ;;
        --workdir)    WORK_DIR="$2"; shift 2 ;;
        --fresh)      WANT_FRESH=1; shift ;;
        *) die "unknown argument: $1 (supported: --base-suite, --workdir, --fresh)" ;;
    esac
done

[ "$(id -u)" = 0 ] || die "run as root (sudo ./build.sh): debootstrap + chroot mounts need root privileges"

ROOTFS="$WORK_DIR/rootfs"
ISO_STAGE="$WORK_DIR/iso"
OUT_DIR="$WORK_DIR/out"
LOG_DIR="$WORK_DIR/logs"
HDE_SRC="$WORK_DIR/hde"
APT_CACHE_DIR="$WORK_DIR/apt-cache"   # survives --fresh; CI caches it across runs
BUILD_LOG_DIR="$LOG_DIR"
export REPO_DIR WORK_DIR ROOTFS ISO_STAGE OUT_DIR LOG_DIR HDE_SRC BUILD_LOG_DIR APT_CACHE_DIR

say "NexWM OS build (repo: $(git -C "$REPO_DIR" rev-parse HEAD 2>/dev/null || echo 'no git'))"

if [ "$WANT_FRESH" = 1 ] && [ -d "$WORK_DIR" ]; then
    say "clean the previous working tree"
    teardown_mounts "$ROOTFS"
    rm -rf "$WORK_DIR"
fi
mkdir -p "$WORK_DIR" "$ROOTFS" "$ISO_STAGE" "$OUT_DIR" "$LOG_DIR"

step "host dependencies"
bash "$REPO_DIR/tools/install-host-deps.sh" 2>&1 | tee "$LOG_DIR/00-host-deps.log"

if [ -z "$BASE_SUITE" ]; then
    step "resolve the Ubuntu base suite"
    BASE_SUITE="$(resolve_base_suite)"
fi
say "Ubuntu base suite: $BASE_SUITE"
say "HDE ref: $HDE_REPO_REF from $HDE_REPO_URL"

export BASE_SUITE

step "pin the HDE (NexWM) source the desktop is built from"
if [ ! -d "$HDE_SRC/.git" ]; then
    git clone --depth 1 --branch "$HDE_REPO_REF" "$HDE_REPO_URL" "$HDE_SRC"
fi
HDE_SHA="$(git -C "$HDE_SRC" rev-parse HEAD)"
HDE_WHEN="$(git -C "$HDE_SRC" log -1 --format=%cI)"
{
    printf 'HDE repository : %s\n' "$HDE_REPO_URL"
    printf 'HDE ref        : %s\n' "$HDE_REPO_REF"
    printf 'HDE commit     : %s (%s)\n' "$HDE_SHA" "$HDE_WHEN"
    printf 'ISO built at   : %s\n' "$(date -uIs)"
} > "$WORK_DIR/hde-provenance.txt"
cat "$WORK_DIR/hde-provenance.txt"

# ---------------------------------------------------------------------------
# Host stage 10: bootstrap the base rootfs.
# ---------------------------------------------------------------------------
say "stage 10: debootstrap"
bash "$REPO_DIR/scripts/stages/10-bootstrap-rootfs.sh" 2>&1 | tee "$LOG_DIR/10-bootstrap.log"

BASE_VERSION="$(sed -n 's/^VERSION_ID=\"\{0,1\}\([^\"]*\)\"\{0,1\}$/\1/p' "$ROOTFS/etc/os-release" | head -n1)"
export BASE_VERSION
[ -n "$BASE_VERSION" ] || die "could not read VERSION_ID from the debootstrapped /etc/os-release"
say "base version: Ubuntu $BASE_VERSION ($BASE_SUITE)"

# ---------------------------------------------------------------------------
# Chroot preparation: pseudo-filesystems, resolv.conf, policy mask, /repo.
# ---------------------------------------------------------------------------
say "mount the chroot"
mkdir -p "$ROOTFS/dev/pts" "$ROOTFS/dev/shm" "$ROOTFS/proc" "$ROOTFS/sys" "$ROOTFS/run" "$ROOTFS/tmp" "$ROOTFS/repo"
mount --bind /dev "$ROOTFS/dev"
mount --bind /dev/pts "$ROOTFS/dev/pts"
mount -t proc proc "$ROOTFS/proc"
mount --bind /sys "$ROOTFS/sys"
mount -t tmpfs tmpfs "$ROOTFS/run"
mount -t tmpfs tmpfs "$ROOTFS/tmp"
mount --bind "$REPO_DIR" "$ROOTFS/repo"

# The APT package cache: debootstrap (stage 10) already downloaded into
# APT_CACHE_DIR; stages 20..60 download through this bind so the cache
# survives the --fresh rootfs wipe and the CI job caches it across runs.
# build.sh unmounts it again after stage 60 (stage 60's old apt-get clean
# would otherwise empty the shared cache) before the squashfs stage.
mkdir -p "$ROOTFS/var/cache/apt/archives" "$APT_CACHE_DIR"
mount --bind "$APT_CACHE_DIR" "$ROOTFS/var/cache/apt/archives"

cp /etc/resolv.conf "$ROOTFS/etc/resolv.conf"
cat > "$ROOTFS/usr/sbin/policy-rc.d" <<'EOF'
#!/bin/sh
# During rootfs packaging no service may start in this chroot: it has no
# console. The file is removed by the hygiene stage.
exit 101
EOF
chmod 0755 "$ROOTFS/usr/sbin/policy-rc.d"

step "copy the pinned HDE checkout into the chroot"
rm -rf "$ROOTFS/tmp/nexwm-src"
cp -a "$HDE_SRC" "$ROOTFS/tmp/nexwm-src"

# ---------------------------------------------------------------------------
# Chroot stages 20..60. REPO_DIR rebinding keeps the scripts portable.
# ---------------------------------------------------------------------------
CHROOT_ENV="env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin \
    HOME=/root TERM=${TERM:-xterm-256color} \
    REPO_DIR=/repo ROOTFS=/ BASE_SUITE=$BASE_SUITE BASE_VERSION=$BASE_VERSION \
    SRC_IN_CHROOT=/tmp/nexwm-src DEBIAN_FRONTEND=noninteractive"

run_chroot_stage() {
    local stage="$1"
    say "chroot stage $stage"
    chroot "$ROOTFS" $CHROOT_ENV bash "/repo/scripts/stages/$stage.sh" \
        2>&1 | tee "$LOG_DIR/$stage.log"
}

run_chroot_stage 20-install-base
run_chroot_stage 25-remove-gnome
run_chroot_stage 30-build-de
run_chroot_stage 35-sddm-login
run_chroot_stage 40-branding
run_chroot_stage 50-installer
run_chroot_stage 60-cleanup-rootfs

# Restore the chroot's own cache files before the shared host cache would be
# confused for them: unmount the bind, then empty the chroot-side archives so
# the squashfs does not carry package files (stage 60 can no longer do this
# itself without wiping the shared cache). /var/lib/apt/lists is still emptied
# by stage 60 before this point, inside the chroot.
if mountpoint -q "$ROOTFS/var/cache/apt/archives"; then
    umount -l "$ROOTFS/var/cache/apt/archives"
    rm -rf "$ROOTFS/var/cache/apt/archives/"* "$ROOTFS/var/cache/apt/archives/partial"
fi
echo "$(du -sh "$APT_CACHE_DIR" | cut -f1) of apt packages cached before eviction"
# Keep the CI cache bounded. NOTE: do NOT prune by -mtime — apt stamps .deb
# files with the archive mirror's own mtime (their release date), not the
# download date, so an mtime-based prune would empty the cache after every
# run. Evict whole files oldest-first while the cache exceeds 5 GiB instead,
# which keeps the commonly reused recent packages and stays under the
# repository's cache allowance with room to spare.
while [ "$(du -sm "$APT_CACHE_DIR" 2>/dev/null | cut -f1)" -gt 5000 ]; do
    oldest=$(find "$APT_CACHE_DIR" -name '*.deb' -type f -printf '%T@ %p\n' | sort -n | head -n 1 | cut -d' ' -f2-)
    [ -n "$oldest" ] || break
    rm -f "$oldest"
done
echo "$(du -sh "$APT_CACHE_DIR" | cut -f1) of apt packages cached for the next run"
# Make the shared bundle stashable by the CI runner user: apt (run as root
# through the chroot bind) leaves a root-owned lock file and partial dir,
# and the cache/save tar cannot read them.
rm -rf "$APT_CACHE_DIR/lock" "$APT_CACHE_DIR/partial"
chmod -R a+rX "$APT_CACHE_DIR"

# ---------------------------------------------------------------------------
# Teardown, then host stages 70..90.
# ---------------------------------------------------------------------------
say "unmount the chroot"
teardown_mounts "$ROOTFS"

say "host stage 71: squashfs"
bash "$REPO_DIR/scripts/stages/70-squashfs.sh" 2>&1 | tee "$LOG_DIR/70-squashfs.log"

say "host stage 80: bootloaders + xorriso"
export ISO_NAME="nexwm-os-$BASE_VERSION-desktop-amd64.iso" ISO_OUT_DIR="$OUT_DIR"
bash "$REPO_DIR/scripts/stages/80-iso.sh" 2>&1 | tee "$LOG_DIR/80-iso.log"

say "host stage 90: preflight checks"
bash "$REPO_DIR/scripts/stages/90-report.sh" 2>&1 | tee "$LOG_DIR/90-report.log"

say "done"
echo "ISO: $OUT_DIR/$ISO_NAME"
