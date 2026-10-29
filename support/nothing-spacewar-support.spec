Name:           nothing-spacewar-support
Version:        0.9
Release:        1
Summary:        Fedora integration for the Nothing Phone (1)
License:        MIT AND BSD-3-Clause
BuildArch:      noarch
Source1:        95-nothing-spacewar.install
Source2:        spacewar-mkbootimg
Source3:        boot.conf
Source4:        install.conf
Source5:        90-nothing-spacewar.conf.dracut
Source6:        50-nothing-spacewar.preset
Source7:        81-nothing-spacewar.rules
Source9:        qbootctl-mark-successful.service
Source10:       nothing-spacewar-usb-gadget
Source11:       nothing-spacewar-usb-gadget.service
Source12:       nothing-spacewar-usb-dhcp.service
Source13:       nothing-spacewar-backup
Source14:       60-nothing-spacewar-ucm.conf
Source15:       ucm2.tar
Source16:       86-nothing-spacewar-usb.rules
Source17:       nothing-spacewar-bt-address
Source18:       nothing-spacewar-bt-address.service
Source19:       87-nothing-spacewar-bluetooth.rules

Requires:       python3
Requires:       dracut
Requires:       systemd-udev
# pam_systemd.so: logind sessions and seats for the graphical login.
Requires:       systemd-pam
# Battery level for the shell (a weak dependency the image build skips).
Requires:       upower
Requires:       util-linux
Requires:       coreutils
Requires:       NetworkManager
Requires:       iproute
Requires:       dnsmasq
Requires:       openssh-server
Requires:       rmtfs
Requires:       tqftpserv
Requires:       hexagonrpc
Requires:       qbootctl
Requires:       ModemManager
# btmgmt, to give the Bluetooth chip an address.
Requires:       bluez
# Holds the voice call streams open (Voice Call UCM profile).
Requires:       dummystreamhack

%description
Glue that makes Fedora boot and run on the Nothing Phone (1) with
kernel-spacewar:
- kernel-install plugin that packs kernel, initramfs and device tree into an
  Android boot image and writes it to the active boot slot
- dracut settings for a small generic initramfs with display and touch
- presets for rmtfs, tqftpserv, hexagonrpcd's sensor service and A/B slot
  marking
- a Bluetooth address for the WCN6750, which comes up without one
- USB networking (NCM, phone at 172.16.42.1, DHCP for the computer) for SSH
- nothing-spacewar-backup, which saves the partitions a reflash can't restore
- ALSA UCM profiles for SC7280 devices (sc7280-mainline/alsa-ucm-conf
  commit %{ucmcommit}) plus the kit's Voice Call profile for this phone,
  used through ALSA_CONFIG_UCM2

%prep
%setup -q -c -T
tar -xf %{SOURCE15}

%build

%install
install -Dm0755 %{SOURCE1} %{buildroot}/usr/lib/kernel/install.d/95-nothing-spacewar.install
install -Dm0755 %{SOURCE2} %{buildroot}/usr/libexec/nothing-spacewar/spacewar-mkbootimg
install -Dm0644 %{SOURCE3} %{buildroot}/usr/lib/nothing-spacewar/boot.conf
install -Dm0644 %{SOURCE4} %{buildroot}/etc/kernel/install.conf
install -Dm0644 %{SOURCE5} %{buildroot}/usr/lib/dracut/dracut.conf.d/90-nothing-spacewar.conf
install -Dm0644 %{SOURCE6} %{buildroot}/usr/lib/systemd/system-preset/50-nothing-spacewar.preset
install -Dm0644 %{SOURCE7} %{buildroot}/usr/lib/udev/rules.d/81-nothing-spacewar.rules
install -Dm0644 %{SOURCE9} %{buildroot}/usr/lib/systemd/system/qbootctl-mark-successful.service
install -Dm0755 %{SOURCE10} %{buildroot}/usr/libexec/nothing-spacewar/nothing-spacewar-usb-gadget
install -Dm0644 %{SOURCE11} %{buildroot}/usr/lib/systemd/system/nothing-spacewar-usb-gadget.service
install -Dm0644 %{SOURCE12} %{buildroot}/usr/lib/systemd/system/nothing-spacewar-usb-dhcp.service
install -Dm0644 %{SOURCE16} %{buildroot}/usr/lib/udev/rules.d/86-nothing-spacewar-usb.rules
install -Dm0755 %{SOURCE17} %{buildroot}/usr/libexec/nothing-spacewar/nothing-spacewar-bt-address
install -Dm0644 %{SOURCE18} %{buildroot}/usr/lib/systemd/system/nothing-spacewar-bt-address.service
install -Dm0644 %{SOURCE19} %{buildroot}/usr/lib/udev/rules.d/87-nothing-spacewar-bluetooth.rules
install -Dm0755 %{SOURCE13} %{buildroot}/usr/bin/nothing-spacewar-backup
install -Dm0644 %{SOURCE14} %{buildroot}/usr/lib/environment.d/60-nothing-spacewar-ucm.conf
mkdir -p %{buildroot}/usr/share/nothing-spacewar/alsa %{buildroot}/etc/nothing-spacewar
cp -a ucm2 %{buildroot}/usr/share/nothing-spacewar/alsa/

