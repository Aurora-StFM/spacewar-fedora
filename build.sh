#!/usr/bin/env bash
# Nothing Phone (1) Fedora kit: build entry point.
#
#   ./build.sh deps                           install build dependencies (sudo)
#   ./build.sh kernel                         cross-compile kernel-spacewar
#   ./build.sh firmware                       package nothing-spacewar-firmware
#   ./build.sh support                        package nothing-spacewar-support
#   ./build.sh extras                         build hexagonrpc, qbootctl, dummystreamhack (mock)
#   sudo ./build.sh rootfs --user NAME        build rootfs.img and boot.img
#   sudo ./build.sh all --user NAME           everything above in order
#
# Run on an x86_64 (or aarch64) Fedora machine.
set -euo pipefail
. "$(dirname "$0")/lib/common.sh"

DEPS=(
    git curl make gcc clang lld llvm flex bison bc perl openssl openssl-devel
    elfutils-libelf-devel dwarves rsync python3 gcc-aarch64-linux-gnu
    binutils-aarch64-linux-gnu rpm-build rpm-sign gnupg2 xz zstd cpio
    e2fsprogs android-tools mock qemu-user-static-aarch64 fedora-gpg-keys
    dnf5 util-linux
)

# Build steps that don't need root drop privileges back to the invoking user.
as_user() {
    if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
        sudo -u "$SUDO_USER" --preserve-env=OUT_DIR,JOBS,FEDORA_RELEASE,UI "$@"
    else
        "$@"
    fi
}

step="${1:-}"
[ $# -gt 0 ] && shift
case "$step" in
    deps)
        require_fedora_host
        sudo dnf install -y "${DEPS[@]}"
        sudo systemctl restart systemd-binfmt 2>/dev/null || true
        groups | grep -qw mock || warn "add yourself to the 'mock' group for ./build.sh extras: sudo usermod -aG mock $USER (then log in again)"
        ;;
    kernel)   require_fedora_host; as_user "$KIT_DIR/kernel/build-kernel.sh" "$@" ;;
    firmware) require_fedora_host; as_user "$KIT_DIR/firmware/build-firmware.sh" "$@" ;;
    support)  require_fedora_host; as_user "$KIT_DIR/support/build-support.sh" "$@" ;;
    extras)   require_fedora_host; as_user "$KIT_DIR/extras/build-extras.sh" "$@" ;;
    rootfs)   require_fedora_host; "$KIT_DIR/image/build-rootfs.sh" "$@" ;;
    all)
        require_fedora_host
        require_root
        export OUT_DIR
        as_user mkdir -p "$OUT_DIR"
        as_user "$KIT_DIR/kernel/build-kernel.sh"
        as_user "$KIT_DIR/firmware/build-firmware.sh"
        as_user "$KIT_DIR/support/build-support.sh"
        as_user "$KIT_DIR/extras/build-extras.sh"
        "$KIT_DIR/image/build-rootfs.sh" "$@"
        ;;
    *)
        sed -n '2,13p' "$0"
        exit 1
        ;;
esac
