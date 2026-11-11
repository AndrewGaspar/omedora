# hypxrland-omedora.spec — Omedora's branded HypXRland session entry.
#
# This package owns /usr/share/wayland-sessions/omedora-xr.desktop plus the
# Lua config seeder, template, and seed-if-absent session wrapper. The common
# launcher belongs to hypxrland, while omedora-settings keeps the stable
# "Omedora" session installed beside "Omedora XR" as the fallback.

Name:           hypxrland-omedora
Version:        1.1.0
Release:        6%{?dist}
Summary:        Omedora XR wayland-session entry

License:        MIT
URL:            https://github.com/omedora/omedora
Source0:        omedora-xr.desktop
Source1:        omarchy-setup-hypxrland
Source2:        omarchy-xr-session
Source3:        hyprland-xr.lua

BuildArch:      noarch
BuildRequires:  desktop-file-utils

# Requiring the branded stable session is deliberate: installing Omedora XR
# must add a choice to the greeter, never replace the known-good fallback.
Requires:       hypxrland-stack >= 1.1.0-1
Requires:       omedora-settings >= 0.2.0~beta.2
# XREAL Air glasses are the session's primary hardware: the XREAL runtime
# (its user unit, OpenXR manifest and the Basalt 6DoF tracker) and the HID
# helper every 2D/3D desktop switch needs. Hard dependencies, not
# Recommends: Omedora installs and updates packages with weak dependencies
# off, and the stack's Suggests is never installed at all. monado-xreal -4 is
# the first that holds the performance power profile while it runs, which
# replaces this package's old session-long hold.
Requires:       monado-xreal >= 25.1.0^20261016.2.git613d8eeb1-4
Requires:       xreal-ctl >= 0^20261016.1.git9097b3c02-1
# Omarchy's floating-workspace titlebars, built for this compositor; the stock
# build fails to load into HypXRland with "Version mismatch".
Requires:       omarchy-hyprland-titlebars-hypxr

%description
The Omedora XR display-manager session entry. It installs the complete Fedora
HypXRland runtime stack, the XREAL Air runtime (monado-xreal) and its 2D/3D
helper (xreal-ctl), and launches the private compositor through uwsm using
~/.config/hypr/hyprland-xr.lua while retaining the ordinary "Omedora"
Hyprland session as a stable fallback.

%prep
# Nothing to unpack; the Sources are installed verbatim below.

%build
# No build step for this noarch data-only package.

%install
install -Dpm0644 %{SOURCE0} \
  %{buildroot}%{_datadir}/wayland-sessions/omedora-xr.desktop
install -Dpm0755 %{SOURCE1} \
  %{buildroot}%{_bindir}/omarchy-setup-hypxrland
install -Dpm0755 %{SOURCE2} \
  %{buildroot}%{_bindir}/omarchy-xr-session
install -Dpm0644 %{SOURCE3} \
  %{buildroot}%{_datadir}/hypxrland/omarchy/hyprland-xr.lua

%check
desktop-file-validate \
  %{buildroot}%{_datadir}/wayland-sessions/omedora-xr.desktop
bash -n %{buildroot}%{_bindir}/omarchy-setup-hypxrland
bash -n %{buildroot}%{_bindir}/omarchy-xr-session

%files
%{_datadir}/wayland-sessions/omedora-xr.desktop
%{_bindir}/omarchy-setup-hypxrland
%{_bindir}/omarchy-xr-session
%dir %{_datadir}/hypxrland/
%dir %{_datadir}/hypxrland/omarchy/
%{_datadir}/hypxrland/omarchy/hyprland-xr.lua

%changelog
* Wed Nov 11 2026 omedora <noreply@omedora> - 1.1.0-6
- Require omarchy-hyprland-titlebars-hypxr, the titlebars plugin built for
  HypXRland. The XR session loads it once HypXRland redirects Omarchy's
  stock plugin path to /usr/lib/hypxrland/plugins.

* Mon Nov 02 2026 omedora <noreply@omedora> - 1.1.0-5
- Drop the session-long performance power-profile hold, its helper and its
  python3-gobject-base and setsid requirements: monado-xreal -4 now holds the
  profile only while the XREAL runtime runs. Require that build.
  OMEDORA_XR_PERFORMANCE_HOLD is gone; mask
  monado-xreal-performance-hold.service to turn the hold off.

* Mon Nov 02 2026 omedora <noreply@omedora> - 1.1.0-4
- Hold the "performance" power profile for the life of the XR session through
  the PowerProfiles hold API, so the 6DoF tracker keeps turbo on battery. The
  detached helper watches the session PID and fails open.
  OMEDORA_XR_PERFORMANCE_HOLD=0 turns it off.

* Mon Nov 02 2026 omedora <noreply@omedora> - 1.1.0-3
- Require monado-xreal and xreal-ctl: a fresh install had neither the XREAL
  runtime nor the HID helper the 2D/3D desktop switch needs.

* Tue Sep 08 2026 omedora <noreply@omedora> - 1.1.0-2
- Seed the Lua XR entry point absent-only via omarchy-setup-hypxrland and run
  it through the omarchy-xr-session wrapper the greeter entry now executes.

* Fri Aug 21 2026 omedora <noreply@omedora> - 1.1.0-1
- Require the fully versioned refreshed XR stack and current Quattro settings
  while preserving the stable Omedora fallback session.

* Wed Aug 12 2026 omedora <noreply@omedora> - 1.0.0-2
- Require the package-backed Quattro settings payload while retaining the
  stable Omedora session beside Omedora XR.

* Tue Aug 11 2026 omedora <noreply@omedora> - 1.0.0-1
- Initial package: add the "Omedora XR" session beside stable Omedora.
- Launch the package-owned HypXRland compositor through uwsm using the fixed
  per-user hyprland-xr.conf entry point.
- Pull in the complete XR runtime stack through hypxrland-stack.
