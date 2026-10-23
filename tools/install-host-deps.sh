#!/bin/bash
# install-host-deps.sh — host (runner) dependencies for a NexWM OS ISO build.
# Runs as root on the build host (GitHub Actions runner or any Ubuntu host).

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
apt-get install -y --no-install-recommends \
    debootstrap \
    xorriso \
    squashfs-tools \
    isolinux syslinux-common \
    grub-common grub-pc-bin grub-efi-amd64-bin \
    mtools \
    initramfs-tools-core \
    dosfstools \
    curl \
    git \
    qemu-system-x86 \
    ovmf

echo "install-host-deps.sh done"
