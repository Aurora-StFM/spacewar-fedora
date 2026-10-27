#!/usr/bin/env bash
# Cross-compile the Nothing Phone (1) kernel (the Nura port developers'
# spacewar branch) with its in-tree configuration plus Fedora's requirements,
# and package it as an aarch64 RPM (kernel-spacewar).
set -euo pipefail
. "$(dirname "$0")/../lib/common.sh"

require_cmds git make clang ld.lld llvm-objcopy flex bison bc perl \
    rpmbuild rpmsign gpg

[ $# -eq 0 ] || die "unknown argument: $1"

SRC="$WORK_DIR/kernel-src"
BUILD="$WORK_DIR/kernel-build"
STAGE="$WORK_DIR/kernel-stage"
JOBS="${JOBS:-$(nproc)}"
# The port developers build with LLVM; clang cross-compiles without a
# separate aarch64 toolchain.
KMAKE=(make -C "$SRC" O="$BUILD" ARCH=arm64 LLVM=1
       LOCALVERSION="-${KERNEL_PKG_RELEASE}.spacewar.aarch64")

mkdir -p "$WORK_DIR" "$RPM_DIR"

msg "Fetching kernel source (${KERNEL_COMMIT:0:12}, ${KERNEL_VERSION})"
git_fetch_commit "$KERNEL_REPO" "$SRC" "$KERNEL_COMMIT" \
    || die "could not fetch $KERNEL_COMMIT from $KERNEL_REPO (see config.env about pinned branches)"

shopt -s nullglob
PATCHES=("$KIT_DIR"/kernel/patches/*.patch)
shopt -u nullglob
for p in "${PATCHES[@]}"; do
    msg2 "applying $(basename "$p")"
    git -C "$SRC" apply --whitespace=nowarn "$p" || die "patch failed: $p"
done

msg "Preparing configuration ($KERNEL_CONFIG_TARGETS + Fedora)"
rm -rf "$BUILD"
mkdir -p "$BUILD"
# shellcheck disable=SC2086  # KERNEL_CONFIG_TARGETS is a list of make targets
"${KMAKE[@]}" $KERNEL_CONFIG_TARGETS >/dev/null
(cd "$BUILD" && ARCH=arm64 "$SRC/scripts/kconfig/merge_config.sh" -m -O "$BUILD" \
    "$BUILD/.config" "$KIT_DIR/kernel/fedora.config" "$KIT_DIR/kernel/overrides.config" >/dev/null)
"${KMAKE[@]}" olddefconfig >/dev/null

# Fail early if a setting the kit relies on did not survive olddefconfig.
# "=y" where it must be built in; otherwise built in or a module is fine.
for opt in SECURITY_SELINUX=y EXT4_FS=y FW_LOADER_COMPRESS_XZ=y \
           FW_LOADER_COMPRESS_ZSTD=y USB_CONFIGFS=y USB_CONFIGFS_NCM=y \
           SCSI_UFS_QCOM DRM_MSM DRM_PANEL_VISIONOX_RM692E5 \
           TOUCHSCREEN_FOCALTECH_SPI QCOM_PD_MAPPER ATH11K_AHB QCOM_FASTRPC \
           SOUNDWIRE_QCOM SND_SOC_SM8250 SND_SOC_WCD938X_SDW \
           SND_SOC_LPASS_RX_MACRO SND_SOC_LPASS_TX_MACRO SND_SOC_LPASS_VA_MACRO \
           SND_SOC_TFA98XX SND_SOC_QDSP6_Q6VOICE TYPEC_MUX_FSA4480 \
           INPUT_QCOM_HV_HAPTICS LEDS_AW21018; do
    case "$opt" in
        *=*) pat="^CONFIG_${opt}\$" ;;
        *)   pat="^CONFIG_${opt}=[ym]\$" ;;
    esac
    grep -q "$pat" "$BUILD/.config" || die "CONFIG_${opt} missing from final config"
done

# kernelrelease reads include/config/auto.conf, which the config targets above
# leave stale (it would still say LOCALVERSION_AUTO=y and add a git hash).
"${KMAKE[@]}" syncconfig >/dev/null
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
    --define "kversion $KERNEL_RPM_VERSION" \
    --define "krelease $KERNEL_PKG_RELEASE" \
    --define "kcommit $KERNEL_COMMIT" \
    --define "kbranch $KERNEL_BRANCH" \
    "$KIT_DIR/kernel/kernel-spacewar.spec"
find "$TOP/RPMS" -name '*.rpm' -exec cp -t "$RPM_DIR" {} +
RPM_GLOB="$RPM_DIR/kernel-spacewar-${KERNEL_RPM_VERSION}-${KERNEL_PKG_RELEASE}.aarch64.rpm"
sign_rpms "$RPM_GLOB"
msg "Done: $RPM_GLOB"
