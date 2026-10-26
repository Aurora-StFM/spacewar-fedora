# Binary-only package staged by build-firmware.sh. Pass fwversion and fwcommit
# with --define.

%global debug_package %{nil}
%global __os_install_post %{nil}
%global _build_id_links none

Name:           nothing-spacewar-firmware
Version:        %{fwversion}
Release:        1
Summary:        Firmware for the Nothing Phone (1)
License:        LicenseRef-Proprietary
URL:            https://github.com/mainlining/firmware-nothing-spacewar
Source0:        firmware-stage.tar
BuildArch:      noarch
AutoReqProv:    no
# GPU (a660 sqe/gmu), Wi-Fi (WCN6750) and Bluetooth firmware come from Fedora.
Requires:       linux-firmware
Requires:       atheros-firmware
Requires:       qcom-firmware

%description
Proprietary firmware for the Nothing Phone (1) from
mainlining/firmware-nothing-spacewar (commit %{fwcommit}): audio, compute,
modem and Wi-Fi DSP images, the signed GPU zap shader, touchscreen firmware,
the Wi-Fi board file, and the DSP libraries and sensor registry that
hexagonrpcd serves to the sensor DSP.

%prep
%setup -q -c -T
tar -xf %{SOURCE0}

%install
cp -a . %{buildroot}/

%files
/usr/lib/firmware/qcom/sm7325/nothing
/usr/lib/firmware/updates/ath11k/WCN6750/hw1.0/board-2.bin
%dir /usr/share/qcom
%dir /usr/share/qcom/sm7325
/usr/share/qcom/sm7325/Nothing

%changelog
* Mon Oct 26 2026 Nothing Phone 1 Fedora kit <spacewar@localhost> - %{fwversion}-1
- Package mainlining/firmware-nothing-spacewar for Fedora
