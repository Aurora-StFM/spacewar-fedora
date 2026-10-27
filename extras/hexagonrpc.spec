# Built by extras/build-extras.sh with mock for aarch64.
# Pass hexversion and hexcommit with --define.

Name:           hexagonrpc
Version:        %{hexversion}
Release:        1%{?dist}
Summary:        FastRPC file server and client library for Qualcomm Hexagon DSPs
License:        GPL-3.0-only
URL:            https://github.com/linux-msm/hexagonrpc
Source0:        hexagonrpc-%{hexversion}.tar.gz
Source1:        hexagonrpc.sysusers
Source2:        70-hexagonrpc.rules

BuildRequires:  gcc
BuildRequires:  meson
BuildRequires:  json-c-devel
BuildRequires:  systemd-rpm-macros

%description
hexagonrpcd answers FastRPC calls from Qualcomm DSPs, serving the files the
sensor process on the DSP asks for (registry, configuration, libraries).
Needed for the accelerometer, light and proximity sensors on SC7280/SM7325
phones such as the Nothing Phone (1). Commit %{hexcommit}.

%prep
%autosetup -n hexagonrpc-%{hexversion}

%build
%meson
%meson_build

%install
%meson_install
# data/meson.build installs the units under libdir (/usr/lib64 on 64-bit
# Fedora); systemd only reads /usr/lib/systemd/system.
if [ -d %{buildroot}%{_libdir}/systemd/system ]; then
    mkdir -p %{buildroot}%{_unitdir}
    mv %{buildroot}%{_libdir}/systemd/system/*.service %{buildroot}%{_unitdir}/
    rmdir %{buildroot}%{_libdir}/systemd/system %{buildroot}%{_libdir}/systemd
fi
install -Dm0644 %{SOURCE1} %{buildroot}%{_sysusersdir}/hexagonrpc.conf
install -Dm0644 %{SOURCE2} %{buildroot}%{_udevrulesdir}/70-hexagonrpc.rules

%post
%systemd_post hexagonrpcd-adsp-sensorspd.service

%preun
%systemd_preun hexagonrpcd-adsp-sensorspd.service

%files
%license COPYING
%doc README.md
%{_bindir}/hexagonrpcd
%{_libdir}/libhexagonrpc.so*
%{_libexecdir}/hexagonrpc
%{_unitdir}/hexagonrpcd-*.service
%{_sysusersdir}/hexagonrpc.conf
%{_udevrulesdir}/70-hexagonrpc.rules
%{_mandir}/man1/*

%changelog
* Mon Oct 26 2026 Nothing Phone 1 Fedora kit <spacewar@localhost> - %{hexversion}-1
- Package hexagonrpc for the Nothing Phone (1) kit
