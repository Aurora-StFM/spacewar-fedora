Name:           nothing-spacewar-support
Version:        0.3
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
Source12:       nothing-spacewar-usb.nmconnection
Source13:       nothing-spacewar-backup
Source14:       60-nothing-spacewar-ucm.conf
Source15:       ucm2.tar

Requires:       python3
Requires:       dracut
Requires:       systemd-udev
Requires:       util-linux
Requires:       coreutils
Requires:       NetworkManager
Requires:       openssh-server
Requires:       rmtfs
Requires:       tqftpserv
Requires:       hexagonrpc
Requires:       qbootctl
Requires:       ModemManager
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
- USB networking (NCM, phone at 172.16.42.1) for SSH during bring-up
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
install -Dm0600 %{SOURCE12} %{buildroot}/usr/lib/NetworkManager/system-connections/nothing-spacewar-usb.nmconnection
install -Dm0755 %{SOURCE13} %{buildroot}/usr/bin/nothing-spacewar-backup
install -Dm0644 %{SOURCE14} %{buildroot}/usr/lib/environment.d/60-nothing-spacewar-ucm.conf
mkdir -p %{buildroot}/usr/share/nothing-spacewar/alsa %{buildroot}/etc/nothing-spacewar
cp -a ucm2 %{buildroot}/usr/share/nothing-spacewar/alsa/

%post
%systemd_post qbootctl-mark-successful.service nothing-spacewar-usb-gadget.service

%preun
%systemd_preun qbootctl-mark-successful.service nothing-spacewar-usb-gadget.service

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
/usr/lib/NetworkManager/system-connections/nothing-spacewar-usb.nmconnection
/usr/lib/environment.d/60-nothing-spacewar-ucm.conf
/usr/bin/nothing-spacewar-backup
/usr/share/nothing-spacewar
%dir /etc/nothing-spacewar

%changelog
* Tue Oct 27 2026 Nothing Phone 1 Fedora kit <spacewar@localhost> - 0.3-1
- Drop the dummystreamhack@ user unit; the dummystreamhack package ships
  its own

* Tue Oct 27 2026 Nothing Phone 1 Fedora kit <spacewar@localhost> - 0.2-1
- Voice Call UCM profile (earpiece, speakerphone, bottom microphone) and
  the dummystreamhack@ user unit it starts

* Mon Oct 26 2026 Nothing Phone 1 Fedora kit <spacewar@localhost> - 0.1-1
- First version: boot image plugin, dracut settings, services, USB
  networking, partition backup tool, SC7280 UCM profiles
