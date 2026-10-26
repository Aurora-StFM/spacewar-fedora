# Built by extras/build-extras.sh with mock for aarch64.
# Pass qbversion and qbcommit with --define.

Name:           qbootctl
Version:        %{qbversion}
Release:        1%{?dist}
Summary:        Qualcomm A/B boot slot control
License:        GPL-3.0-only
URL:            https://github.com/linux-msm/qbootctl
Source0:        qbootctl-%{qbversion}.tar.gz

BuildRequires:  gcc
BuildRequires:  meson
BuildRequires:  kernel-headers

%description
qbootctl reads and changes the A/B slot attributes in the GPT of Qualcomm
phones: which slot is active, bootable and marked successful. Commit
%{qbcommit}.

%prep
%autosetup -n qbootctl-%{qbversion}

%build
%meson
%meson_build

%install
%meson_install

%files
%license LICENSE
%doc README.md
%{_bindir}/qbootctl

%changelog
* Mon Oct 26 2026 Nothing Phone 1 Fedora kit <spacewar@localhost> - %{qbversion}-1
- Package qbootctl for the Nothing Phone (1) kit
