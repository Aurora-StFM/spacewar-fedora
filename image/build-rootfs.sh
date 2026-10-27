#!/usr/bin/env bash
# Build the Nothing Phone (1) system images from Fedora's aarch64 packages
# and the kit's RPMs:
#   out/rootfs.img        ext4 root filesystem (sparse, for: fastboot flash userdata)
#   out/boot.img          Android boot image (for: fastboot boot / fastboot flash boot)
#
# Usage: sudo image/build-rootfs.sh --user NAME [--hostname NAME]
#        sudo image/build-rootfs.sh --update
# The password for NAME is asked for interactively. On a phone, digits make
# the lock screen easiest to unlock.
#
# --update reuses the image folder from the last build (out/work/rootfs):
# it installs the kit's packages again (newer versions replace older ones)
# and repacks both images, without downloading Fedora again or touching the
# user account. Use it after rebuilding a kit package.
set -euo pipefail
. "$(dirname "$0")/../lib/common.sh"

require_root
require_cmds dnf rpm mkfs.ext4 img2simg useradd usermod openssl systemctl du findmnt mknod
require_qemu_aarch64

USER_NAME=""
HOST_NAME="nothing-phone"
UPDATE=no
while [ $# -gt 0 ]; do
    case "$1" in
        --user) USER_NAME="$2"; shift 2 ;;
        --hostname) HOST_NAME="$2"; shift 2 ;;
        --update) UPDATE=yes; shift ;;
        *) die "unknown argument: $1" ;;
    esac
done
if [ "$UPDATE" = no ]; then
    [ -n "$USER_NAME" ] || die "pass --user NAME (the phone's user account), or --update"
    [[ "$USER_NAME" =~ ^[a-z_][a-z0-9_-]*$ ]] || die "invalid user name: $USER_NAME"
fi

shopt -s nullglob
KERNEL_RPMS=("$RPM_DIR"/kernel-spacewar-*.aarch64.rpm)
RPMS=("${KERNEL_RPMS[@]}"
      "$RPM_DIR"/nothing-spacewar-firmware-*.noarch.rpm
      "$RPM_DIR"/nothing-spacewar-support-*.noarch.rpm
      "$RPM_DIR"/hexagonrpc-[0-9]*.aarch64.rpm
      "$RPM_DIR"/qbootctl-[0-9]*.aarch64.rpm
      "$RPM_DIR"/dummystreamhack-[0-9]*.aarch64.rpm)
shopt -u nullglob
[ ${#KERNEL_RPMS[@]} -ge 1 ] && [ ${#RPMS[@]} -ge 6 ] \
    || die "build the packages first (./build.sh kernel firmware support extras)"
[ -f "$SIGN_PUBKEY" ] || die "signing key $SIGN_PUBKEY missing"

while [ "$UPDATE" = no ]; do
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
        # Fedora's Phosh is a login session (phosh-session), so something
        # has to start it: greetd logs the user straight in, Phosh's own
        # lock screen asks for the PIN.
        UI_REQUIRED=(phosh phoc greetd greetd-selinux)
        UI_PKGS=(phosh-mobile-settings squeekboard gnome-calls chatty
                 gnome-console gnome-settings-daemon gnome-control-center
                 nautilus firefox feedbackd)
        ;;
    plasma-mobile)
        UI_REQUIRED=(plasma-mobile sddm)
        UI_PKGS=(plasma-dialer spacebar maliit-keyboard konsole dolphin firefox)
        ;;
    *) die "UI must be phosh or plasma-mobile (got '$UI')" ;;
esac

ROOT="$WORK_DIR/rootfs"
# shellcheck disable=SC2054  # excludepkgs takes a comma-separated list
DNF=(dnf -y -q --installroot="$ROOT" --releasever="$FEDORA_RELEASE" --forcearch=aarch64
     --use-host-config --setopt=install_weak_deps=False
     --setopt=excludepkgs=kernel,kernel-core,kernel-modules,kernel-modules-core,kernel-modules-extra)

