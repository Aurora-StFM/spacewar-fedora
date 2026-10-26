#!/usr/bin/env bash
# Package the Nothing Phone (1) firmware as a noarch RPM
# (nothing-spacewar-firmware) from mainlining/firmware-nothing-spacewar.
#
# Device-only files go to the paths the device tree asks for
# (/usr/lib/firmware/qcom/sm7325/nothing/spacewar/). The Wi-Fi board file
# replaces one Fedora's linux-firmware also ships, so it goes to
# /usr/lib/firmware/updates/, which the kernel searches first. That avoids a
# file conflict with Fedora's package.
set -euo pipefail
. "$(dirname "$0")/../lib/common.sh"

require_cmds git rpmbuild rpmsign gpg

mkdir -p "$WORK_DIR" "$RPM_DIR"
REPO="$WORK_DIR/firmware-nothing-spacewar"
msg "Fetching firmware repository (${FIRMWARE_COMMIT:0:12})"
git_fetch_commit "$FIRMWARE_REPO" "$REPO" "$FIRMWARE_COMMIT"
FW_VERSION="$(TZ=UTC git -C "$REPO" show -s --format=%cd --date=format-local:%Y%m%d HEAD)"

DEV="lib/firmware/qcom/sm7325/nothing/spacewar"
SHARE="usr/share/qcom/sm7325/Nothing/spacewar"
for f in "$DEV/a660_zap.mbn" "$DEV/adsp.mbn" "$DEV/cdsp.mbn" "$DEV/modem.mbn" \
         "$DEV/wpss.mbn" "$DEV/ipa_fws.mbn" "$DEV/vpu20_1v.mbn" \
         "$DEV/focaltech_ts_novatek.bin" \
         lib/firmware/postmarketos/ath11k/WCN6750/hw1.0/board-2.bin \
         "$SHARE/sensors/sns_reg.conf"; do
    [ -e "$REPO/$f" ] || die "firmware file missing: $f"
done

msg "Staging firmware"
STAGE="$WORK_DIR/firmware-stage"
rm -rf "$STAGE"
mkdir -p "$STAGE/usr/lib/firmware/qcom/sm7325/nothing" \
         "$STAGE/usr/lib/firmware/updates/ath11k/WCN6750/hw1.0" \
         "$STAGE/usr/share/qcom/sm7325/Nothing"
cp -a "$REPO/$DEV" "$STAGE/usr/lib/firmware/qcom/sm7325/nothing/"
install -m644 "$REPO/lib/firmware/postmarketos/ath11k/WCN6750/hw1.0/board-2.bin" \
    "$STAGE/usr/lib/firmware/updates/ath11k/WCN6750/hw1.0/board-2.bin"
# DSP libraries, sensor registry and audio calibration, read by hexagonrpcd.
cp -a "$REPO/$SHARE" "$STAGE/usr/share/qcom/sm7325/Nothing/"

msg "Packaging nothing-spacewar-firmware RPM"
TOP="$WORK_DIR/rpmbuild-firmware"
rm -rf "$TOP"
mkdir -p "$TOP/SOURCES"
tar -C "$STAGE" -cf "$TOP/SOURCES/firmware-stage.tar" .
rpmbuild -bb --define "_topdir $TOP" \
    --define "fwversion $FW_VERSION" \
    --define "fwcommit $FIRMWARE_COMMIT" \
    "$KIT_DIR/firmware/nothing-spacewar-firmware.spec"
rm -f "$RPM_DIR"/nothing-spacewar-firmware-*.rpm
find "$TOP/RPMS" -name '*.rpm' -exec cp -t "$RPM_DIR" {} +
sign_rpms "$RPM_DIR"/nothing-spacewar-firmware-*.rpm
msg "Done: $(ls "$RPM_DIR"/nothing-spacewar-firmware-*.rpm)"
