#!/usr/bin/env bash
# Build the Nothing Phone (1) system images from Fedora's aarch64 packages
# and the kit's RPMs:
#   out/rootfs.img        ext4 root filesystem (sparse, for: fastboot flash userdata)
#   out/boot.img          Android boot image (for: fastboot boot / fastboot flash boot)
#
# Usage: sudo image/build-rootfs.sh --user NAME [--hostname NAME]
# The password for NAME is asked for interactively. On a phone, digits make
# the lock screen easiest to unlock.
set -euo pipefail
. "$(dirname "$0")/../lib/common.sh"

require_root
require_cmds dnf rpm mkfs.ext4 img2simg useradd chpasswd systemctl du
require_qemu_aarch64

USER_NAME=""
HOST_NAME="nothing-phone"
while [ $# -gt 0 ]; do
    case "$1" in
        --user) USER_NAME="$2"; shift 2 ;;
        --hostname) HOST_NAME="$2"; shift 2 ;;
        *) die "unknown argument: $1" ;;
    esac
done
[ -n "$USER_NAME" ] || die "pass --user NAME (the phone's user account)"
[[ "$USER_NAME" =~ ^[a-z_][a-z0-9_-]*$ ]] || die "invalid user name: $USER_NAME"

shopt -s nullglob
KERNEL_RPMS=("$RPM_DIR"/kernel-spacewar-*.aarch64.rpm)
RPMS=("${KERNEL_RPMS[@]}"
      "$RPM_DIR"/nothing-spacewar-firmware-*.noarch.rpm
      "$RPM_DIR"/nothing-spacewar-support-*.noarch.rpm
      "$RPM_DIR"/hexagonrpc-[0-9]*.aarch64.rpm
      "$RPM_DIR"/qbootctl-[0-9]*.aarch64.rpm)
shopt -u nullglob
[ ${#KERNEL_RPMS[@]} -ge 1 ] && [ ${#RPMS[@]} -ge 5 ] \
    || die "build the packages first (./build.sh kernel firmware support extras)"
[ -f "$SIGN_PUBKEY" ] || die "signing key $SIGN_PUBKEY missing"

while :; do
    read -rsp "Password for $USER_NAME on the phone: " PW1; echo
    read -rsp "Repeat it: " PW2; echo
    [ -n "$PW1" ] && [ "$PW1" = "$PW2" ] && break
    warn "passwords were empty or did not match, try again"
done

BASE_PKGS=(
    @core glibc-langpack-en selinux-policy-targeted dracut
    NetworkManager NetworkManager-wifi NetworkManager-wwan ModemManager
    openssh-server sudo zram-generator-defaults
    linux-firmware atheros-firmware qcom-firmware rmtfs tqftpserv
    pipewire wireplumber pipewire-pulseaudio pipewire-alsa alsa-ucm alsa-utils
    bluez iio-sensor-proxy python3 e2fsprogs
)
case "$UI" in
    phosh)
        UI_PKGS=(phosh phoc phosh-mobile-settings squeekboard gnome-calls chatty
                 gnome-console gnome-settings-daemon gnome-control-center
                 nautilus firefox feedbackd)
        ;;
    plasma-mobile)
        UI_PKGS=(plasma-mobile plasma-dialer spacebar sddm maliit-keyboard
                 konsole dolphin firefox)
        ;;
    *) die "UI must be phosh or plasma-mobile (got '$UI')" ;;
esac

ROOT="$WORK_DIR/rootfs"
# shellcheck disable=SC2054  # excludepkgs takes a comma-separated list
DNF=(dnf -y -q --installroot="$ROOT" --releasever="$FEDORA_RELEASE" --forcearch=aarch64
     --use-host-config --setopt=install_weak_deps=False
     --setopt=excludepkgs=kernel,kernel-core,kernel-modules,kernel-modules-core,kernel-modules-extra)

msg "Creating root filesystem in $ROOT (Fedora $FEDORA_RELEASE, $UI)"
rm -rf "$ROOT"
mkdir -p "$ROOT"
"${DNF[@]}" install "${BASE_PKGS[@]}"
msg2 "installing UI packages (missing ones are skipped with a warning)"
"${DNF[@]}" install --skip-unavailable "${UI_PKGS[@]}"