# Package scripts (dracut above all) need /proc, /sys and a minimal /dev in
# the image while they run. /dev is a private tmpfs with a few device nodes
# rather than the host's /dev, so nothing in the image can touch real devices.
mount_chroot() {
    mkdir -p "$ROOT/proc" "$ROOT/sys" "$ROOT/dev"
    mount -t proc proc "$ROOT/proc"
    mount -t sysfs -o ro sysfs "$ROOT/sys"
    mount -t tmpfs -o mode=0755,nosuid dev "$ROOT/dev"
    mknod -m 0666 "$ROOT/dev/null" c 1 3
    mknod -m 0666 "$ROOT/dev/zero" c 1 5
    mknod -m 0666 "$ROOT/dev/full" c 1 7
    mknod -m 0666 "$ROOT/dev/random" c 1 8
    mknod -m 0666 "$ROOT/dev/urandom" c 1 9
    mknod -m 0666 "$ROOT/dev/tty" c 5 0
    ln -s /proc/self/fd "$ROOT/dev/fd"
    ln -s /proc/self/fd/0 "$ROOT/dev/stdin"
    ln -s /proc/self/fd/1 "$ROOT/dev/stdout"
    ln -s /proc/self/fd/2 "$ROOT/dev/stderr"
    mkdir -p "$ROOT/dev/pts" "$ROOT/dev/shm"
}
umount_chroot() {
    local m
    for m in dev sys proc; do
        mountpoint -q "$ROOT/$m" && umount -l "$ROOT/$m"
    done
    # Refuse to go on (and to delete anything) while something is still
    # mounted inside the image.
    if [ -n "$(findmnt -R -n -o TARGET --list "$ROOT" 2>/dev/null | grep -v "^$ROOT\$")" ]; then
        die "something is still mounted under $ROOT; unmount it by hand"
    fi
}
trap 'umount_chroot 2>/dev/null || true' EXIT

if [ "$UPDATE" = yes ]; then
msg "Updating the kit's packages in $ROOT"
[ -f "$ROOT/etc/os-release" ] || die "no image in $ROOT to update; run a full build first (--user NAME)"
umount_chroot
mount_chroot
rpm --root "$ROOT" --import "$SIGN_PUBKEY"
# Newer package versions replace the installed ones; unchanged ones are kept.
"${DNF[@]}" install "${RPMS[@]}"
# Package scripts only apply presets on first install, so enable the kit's
# services (including any new ones) here.
mapfile -t KIT_UNITS < <(awk '$1 == "enable" { print $2 }' \
    "$ROOT/usr/lib/systemd/system-preset/50-nothing-spacewar.preset")
systemctl --root "$ROOT" preset "${KIT_UNITS[@]}" >/dev/null
touch "$ROOT/.autorelabel"
else
msg "Creating root filesystem in $ROOT (Fedora $FEDORA_RELEASE, $UI)"
[ -d "$ROOT" ] && umount_chroot
rm -rf --one-file-system "$ROOT"
mkdir -p "$ROOT"
mount_chroot
"${DNF[@]}" install "${BASE_PKGS[@]}"
msg2 "installing UI packages (missing ones are skipped with a warning)"
"${DNF[@]}" install "${UI_REQUIRED[@]}"
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
# Set the password by writing the hash into the image's /etc/shadow.
# chpasswd --root can't be used: SELinux confines it and stops it from
# entering a folder under /home.
PW_HASH="$(printf '%s' "$PW1" | openssl passwd -6 -stdin)"
unset PW1 PW2
[[ "$PW_HASH" == '$6$'* ]] || die "could not hash the password"
awk -F: -v OFS=: -v u="$USER_NAME" -v h="$PW_HASH" \
    '$1 == u { $2 = h; found = 1 } { print } END { exit !found }' \
    "$ROOT/etc/shadow" > "$ROOT/etc/shadow.new" || die "$USER_NAME not found in the image's /etc/shadow"
chmod 0000 "$ROOT/etc/shadow.new"
mv -f "$ROOT/etc/shadow.new" "$ROOT/etc/shadow"
unset PW_HASH

