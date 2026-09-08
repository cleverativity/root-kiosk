#!/usr/bin/env bash
# Idempotent install of the system packages required to build AnotterKiosk
# images (x86 and Raspberry Pi). Mirrors the dependencies used by the CI
# workflow in .github/workflows/main.yml.
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# Packages required by build_x86.sh and build_raspberry_pi.sh.
# - debootstrap, util-linux (sfdisk/losetup), dosfstools (mkfs.fat),
#   e2fsprogs (mkfs.ext4/resize2fs), zerofree, rsync, wget, xz-utils, pigz:
#   core image assembly + compression.
# - qemu-user-static, binfmt-support: run the arm64/armhf chroot for the
#   Raspberry Pi build on an x86_64 host.
# - libguestfs-tools, libarchive-tools, mount: extra image tooling used by CI.
PACKAGES=(
  debootstrap
  util-linux
  dosfstools
  e2fsprogs
  zerofree
  rsync
  wget
  xz-utils
  pigz
  mount
  libarchive-tools
  libguestfs-tools
  qemu-user-static
  binfmt-support
  # Userspace FUSE FAT driver: the Cloud Agent host kernel lacks in-kernel
  # vfat support, so the FAT boot partition is mounted via fusefat (see the
  # mount.vfat helper installed below).
  fusefat
  fuse3
)

sudo apt-get update -qq
sudo apt-get install -y -qq --no-install-recommends \
  -o Dpkg::Options::=--force-confdef \
  -o Dpkg::Options::=--force-confold \
  "${PACKAGES[@]}"

# The Cloud Agent VM shares a host kernel with loop max_part=0, so
# `losetup -P` cannot create /dev/loopNpM partition nodes. Install a shim
# (ahead of /usr/sbin in sudo's secure_path) that uses partx to create those
# nodes, letting the unmodified build scripts run here. See losetup-shim.sh.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sudo install -m 0755 "${SCRIPT_DIR}/losetup-shim.sh" /usr/local/sbin/losetup

# This VM's host kernel has no in-kernel vfat support and no loadable modules,
# so mounting the FAT boot partition fails. Install a mount.vfat helper that
# routes vfat mounts through the userspace FUSE FAT driver (fusefat). See
# mount.vfat for details.
sudo install -m 0755 "${SCRIPT_DIR}/mount.vfat" /sbin/mount.vfat

echo "AnotterKiosk build dependencies installed."
