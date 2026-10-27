#!/usr/bin/env bash
# Package the Fedora integration files as nothing-spacewar-support (noarch),
# together with the SC7280 ALSA UCM profiles and the boot image settings from
# config.env.
set -euo pipefail
. "$(dirname "$0")/../lib/common.sh"

require_cmds git rpmbuild rpmsign gpg python3

TOP="$WORK_DIR/rpmbuild-support"
rm -rf "$TOP"
mkdir -p "$TOP/SOURCES" "$RPM_DIR"
cp -r "$KIT_DIR"/support/files/. "$TOP/SOURCES/"

msg "Fetching ALSA UCM profiles (${UCM_COMMIT:0:12})"
UCM="$WORK_DIR/alsa-ucm-conf"
git_fetch_commit "$UCM_REPO" "$UCM" "$UCM_COMMIT"
[ -d "$UCM/ucm2" ] || die "no ucm2 directory in $UCM_REPO"
shopt -s nullglob
for p in "$KIT_DIR"/support/ucm-patches/*.patch; do
    msg2 "applying $(basename "$p")"
    git -C "$UCM" apply "$p" || die "UCM patch failed: $p"
done
shopt -u nullglob
tar -C "$UCM" -cf "$TOP/SOURCES/ucm2.tar" ucm2

# Boot image layout and command line, baked in from config.env. Users can
# override any of it in /etc/nothing-spacewar/boot.conf.
cat > "$TOP/SOURCES/boot.conf" <<EOF
# Nothing Phone (1) boot image settings (from the kit's config.env).
# Override in /etc/nothing-spacewar/boot.conf.
FLASH_ON_UPDATE=yes
KERNEL_CMDLINE="$KERNEL_CMDLINE"
BOOTIMG_HEADER_VERSION=$BOOTIMG_HEADER_VERSION
BOOTIMG_PAGESIZE=$BOOTIMG_PAGESIZE
BOOTIMG_BASE=$BOOTIMG_BASE
BOOTIMG_KERNEL_OFFSET=$BOOTIMG_KERNEL_OFFSET
BOOTIMG_RAMDISK_OFFSET=$BOOTIMG_RAMDISK_OFFSET
BOOTIMG_SECOND_OFFSET=$BOOTIMG_SECOND_OFFSET
BOOTIMG_TAGS_OFFSET=$BOOTIMG_TAGS_OFFSET
BOOTIMG_DTB_OFFSET=$BOOTIMG_DTB_OFFSET
EOF

msg "Packaging nothing-spacewar-support RPM"
rpmbuild -bb --define "_topdir $TOP" --define "ucmcommit $UCM_COMMIT" \
    "$KIT_DIR/support/nothing-spacewar-support.spec"
rm -f "$RPM_DIR"/nothing-spacewar-support-*.rpm
find "$TOP/RPMS" -name '*.rpm' -exec cp -t "$RPM_DIR" {} +
sign_rpms "$RPM_DIR"/nothing-spacewar-support-*.rpm
msg "Done: $(ls "$RPM_DIR"/nothing-spacewar-support-*.rpm)"
