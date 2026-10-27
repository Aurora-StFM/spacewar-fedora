# Fedora for the Nothing Phone (1)

An unofficial kit that builds a Fedora mobile system (Phosh or Plasma Mobile)
for the Nothing Phone (1), codename Spacewar, on a mainline Linux kernel.

> **Status: untested.** Nothing here has been booted on a phone yet. It is
> built on the work of the [Nura](https://nura.eco) (formerly postmarketOS)
> Spacewar port, which does boot: kernel, firmware, audio profiles and boot
> image layout all come from the people behind it. Written with an AI assistant (Claude).
> Not affiliated with Nura, Nothing, or the Fedora Project. Read the scripts
> before running them as root.

It reuses:

- **Kernel:** the port developers' development branch,
  [mainlining/linux `fekz115/spacewar`](https://github.com/mainlining/linux/tree/fekz115/spacewar)
  (Linux 7.3-rc4 plus about 70 Nothing Phone (1) patches), with its in-tree
  `sc7280.config`. It is newer than what Nura ships and includes the
  microphone, call-audio, stereo-speaker, haptics and Glyph LED work.
- **Firmware:** [mainlining/firmware-nothing-spacewar](https://github.com/mainlining/firmware-nothing-spacewar).
- **Audio profiles:** [sc7280-mainline/alsa-ucm-conf](https://github.com/sc7280-mainline/alsa-ucm-conf),
  plus a Voice Call profile for this phone (`support/ucm-patches/`).
- **Tools:** [hexagonrpc](https://github.com/linux-msm/hexagonrpc) (sensors),
  [qbootctl](https://github.com/linux-msm/qbootctl) (A/B slots) and
  [dummystreamhack](https://codeberg.org/valpackett/dummystreamhack) (call
  audio), which Fedora doesn't package.

All versions are pinned in `config.env`.

## Expected status

What works in Nura should work here (see `docs/hardware-findings.md`):
display, touch, GPU, battery, Bluetooth, GPS, SMS, mobile data, USB. The
kernel branch adds work in progress for microphones, headphones, stereo
speakers, calls, haptics, Glyph LEDs and Wi-Fi calibration; expect rough
edges there. The fingerprint reader doesn't work, NFC and cameras are
partial. Sensors need a libssc-enabled iio-sensor-proxy that Fedora doesn't
ship.

## How it boots

The phone's bootloader has no GRUB or boot menu: it loads one Android boot
image (kernel, initramfs, device tree) from the boot partition of the active
slot. The root filesystem lives in the `userdata` partition.

`nothing-spacewar-support` adds a kernel-install plugin, so a kernel update
works like on any Fedora system: dnf installs `kernel-spacewar`, dracut builds
the initramfs, and the plugin packs a boot image into
`/boot/nothing-spacewar/` and writes it to the active boot slot. To keep the
boot partition untouched, set `FLASH_ON_UPDATE=no` in
`/etc/nothing-spacewar/boot.conf` and flash the image yourself.

## What's in the kit

| Path | Purpose |
|---|---|
| `build.sh` | Entry point: `deps`, `kernel`, `firmware`, `support`, `extras`, `rootfs`, `all` |
| `config.env` | Pinned sources, boot image layout, kernel command line, Fedora release, UI |
| `kernel/` | Cross-compiles the kernel with clang and packages it as `kernel-spacewar`. The configuration is arm64 `defconfig` plus the branch's `sc7280.config`; `fedora.config` adds SELinux, compressed firmware and USB gadget networking. Patches in `kernel/patches/` are applied first. |
| `firmware/` | Packages the firmware as `nothing-spacewar-firmware` |
| `support/` | `nothing-spacewar-support`: boot image plugin and writer, dracut settings, service presets, USB networking, `nothing-spacewar-backup`, audio profiles including calls |
| `extras/` | Builds `hexagonrpc`, `qbootctl` and `dummystreamhack` for aarch64 with mock |
| `image/build-rootfs.sh` | Builds `out/rootfs.img` and `out/boot.img` from Fedora's aarch64 repositories |
| `docs/hardware-findings.md` | What is known about each piece of hardware and the plan |

## Step 1: Build

On a Fedora machine with about 30 GB free:

```bash
./build.sh deps                     # once; then add yourself to the mock group
./build.sh kernel
./build.sh firmware
./build.sh support
./build.sh extras
sudo ./build.sh rootfs --user yourname
```

`rootfs` asks for the password of the phone's user account. Digits make the
lock screen easiest. Choose the shell with `UI=plasma-mobile` (default
`phosh`) and the Fedora release with `FEDORA_RELEASE=`.

The kernel comes from a personal development branch that can be rebased.
If `./build.sh kernel` can't fetch the pinned commit any more, pick a newer
commit from the branch, or keep your own fork (see the note in `config.env`).

## Step 2: Before flashing

- **Unlock the bootloader.** This erases the phone. Nothing's process is like
  a Pixel's: enable OEM unlocking in Developer options, boot to the bootloader
  (Volume Down + Power) and run `fastboot flashing unlock`.
- **Download Nothing's stock fastboot images for your exact Nothing OS
  version.** That is the way back to Android, including the `dtbo` partition
  erased below.
- **Back up `persist` and the modem partitions** as soon as Linux runs (step 4).
  They hold the Wi-Fi/Bluetooth MAC addresses, sensor calibration and the
  modem's per-device data, and no stock package contains them. Flashing
  doesn't touch them, but a mistake later could.

## Step 3: Flash

In the bootloader (Volume Down + Power), following Nura's instructions:

```bash
fastboot -w                              # wipe userdata
fastboot erase dtbo                      # Android's device tree overlay breaks the mainline one
fastboot flash userdata out/rootfs.img
fastboot boot out/boot.img               # try it once without writing the boot partition
```

The first boot relabels the filesystem for SELinux and reboots once. Because
`fastboot boot` doesn't write anything, that reboot would start the Android
kernel still in the boot partition, which can't use the Fedora userdata and
may offer to format it. **Hold Volume Down as the phone reboots** so it lands
in the bootloader instead, then run `fastboot boot out/boot.img` again. Never
accept a "format data" or "factory reset" prompt from Android recovery here;
it wipes the Fedora install.

When it works, make it permanent:

```bash
fastboot flash boot out/boot.img
fastboot reboot
```

## Step 4: First login and backup

Connect the phone by USB. It appears as a network adapter and hands your
computer an address:

```bash
ssh yourname@172.16.42.1
sudo nothing-spacewar-backup
exit
scp -r 'yourname@172.16.42.1:spacewar-backup-*' .
```

Keep that backup somewhere safe.

## Updating

After rebuilding one of the kit's packages, you don't need a full image
build: `sudo ./build.sh rootfs --update` installs the new packages into the
last image and repacks `boot.img` and `rootfs.img`.


Rebuild the packages and copy them over, or serve `out/rpms` as a repository.
On the phone, `sudo dnf install ./kernel-spacewar-*.rpm` writes the new kernel
to the boot slot. Fedora's own kernel is excluded from dnf; it can't boot this
phone.

If a new kernel doesn't boot, boot the previous image from your computer
(`fastboot boot boot-<version>.img`, copied from `/boot/nothing-spacewar/` on
the phone) and remove the broken kernel.

## Getting back to Android

Flash Nothing's stock images for your version (this restores `dtbo` and
`boot`, and formats `userdata`).
