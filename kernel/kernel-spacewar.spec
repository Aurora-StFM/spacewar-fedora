# Binary-only package: the kernel is cross-compiled by build-kernel.sh and the
# staged tree is passed in as Source0. Pass kver, kversion, krelease, kcommit
# and kbranch with --define.

%global debug_package %{nil}
%global __os_install_post %{nil}
%global __strip /bin/true
%global _build_id_links none

Name:           kernel-spacewar
Version:        %{kversion}
Release:        %{krelease}
Summary:        Linux kernel for the Nothing Phone (1)
License:        GPL-2.0-only
URL:            https://github.com/mainlining/linux
Source0:        kernel-spacewar-stage.tar
ExclusiveArch:  aarch64
AutoReqProv:    no

Requires:       coreutils
Requires:       kmod
Requires:       dracut
Requires(posttrans): systemd-udev
Requires(preun): systemd-udev
Recommends:     nothing-spacewar-support
Recommends:     nothing-spacewar-firmware

# Let dnf keep several versions installed side by side, like Fedora's kernel.
Provides:       installonlypkg(kernel)
Provides:       kernel-uname-r = %{kver}
Provides:       kernel-core-uname-r = %{kver}
Provides:       kernel-modules-uname-r = %{kver}
Provides:       kernel-modules-core-uname-r = %{kver}

%description
Linux %{kversion} with the Nura (postmarketOS) port developers' Nothing
Phone (1) patches (mainlining/linux %{kbranch}, commit %{kcommit}), built
with the branch's configuration plus the settings Fedora needs (SELinux,
compressed firmware).
Kernel %{kver}. nothing-spacewar-support turns it into an Android boot image
and writes it to the phone's boot partition.

%prep
%setup -q -c -T
tar -xf %{SOURCE0}

%install
cp -a . %{buildroot}/

# File list for everything that was staged.
(cd %{buildroot} && find usr/lib/modules/%{kver} -mindepth 1 -maxdepth 1 | sed 's|^|/|') > %{_builddir}/kernel-files.list

# Files created later by depmod and kernel-install.
for f in alias alias.bin builtin.alias.bin builtin.bin dep dep.bin devname \
         softdep symbols symbols.bin weakdep; do
    touch %{buildroot}/usr/lib/modules/%{kver}/modules.$f
done
mkdir -p %{buildroot}/boot/nothing-spacewar
for f in boot-%{kver}.img initramfs-%{kver}.img; do
    touch %{buildroot}/boot/nothing-spacewar/$f
done

%posttrans
/usr/bin/kernel-install add %{kver} /usr/lib/modules/%{kver}/vmlinuz || exit $?

%preun
/usr/bin/kernel-install remove %{kver} || :

%files -f %{_builddir}/kernel-files.list
%dir /usr/lib/modules/%{kver}
%ghost /usr/lib/modules/%{kver}/modules.alias
%ghost /usr/lib/modules/%{kver}/modules.alias.bin
%ghost /usr/lib/modules/%{kver}/modules.builtin.alias.bin
%ghost /usr/lib/modules/%{kver}/modules.builtin.bin
%ghost /usr/lib/modules/%{kver}/modules.dep
%ghost /usr/lib/modules/%{kver}/modules.dep.bin
%ghost /usr/lib/modules/%{kver}/modules.devname
%ghost /usr/lib/modules/%{kver}/modules.softdep
%ghost /usr/lib/modules/%{kver}/modules.symbols
%ghost /usr/lib/modules/%{kver}/modules.symbols.bin
%ghost /usr/lib/modules/%{kver}/modules.weakdep
%ghost %attr(0600, root, root) /boot/nothing-spacewar/boot-%{kver}.img
%ghost %attr(0600, root, root) /boot/nothing-spacewar/initramfs-%{kver}.img

%changelog
* Tue Oct 27 2026 Nothing Phone 1 Fedora kit <spacewar@localhost> - %{kversion}-%{krelease}
- Switch to mainlining/linux fekz115/spacewar (7.3.0-rc4): microphones,
  call audio (q6voice), stereo speakers (tfa98xx), haptics, Glyph LEDs,
  mainline touchscreen driver, Wi-Fi calibration variant
- Configuration from defconfig + sc7280.config instead of Nura's config
- kernel/patches/0001: fix an uninitialised codec_dai in the sm8250 sound
  card driver's LPI MI2S cases (not used by this phone)

* Mon Oct 26 2026 Nothing Phone 1 Fedora kit <spacewar@localhost> - 7.2.9-1
- First build: sc7280-mainline v7.2.9-sc7280 with Nura's config and a
  Fedora fragment (SELinux, compressed firmware, USB gadget networking)