msg "Installing the kit's packages"
rpm --root "$ROOT" --import "$SIGN_PUBKEY"
mkdir -p "$ROOT/etc/pki/rpm-gpg"
install -m644 "$SIGN_PUBKEY" "$ROOT/etc/pki/rpm-gpg/"
# Fedora's stock kernel has no Nothing Phone (1) support; keep dnf from
# installing it later.
mkdir -p "$ROOT/etc/dnf/libdnf5.conf.d"
cat > "$ROOT/etc/dnf/libdnf5.conf.d/50-nothing-spacewar.conf" <<'EOF'
[main]
excludepkgs=kernel,kernel-core,kernel-modules,kernel-modules-core,kernel-modules-extra
EOF
# kernel-install runs dracut and the boot image plugin in the chroot.
"${DNF[@]}" install "${RPMS[@]}"

msg "Configuring the system"
echo "$HOST_NAME" > "$ROOT/etc/hostname"
cat > "$ROOT/etc/fstab" <<'EOF'
# Root filesystem in the userdata partition; grown to fill it on first boot.
PARTLABEL=userdata  /  ext4  defaults,x-systemd.growfs  0 1
EOF
: > "$ROOT/etc/machine-id"
touch "$ROOT/.autorelabel"

useradd --root "$ROOT" -m -u 1000 -U -G wheel -c "$USER_NAME" "$USER_NAME"
for g in audio video input dialout feedbackd; do
    grep -q "^$g:" "$ROOT/etc/group" && usermod --root "$ROOT" -aG "$g" "$USER_NAME"
done
printf '%s:%s\n' "$USER_NAME" "$PW1" | chpasswd --root "$ROOT"
unset PW1 PW2

systemctl --root "$ROOT" preset-all >/dev/null
systemctl --root "$ROOT" set-default graphical.target >/dev/null
case "$UI" in
    phosh)
        if [ -f "$ROOT/usr/lib/systemd/system/phosh.service" ]; then
            # Fedora's phosh.service starts the shell for the user with UID 1000.
            systemctl --root "$ROOT" enable phosh.service >/dev/null
        else
            warn "phosh.service not found; enable a display manager on the phone"
        fi
        ;;
    plasma-mobile)
        mkdir -p "$ROOT/etc/sddm.conf.d"
        cat > "$ROOT/etc/sddm.conf.d/50-nothing-spacewar.conf" <<EOF
[Autologin]
User=$USER_NAME
Session=plasma-mobile
EOF
        systemctl --root "$ROOT" enable sddm.service >/dev/null
        ;;
esac

msg "Collecting the boot image"
KREL="$(rpm --root "$ROOT" -q --qf '%{VERSION}-%{RELEASE}.spacewar.aarch64\n' kernel-spacewar | sort -V | tail -n1)"
BOOT_IMG="$ROOT/boot/nothing-spacewar/boot-$KREL.img"
[ -s "$BOOT_IMG" ] || die "no boot image for $KREL (did kernel-install run? see the dnf output above)"
cp "$BOOT_IMG" "$OUT_DIR/boot.img"
chmod 0644 "$OUT_DIR/boot.img"

msg "Creating the ext4 image"
used_mb="$(du -sxm "$ROOT" | cut -f1)"
size_mb=$(( used_mb * 11 / 10 + ROOTFS_EXTRA_MB ))
RAW="$OUT_DIR/rootfs.raw"
rm -f "$RAW" "$OUT_DIR/rootfs.img"
truncate -s "${size_mb}M" "$RAW"
mkfs.ext4 -q -L fedora_root -d "$ROOT" "$RAW"
img2simg "$RAW" "$OUT_DIR/rootfs.img"
rm -f "$RAW"
[ -n "${SUDO_USER:-}" ] && chown "$SUDO_USER": "$OUT_DIR/boot.img" "$OUT_DIR/rootfs.img"

msg "Done"
msg2 "$OUT_DIR/boot.img   (kernel $KREL)"
msg2 "$OUT_DIR/rootfs.img (${size_mb} MiB before sparse packing)"
msg2 "See README.md, 'Flashing', for the next steps."
