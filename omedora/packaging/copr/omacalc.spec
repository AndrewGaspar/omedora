# omacalc.spec — Quattro's Qt Quick calculator for Fedora.

%global debug_package %{nil}

Name:           omacalc
Version:        0.2.2
Release:        1%{?dist}
Summary:        Dead-simple Qt Quick calculator

License:        MIT AND OFL-1.1
URL:            https://github.com/omacom-io/omacalc
Source0:        https://codeload.github.com/omacom-io/omacalc/tar.gz/refs/tags/v%{version}#/%{name}-%{version}.tar.gz
Source1:        omacalc.desktop
Source2:        omacalc.svg

ExclusiveArch:  x86_64

BuildRequires:  gcc-c++
BuildRequires:  make
BuildRequires:  qt6-qtbase-devel
BuildRequires:  qt6-qtdeclarative-devel
BuildRequires:  desktop-file-utils
Requires:       hicolor-icon-theme
Requires:       qt6-qtdeclarative
Requires:       xdg-desktop-portal

%description
Omacalc is the small Qt Quick calculator used by Quattro's calculator
keybindings. It follows the desktop color scheme and provides a focused
arithmetic interface without a larger desktop calculator dependency.

%prep
%autosetup -n %{name}-%{version}

%build
./bin/build

%install
install -D -m 0755 build/omacalc %{buildroot}%{_bindir}/omacalc
install -D -m 0644 %{SOURCE1} \
  %{buildroot}%{_datadir}/applications/omacalc.desktop
install -D -m 0644 %{SOURCE2} \
  %{buildroot}%{_datadir}/icons/hicolor/scalable/apps/omacalc.svg

%check
desktop-file-validate %{buildroot}%{_datadir}/applications/omacalc.desktop
pushd tests
qmake6 tests.pro
%make_build
QT_QPA_PLATFORM=offscreen ./tst_omacalc
popd

%files
%license LICENSE
%license fonts/OFL.txt
%doc README.md
%{_bindir}/omacalc
%{_datadir}/applications/omacalc.desktop
%{_datadir}/icons/hicolor/scalable/apps/omacalc.svg

%changelog
* Wed Aug 12 2026 omedora <noreply@omedora> - 0.2.2-1
- Package the Quattro calculator from its immutable upstream release.
- Ship the desktop entry and icon used by Omarchy's Arch package.
