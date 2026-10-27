# Built by extras/build-extras.sh with mock for aarch64.
# Pass dshversion and dshcommit with --define.

Name:           dummystreamhack
Version:        %{dshversion}
Release:        1%{?dist}
Summary:        Open ALSA hostless streams for Qualcomm voice calls
License:        MIT
URL:            https://codeberg.org/valpackett/dummystreamhack
Source0:        dummystreamhack-%{dshcommit}.tar.gz

BuildRequires:  gcc
BuildRequires:  meson
BuildRequires:  pkgconfig(alsa)

%description
On Qualcomm phones the call audio flows between the modem and the audio DSP
without passing through Linux, but the DSP routes are only active while an
ALSA stream on the voice PCM is open. dummystreamhack opens such a "hostless"
stream and keeps it open. The Voice Call UCM profile starts it through the
dummystreamhack@ user unit (shipped by nothing-spacewar-support).
Commit %{dshcommit}.

%prep
%autosetup -n dummystreamhack

%build
%meson
%meson_build

%install
%meson_install

%files
%{_bindir}/dummystreamhack

%changelog
* Tue Oct 27 2026 Nothing Phone 1 Fedora kit <spacewar@localhost> - %{dshversion}-1
- Package dummystreamhack for the Nothing Phone (1) kit
