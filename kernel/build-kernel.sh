#!/usr/bin/env bash
# Cross-compile the sc7280-mainline kernel for the Nothing Phone (1) with
# Nura's configuration plus Fedora's requirements, and package it as an
# aarch64 RPM (kernel-spacewar).
#
#   build-kernel.sh                     download Nura's config (checksum-verified)
#   build-kernel.sh --config-file FILE  use a config you downloaded yourself
#                                       (still checked against the pinned SHA-512)
set -euo pipefail
. "$(dirname "$0")/../lib/common.sh"

require_cmds git curl make clang ld.lld llvm-objcopy flex bison bc perl \
    rpmbuild rpmsign gpg sha512sum

CONFIG_FILE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --config-file) CONFIG_FILE="$(realpath "$2")"; shift 2 ;;
        *) die "unknown argument: $1" ;;
    esac
done

SRC="$WORK_DIR/kernel-src"
BUILD="$WORK_DIR/kernel-build"
STAGE="$WORK_DIR/kernel-stage"
CFG="$WORK_DIR/kernel-config"
JOBS="${JOBS:-$(nproc)}"
# Nura builds this kernel with LLVM; clang cross-compiles without a separate
# aarch64 toolchain.
KMAKE=(make -C "$SRC" O="$BUILD" ARCH=arm64 LLVM=1
       LOCALVERSION="-${KERNEL_PKG_RELEASE}.spacewar.aarch64")

mkdir -p "$WORK_DIR" "$RPM_DIR" "$CFG"

msg "Fetching kernel source (${KERNEL_COMMIT:0:12}, v${KERNEL_VERSION}-sc7280)"
git_fetch_commit "$KERNEL_REPO" "$SRC" "$KERNEL_COMMIT"

shopt -s nullglob
PATCHES=("$KIT_DIR"/kernel/patches/*.patch)
shopt -u nullglob
for p in "${PATCHES[@]}"; do
    msg2 "applying $(basename "$p")"
    git -C "$SRC" apply --whitespace=nowarn "$p" || die "patch failed: $p"
done

msg "Preparing configuration"
if [ -n "$CONFIG_FILE" ]; then
    cp "$CONFIG_FILE" "$CFG/nura.config"
    echo "$NURA_CONFIG_SHA512  $CFG/nura.config" | sha512sum -c --quiet - \
        || die "$CONFIG_FILE does not match the pinned Nura config (NURA_CONFIG_SHA512)"
else
    fetch_verified "$NURA_CONFIG_URL" "$CFG/nura.config" sha512 "$NURA_CONFIG_SHA512" \
        || die "could not fetch Nura's config; download it in a browser and pass --config-file"
fi
mkdir -p "$BUILD"
(cd "$BUILD" && ARCH=arm64 "$SRC/scripts/kconfig/merge_config.sh" -m -O "$BUILD" \
    "$CFG/nura.config" "$KIT_DIR/kernel/fedora.config" "$KIT_DIR/kernel/overrides.config" >/dev/null)
"${KMAKE[@]}" olddefconfig >/dev/null

# Fail early if a setting the kit relies on did not survive olddefconfig.
# Built in (y) where the system needs it before modules load, either for the rest.
for opt in SECURITY_SELINUX=y EXT4_FS=y FW_LOADER_COMPRESS_XZ=y \
           FW_LOADER_COMPRESS_ZSTD=y USB_CONFIGFS=y USB_CONFIGFS_NCM=y \
           SCSI_UFS_QCOM DRM_MSM QCOM_PD_MAPPER ATH11K_AHB QCOM_FASTRPC \
           INPUT_QCOM_HV_HAPTICS; do
    case "$opt" in
        *=*) pat="^CONFIG_${opt}\$" ;;
        *)   pat="^CONFIG_${opt}=[ym]\$" ;;
    esac
    grep -q "$pat" "$BUILD/.config" || die "CONFIG_${opt} missing from final config"
done

KREL="$("${KMAKE[@]}" -s kernelrelease)"
[ "$KREL" = "$KERNEL_RELEASE_STRING" ] || die "unexpected kernel release '$KREL' (wanted $KERNEL_RELEASE_STRING)"

msg "Building kernel $KREL with $JOBS jobs (this takes a while)"
"${KMAKE[@]}" -j"$JOBS" Image.gz modules dtbs

msg "Staging files"
rm -rf "$STAGE"
MODDIR="$STAGE/usr/lib/modules/$KREL"
"${KMAKE[@]}" INSTALL_MOD_PATH="$STAGE/usr" INSTALL_MOD_STRIP=1 DEPMOD=true modules_install >/dev/null
"${KMAKE[@]}" INSTALL_DTBS_PATH="$MODDIR/dtb" dtbs_install >/dev/null
rm -f "$MODDIR/build" "$MODDIR/source"
# The phone's bootloader takes a gzip-compressed Image; the boot.img builder
# (nothing-spacewar-support) reads it from here.
install -m644 "$BUILD/arch/arm64/boot/Image.gz" "$MODDIR/vmlinuz"
install -m644 "$BUILD/System.map" "$MODDIR/System.map"
install -m644 "$BUILD/.config" "$MODDIR/config"
[ -f "$MODDIR/dtb/$SPACEWAR_DTB" ] || die "$SPACEWAR_DTB was not built"

msg "Packaging kernel-spacewar RPM"
TOP="$WORK_DIR/rpmbuild"
rm -rf "$TOP"
mkdir -p "$TOP/SOURCES"
tar -C "$STAGE" -cf "$TOP/SOURCES/kernel-spacewar-stage.tar" .
rpmbuild -bb --target aarch64-linux \
    --define "_topdir $TOP" \
    --define "kver $KREL" \
    --define "kversion $KERNEL_VERSION" \
    --define "krelease $KERNEL_PKG_RELEASE" \
    --define "kcommit $KERNEL_COMMIT" \
    "$KIT_DIR/kernel/kernel-spacewar.spec"
find "$TOP/RPMS" -name '*.rpm' -exec cp -t "$RPM_DIR" {} +
sign_rpms "$RPM_DIR"/kernel-spacewar-"$KERNEL_VERSION"-"$KERNEL_PKG_RELEASE".*.rpm
msg "Done: $(ls "$RPM_DIR"/kernel-spacewar-"$KERNEL_VERSION"-"$KERNEL_PKG_RELEASE".*.rpm)"