%post
%systemd_post qbootctl-mark-successful.service nothing-spacewar-usb-gadget.service nothing-spacewar-usb-dhcp.service

%preun
%systemd_preun qbootctl-mark-successful.service nothing-spacewar-usb-gadget.service nothing-spacewar-usb-dhcp.service

%files
/usr/lib/kernel/install.d/95-nothing-spacewar.install
%config(noreplace) /etc/kernel/install.conf
/usr/libexec/nothing-spacewar
/usr/lib/nothing-spacewar
/usr/lib/dracut/dracut.conf.d/90-nothing-spacewar.conf
/usr/lib/systemd/system-preset/50-nothing-spacewar.preset
/usr/lib/udev/rules.d/81-nothing-spacewar.rules
/usr/lib/systemd/system/qbootctl-mark-successful.service
/usr/lib/systemd/system/nothing-spacewar-usb-gadget.service
/usr/lib/systemd/system/nothing-spacewar-usb-dhcp.service
/usr/lib/udev/rules.d/86-nothing-spacewar-usb.rules
/usr/lib/udev/rules.d/87-nothing-spacewar-bluetooth.rules
/usr/lib/systemd/system/nothing-spacewar-bt-address.service
/usr/lib/environment.d/60-nothing-spacewar-ucm.conf
/usr/bin/nothing-spacewar-backup
/usr/share/nothing-spacewar
%dir /etc/nothing-spacewar

%changelog
* Thu Oct 29 2026 Nothing Phone 1 Fedora kit <spacewar@localhost> - 0.9-1
- UCM: microphones through DEC0 with the measured AMIC mapping (bottom,
  top, headset); card mixer instead of default:, no ctl-remap

* Wed Oct 28 2026 Nothing Phone 1 Fedora kit <spacewar@localhost> - 0.8-1
- Bluetooth address: retry until the chip's firmware setup has finished
  (the first attempt came too early and failed with Invalid Index)

* Wed Oct 28 2026 Nothing Phone 1 Fedora kit <spacewar@localhost> - 0.7-1
- Set a stable Bluetooth address at boot (derived from the serial number);
  without one the WCN6750 stays unconfigured and BlueZ finds no controller

* Wed Oct 28 2026 Nothing Phone 1 Fedora kit <spacewar@localhost> - 0.6-1
- Require upower so Plasma Mobile and Phosh show the battery level

* Tue Oct 27 2026 Nothing Phone 1 Fedora kit <spacewar@localhost> - 0.5-1
- Require systemd-pam: without pam_systemd the SDDM/greetd sessions get no
  logind seat and the compositor can't open the display (black screen)
- nothing-spacewar-backup saves into the calling user's home, owned by
  them, so scp can copy it straight off

* Tue Oct 27 2026 Nothing Phone 1 Fedora kit <spacewar@localhost> - 0.4-1
- USB networking: configure usb0 in the gadget script and serve DHCP with
  dnsmasq; NetworkManager ignores gadget interfaces, so the shared
  connection profile never came up (laptop saw NO-CARRIER)

* Tue Oct 27 2026 Nothing Phone 1 Fedora kit <spacewar@localhost> - 0.3-1
- Drop the dummystreamhack@ user unit; the dummystreamhack package ships
  its own

* Tue Oct 27 2026 Nothing Phone 1 Fedora kit <spacewar@localhost> - 0.2-1
- Voice Call UCM profile (earpiece, speakerphone, bottom microphone) and
  the dummystreamhack@ user unit it starts

* Mon Oct 26 2026 Nothing Phone 1 Fedora kit <spacewar@localhost> - 0.1-1
- First version: boot image plugin, dracut settings, services, USB
  networking, partition backup tool, SC7280 UCM profiles
