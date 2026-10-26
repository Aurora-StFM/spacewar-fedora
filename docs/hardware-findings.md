# Hardware findings

What is known about each piece of Nothing Phone (1) hardware on the mainline
kernel, where the information came from, and the plan. Status from Nura's
wiki (October 2026) unless noted.

Sources:
- Nura wiki: <https://wiki.nura.eco/wiki/Nothing_Phone_1_(nothing-spacewar)>
- Mainline kernel: <https://github.com/sc7280-mainline/linux> (tag v7.2.9-sc7280),
  `arch/arm64/boot/dts/qcom/sm7325-nothing-spacewar.dts`
- Nothing's Android device tree: <https://github.com/NothingOSS/android_kernel_devicetree_nothing_sm7325>
- Nothing's Android kernel: <https://github.com/NothingOSS/android_kernel_msm-5.4_nothing_sm7325>
- Ubuntu Touch port (Android kernel, everything working): <https://github.com/Nonta72/nothing-spacewar>

## Already working in Nura

Flashing, USB networking, storage, battery, screen (60/90/120 Hz), touch, GPU,
camera flash, Bluetooth, GPS, SMS, mobile data, USB OTG, encryption,
accelerometer, magnetometer, ambient light and proximity. The kit's job for
these is only to package them the Fedora way.

## Audio: broken (speakers left channel only, headphones only)

- Speakers: two NXP TFA9873 amplifiers on I2C2 (0x34 earpiece, 0x35
  loudspeaker), fed by the DSP over primary MI2S. This is the only path the
  mainline device tree describes (`&sound`, "I2S Playback"). The wiki notes
  both speakers play only the left channel; the TFA driver is a rewrite that
  isn't ready for upstream.
- Microphones and headset: WCD9385 codec. The mainline device tree has only
  its power supply (`vdd_px_wcd9385`), no codec, SoundWire or LPASS macro
  nodes. The wiki says only headphones work so far.
- Calls are broken because there is no microphone path.
- The Ubuntu Touch module list confirms the parts Android uses: wcd938x,
  bolero (rx/tx/va/wsa macros), tfa98xx, SoundWire, swr_dmic.
- Plan: add the WCD9385 + LPASS RX/TX/VA macro nodes, following the Fairphone 5
  (QCM6490, same SoC family, upstream). Then UCM verbs for mics and calls.
- Nura's UCM package depends on `dummystreamhack`; find out what it works
  around before the first audio test.

## Haptics: driver written, untested on hardware

- The vibration motor is driven by the haptics block in the PM8350B PMIC
  (`qcom,hv-haptics@f000`, registers 0xf000/0xf100/0xf200, "fifo-empty"
  interrupt), not a separate chip. Ubuntu Touch loads `swr_haptics_dlkm` and
  uses Android's `qcom-hv-haptics` driver (5000 lines).
- Nothing's phone uses Qualcomm's reference phone settings unchanged
  (`yupik-qrd-overlay.dts` includes `yupik-qrd.dtsi`): `qcom,vmax-mv = 9150`,
  `qcom,Vrms_mv = 1270`, `qcom,lra-period-us = 5880`, closed-loop brake, sine
  drive; click effects at 3600 mV.
- The Nura wiki lists it as `qcom,pmi632-vib` with "custom modes required";
  mainline's `pm8xxx-vibrator` handles the older, simpler vibrator block,
  which has a different register layout, so it can't drive this one.
- `kernel/patches/0001-0003` add a new driver, `qcom-hv-haptics`
  (`qcom,pm8350b-haptics`, ~350 lines). It only uses "direct play": a
  constant amplitude with auto-resonance, exposed as an FF_RUMBLE input
  device, which is all feedbackd needs. It compiles cleanly (W=1), passes
  checkpatch, and the device tree builds.
- Peak voltage starts at 3.6 V in the device tree (downstream uses 9.15 V
  for continuous vibration). Raise it once the motor is confirmed working.
- Left out for now: brake (the motor coasts to a stop), the FIFO and
  pattern modes, closed-loop calibration, and boost control through the
  PMIC's SDAM/PBS, which downstream uses on this board.

### Testing it

```bash
dmesg | grep -i haptics                   # probe errors, if any
grep -l qcom-hv-haptics /sys/class/input/*/device/name   # find the eventN
sudo dnf install linuxconsoletools
sudo fftest /dev/input/eventN             # pick the rumble effect
```

If the probe succeeds but nothing moves, the likely missing piece is the
boost: downstream asks the PMIC's PBS sequencer to turn it on by writing to
SDAM 46 (`PBS_ARG` 0x42 = 1, then `PBS_TRIG_SET` 0xe5 = 1). That would be the
next patch.

## Wi-Fi: partial

WCN6750 via ath11k (AHB), board file `board-2.bin` from the firmware repo
(installed to `/usr/lib/firmware/updates/ath11k/WCN6750/hw1.0/`). The device
tree node is present; "partial" needs diagnosing on the phone (dmesg, `iw`).

## Sensors on Fedora

The sensors run on the audio DSP and need hexagonrpcd (packaged by the kit)
plus iio-sensor-proxy built with the libssc backend. Fedora's iio-sensor-proxy
is built without libssc, so auto-rotation and the light sensor will not reach
the desktop until libssc and a patched iio-sensor-proxy are packaged.

## Not planned yet

- Camera: wide camera needs C-PHY, which the kernel doesn't support; the
  other two need EEPROM support in the sensor drivers and libcamera.
- Fingerprint (Goodix under-display): depends on Qualcomm's secure
  environment; very likely out of reach.
- Glyph LEDs: AW21018 on I2C1 at 0x20; a mainline LED driver would be a nice
  self-contained project.
- Dual SIM, VoLTE: untested.
