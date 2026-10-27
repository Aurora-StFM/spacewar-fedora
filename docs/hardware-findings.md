# Hardware findings

What is known about each piece of Nothing Phone (1) hardware on the mainline
kernel, where the information came from, and the plan. Status from Nura's
wiki (October 2026) unless noted.

Sources:
- Nura wiki: <https://wiki.nura.eco/wiki/Nothing_Phone_1_(nothing-spacewar)>
- Kernel used by the kit: <https://github.com/mainlining/linux/tree/fekz115/spacewar>
  (7.3-rc4 plus the port developers' patches),
  `arch/arm64/boot/dts/qcom/sm7325-nothing-spacewar.dts`
- Released Nura kernel: <https://github.com/sc7280-mainline/linux> (tag v7.2.9-sc7280)
- Nothing's Android device tree: <https://github.com/NothingOSS/android_kernel_devicetree_nothing_sm7325>
- Nothing's Android kernel: <https://github.com/NothingOSS/android_kernel_msm-5.4_nothing_sm7325>
- Ubuntu Touch port (Android kernel, everything working): <https://github.com/Nonta72/nothing-spacewar>

## Which kernel

Nura's packaged kernel (sc7280-mainline v7.2.9) only describes the speaker
path. The port developers (Danila Tikhonov, Eugene Lepshy "fekz115", Vasiliy
Doylov and others) keep the rest on `mainlining/linux` branches named
`danila/spacewar*` and `fekz115/spacewar*`. The kit builds
`fekz115/spacewar` (newest, 4 October 2026), which adds on top of 7.3-rc4:

- WCD9385 codec, SoundWire and LPASS RX/TX/VA macros (microphones, headphones)
- a Spacewar sound card compatible (`nothing,spacewar-sndcard`)
- the TFA98xx speaker driver with TFA9873 support and per-amplifier channels
- the q6voice stack (q6mvm/q6cvs/q6cvp/VoiceMMode1) for call audio
- a haptics driver, an AW21018 Glyph LED driver, a mainline FocalTech
  touchscreen driver, camera work, the Wi-Fi calibration variant and a USB
  PHY reset quirk

Everything in that list is marked WIP or HACK by its authors.

Checked here: with the kit's configuration (`defconfig` + `sc7280.config` +
`fedora.config`) every driver above is enabled; the Spacewar device tree and
all of `sound/soc/qcom`, `sound/soc/codecs`, `drivers/soundwire`,
`drivers/input`, `drivers/leds` and `drivers/usb/typec/mux` compile. The
only warning was an uninitialised variable in the sm8250 sound card driver
(the LPI MI2S cases, which this phone doesn't use); `kernel/patches/0001`
fixes it.

## Audio: work in progress in the kernel branch, untested here

- Speakers: two NXP TFA9873 amplifiers on I2C2 (0x34 earpiece/top, 0x35
  loudspeaker/bottom), fed by the DSP over Primary MI2S. Nura's driver plays
  only the left channel on both; the branch's tfa98xx driver gives each
  amplifier its own channel ("Speaker Top", "Speaker Bottom").
- Microphones and headphones: WCD9385 over SoundWire, with the LPASS macros.
  Three chassis microphones plus the USB-C analog headset mic (through the
  FSA4480 switch; the phone has no 3.5 mm jack).
- PCM devices on the card ("NP1"): 0 speakers (MultiMedia1), 1 headphones
  (MultiMedia2), 2 capture (MultiMedia3), 6 VoiceMMode1. The device number
  is the dai link's position in the device tree.
- UCM: sc7280-mainline/alsa-ucm-conf (the kit's pin) already has a HiFi
  profile for this card: speakers, headphones, top/bottom/back mic, headset
  mic. It is only linked as `conf.d/sm8250/NP1.conf`, but with the kernel
  branch's `nothing,spacewar-sndcard` compatible the card reports driver
  `sm7325`, so ALSA looks in `conf.d/sm7325/` and would find nothing.
  `support/ucm-patches/0002` adds that link.
- Calls: `support/ucm-patches/0001` adds a Voice Call profile, modelled on
  the Motorola Edge 30 (same SoC): earpiece (bottom amp muted),
  speakerphone, bottom microphone. Every control it sets exists in the
  kernel branch; the profile itself is untested. It starts
  `dummystreamhack@Rhw:NP1,6` / `@Thw:NP1,6` (user units from
  nothing-spacewar-support), which hold the hostless voice streams open
  while the call runs inside the DSP.
- Not covered: wired headset during calls. q6voice-dai has voice routes to
  the MI2S ports but not to RX_CODEC_DMA_RX_0, the WCD9385 headphone path, so
  that needs a kernel change first.

### Testing audio

```bash
aplay -l; arecord -l                         # card NP1 with the PCMs above
alsaucm -c NP1 list _verbs                   # HiFi, Voice Call
speaker-test -c 2 -t wav -D hw:NP1,0         # speakers, after the HiFi verb
```

For calls: start a call with GNOME Calls (Phosh) or Plasma Dialer; PipeWire
switches to the Voice Call verb. `journalctl --user -u 'dummystreamhack@*'`
shows whether the voice streams opened.

## Haptics: driver in the kernel branch, untested

- The vibration motor is driven by the haptics block in the PM8350B PMIC
  (registers 0xf000/0xf100/0xf200), not a separate chip.
- Nothing's phone uses Qualcomm's reference phone settings unchanged
  (`yupik-qrd-overlay.dts` includes `yupik-qrd.dtsi`): `qcom,vmax-mv = 9150`,
  `qcom,Vrms_mv = 1270`, `qcom,lra-period-us = 5880`, closed-loop brake, sine
  drive; click effects at 3600 mV.
- The kernel branch has a driver (`qcom,hv-haptics`, direct play as
  FF_RUMBLE, 3.6 V). The kit uses it.
- `kernel/patches-alt/hv-haptics/` holds an alternative driver written for
  the old kernel. It additionally sets the LRA period and auto-resonance and
  drives a sine wave; see its README if the branch's driver vibrates weakly.
- If the driver probes but nothing moves, the likely missing piece is the
  boost: downstream asks the PMIC's PBS sequencer to turn it on by writing to
  SDAM 46 (`PBS_ARG` 0x42 = 1, then `PBS_TRIG_SET` 0xe5 = 1).

```bash
dmesg | grep -i haptics
grep -l haptics /sys/class/input/*/device/name   # find the eventN
sudo dnf install linuxconsoletools
sudo fftest /dev/input/eventN                     # pick the rumble effect
```

## Wi-Fi: partial in Nura, likely fixed by the calibration variant

WCN6750 via ath11k (AHB). The kernel branch sets
`qcom,calibration-variant = "Nothing_Spacewar"`, and the board file the kit
installs (`/usr/lib/firmware/updates/ath11k/WCN6750/hw1.0/board-2.bin`)
contains that variant (board id 255). Without it ath11k falls back to
generic calibration, a plausible cause of the "partial" rating.

## Sensors on Fedora

The sensors run on the audio DSP and need hexagonrpcd (packaged by the kit)
plus iio-sensor-proxy built with the libssc backend. Fedora's iio-sensor-proxy
is built without libssc, so auto-rotation and the light sensor will not reach
the desktop until libssc and a patched iio-sensor-proxy are packaged.

## Glyph LEDs

AW21018 on I2C1 at 0x20. The kernel branch adds a driver and describes the
LEDs as `white:glyph-1` ... `glyph-5` plus the red camera LED, so they appear
under `/sys/class/leds/`.

## Not planned yet

- Camera: the branch has front and ultra-wide camera work; the wide camera
  needs C-PHY, which the kernel doesn't support.
- Fingerprint (Goodix under-display): depends on Qualcomm's secure
  environment; very likely out of reach.
- Dual SIM, VoLTE: untested.
