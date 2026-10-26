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
%{?sysusers_requires_compat}

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
install -Dm0644 %{SOURCE1} %{buildroot}%{_sysusersdir}/hexagonrpc.conf
install -Dm0644 %{SOURCE2} %{buildroot}%{_udevrulesdir}/70-hexagonrpc.rules

%pre
%sysusers_create_compat %{SOURCE1}

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