systemctl --root "$ROOT" preset-all >/dev/null
systemctl --root "$ROOT" set-default graphical.target >/dev/null
case "$UI" in
    phosh)
        # greetd runs its greeter as an unprivileged user; Fedora's package
        # creates it, but the name differs between versions.
        GREETER=""
        for u in greetd greeter; do
            if grep -q "^$u:" "$ROOT/etc/passwd"; then GREETER="$u"; break; fi
        done
        if [ -z "$GREETER" ]; then
            useradd --root "$ROOT" -r -M -d /var/lib/greetd -s /usr/sbin/nologin -G video greeter
            GREETER=greeter
        fi
        mkdir -p "$ROOT/etc/greetd"
        cat > "$ROOT/etc/greetd/config.toml" <<GREETD
# Nothing Phone (1): log $USER_NAME straight into Phosh at boot; Phosh's
# lock screen asks for the PIN. After logging out, a text login on the
# same screen can start Phosh again.
[terminal]
# tty1 keeps its normal text login as a fallback.
vt = 7

[initial_session]
command = "phosh-session"
user = "$USER_NAME"

[default_session]
command = "agreety --cmd phosh-session"
user = "$GREETER"
GREETD
        systemctl --root "$ROOT" enable greetd.service >/dev/null
        ;;
    plasma-mobile)
        # SDDM's autologin wants the session file's exact name; take it from
        # the image instead of guessing.
        SESSION="$(find "$ROOT/usr/share/wayland-sessions" -maxdepth 1 -name 'plasma-mobile*.desktop' -printf '%f\n' | sort | head -n1)"
        [ -n "$SESSION" ] || die "no Plasma Mobile session file in /usr/share/wayland-sessions"
        mkdir -p "$ROOT/etc/sddm.conf.d"
        cat > "$ROOT/etc/sddm.conf.d/50-nothing-spacewar.conf" <<EOF
[Autologin]
User=$USER_NAME
Session=$SESSION
EOF
        systemctl --root "$ROOT" enable sddm.service >/dev/null
        ;;
esac

fi  # full build

msg "Collecting the boot image"
# The kernel's own version string (7.3.0-rc4-1.spacewar.aarch64), not the RPM's
# (7.3.0~rc4-1): take it from the installed module directories.
KREL="$(find "$ROOT/usr/lib/modules" -mindepth 1 -maxdepth 1 -name '*.spacewar.aarch64' -printf '%f\n' | sort -V | tail -n1)"
[ -n "$KREL" ] || die "kernel-spacewar is not installed in $ROOT"
BOOT_IMG="$ROOT/boot/nothing-spacewar/boot-$KREL.img"
[ -s "$BOOT_IMG" ] || die "no boot image for $KREL (did kernel-install run? see the dnf output above)"
cp "$BOOT_IMG" "$OUT_DIR/boot.img"
chmod 0644 "$OUT_DIR/boot.img"

# Unmount /proc, /sys and /dev before the image is copied, or their
# contents would end up in it.
umount_chroot

msg "Creating the ext4 image"
used_mb="$(du -sxm "$ROOT" | cut -f1)"
size_mb=$(( used_mb * 11 / 10 + ROOTFS_EXTRA_MB ))
RAW="$OUT_DIR/rootfs.raw"
rm -f "$RAW" "$OUT_DIR/rootfs.img"
truncate -s "${size_mb}M" "$RAW"
mkfs.ext4 -q -L fedora_root -d "$ROOT" "$RAW"
img2simg "$RAW" "$OUT_DIR/rootfs.img"
rm -f "$RAW"
if [ -n "${SUDO_USER:-}" ]; then
    chown "$SUDO_USER": "$OUT_DIR/boot.img" "$OUT_DIR/rootfs.img"
fi

msg "Done"
msg2 "$OUT_DIR/boot.img   (kernel $KREL)"
msg2 "$OUT_DIR/rootfs.img (${size_mb} MiB before sparse packing)"
msg2 "See README.md, 'Flashing', for the next steps."
