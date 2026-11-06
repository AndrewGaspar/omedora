# xreal-ctl.spec — XREAL Air display-mode HID helper from the HypXRland fork.
#
# xreal-ctl switches XREAL Air glasses between 2D (1920x1080) and 3D SBS
# (3840x1080), and sets their brightness, over the glasses' HID control
# interface. It is for when no Monado runtime owns the device. Without it every
# desktop 2D/3D switch fails.
#
# The source is one C file in the fork's contrib/xreal. This spec reuses
# hypxrland.spec's pinned commit archive (same URL and file name, so the same
# .sources sha) and builds only that file, so the helper never rebuilds the
# compositor. Keep %%commit, %%snapshot and the .sources sha equal to
# hypxrland.spec's.
#
# Device access comes from Fedora's xr-hardware: its 70-xrhardware.rules tags
# every node under 3318:0424/0426/0428/0432 (the hidraw nodes included) with
# uaccess, so no rule of our own is needed.

%global snapshot 20261105.1
%global commit 96488989950e9b1e8bc48e99ac9d831fdba15ab9
%global shortcommit %(c=%{commit}; echo ${c:0:9})

Name:           xreal-ctl
Version:        0^%{snapshot}.git%{shortcommit}
Release:        1%{?dist}
Summary:        Display mode and brightness control for XREAL Air glasses

# xreal-ctl.c is part of the HypXRland fork (BSD-3-Clause). Its packet framing
# and CRC-32 table are copied from Monado's xreal_air driver (BSL-1.0).
License:        BSD-3-Clause AND BSL-1.0
URL:            https://github.com/AndrewGaspar/Hyprland
Source0:        %{url}/archive/%{commit}/hypxrland-%{commit}.tar.gz

BuildRequires:  gcc
BuildRequires:  make
BuildRequires:  pkgconfig(hidapi-hidraw)

# The uaccess rules that let the seat user open the glasses' hidraw nodes.
# 1.1.2 is the first Fedora 44 build with Air 2 Ultra (3318:0426).
Requires:       xr-hardware >= 1.1.2

%description
xreal-ctl switches XREAL Air, Air 2, Air 2 Pro and Air 2 Ultra glasses between
2D mono (1920x1080) and 3D side-by-side (3840x1080), and sets their brightness,
by speaking their HID control protocol directly. It is the flat side of the
HypXRland desktop toggle and works without a running Monado. Do not run it
while monado-xreal holds the glasses.

  xreal-ctl mode 2d|3d
  xreal-ctl brightness 0..100
  xreal-ctl detect

%prep
%setup -q -c -T
tar -xzf %{SOURCE0} --strip-components=1 \
  Hyprland-%{commit}/LICENSE Hyprland-%{commit}/contrib/xreal
# On Fedora the device rules come from xr-hardware, not the fork's
# 70-xreal.rules, so point the open-failure hint there.
sed -i 's/Is the 70-xreal\.rules udev rule installed?/Are the xr-hardware udev rules installed?/' \
  contrib/xreal/xreal-ctl.c
grep -qF 'Are the xr-hardware udev rules installed?' contrib/xreal/xreal-ctl.c

%build
# The Makefile compiles and links in one command, so the link flags ride in
# CFLAGS.
%make_build -C contrib/xreal CC="%{__cc}" \
  CFLAGS="%{build_cflags} %{build_ldflags}"

%install
install -Dpm0755 contrib/xreal/xreal-ctl %{buildroot}%{_bindir}/xreal-ctl

%check
ctl=%{buildroot}%{_bindir}/xreal-ctl
# Usage errors exit 2 before any device is opened.
for args in "" "mode" "mode 4d" "brightness" "brightness 101" "bogus"; do
  status=0
  $ctl $args >/dev/null 2>&1 || status=$?
  [[ $status == 2 ]]
done
$ctl 2>&1 | grep -qF 'usage: xreal-ctl mode 2d|3d'
# No glasses are attached to a build host.
status=0
$ctl detect >/dev/null 2>&1 || status=$?
[[ $status == 1 ]]

%files
%license LICENSE
%{_bindir}/xreal-ctl

%changelog
* Thu Nov 05 2026 omedora <noreply@omedora> - 0^20261105.1.git964889899-1
- Follow hypxrland.spec to the Nov 5 snapshot. contrib/xreal is unchanged.

* Mon Nov 02 2026 omedora <noreply@omedora> - 0^20261102.1.gite3a89bc8c-1
- Follow hypxrland.spec to the Nov 2 snapshot. contrib/xreal is unchanged.

* Mon Nov 02 2026 omedora <noreply@omedora> - 0^20261016.1.git9097b3c02-1
- Initial package: xreal-ctl from HypXRland's contrib/xreal at the commit
  hypxrland.spec pins, built alone from the same archive.
