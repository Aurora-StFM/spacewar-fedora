# Alternative haptics driver (not applied)

These patches add a `qcom-hv-haptics` driver for the PM8350B haptics block.
They were written for the earlier sc7280-mainline 7.2.9 kernel, before the
kit moved to the port developers' branch, which carries its own driver
(Vasiliy Doylov's, compatible `qcom,hv-haptics`) at the same path. The kit
uses theirs, so these don't apply any more and `build-kernel.sh` ignores
this folder.

Differences worth knowing if theirs vibrates weakly or not at all:

- This one programs the LRA resonance period (5880 us from Nothing's device
  tree, corrected for the automatic RC clock) and turns on auto-resonance.
  Theirs leaves both at the hardware defaults.
- This one drives a sine wave; theirs a square wave.
- This one waits for the boost converter to settle before starting and
  checks for the 5 V boost clamp.

Those pieces could be offered to the port developers as changes to their
driver rather than a second one.
