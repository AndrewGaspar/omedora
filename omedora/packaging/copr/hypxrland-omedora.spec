# hypxrland-omedora.spec — Omedora's branded HypXRland session entry.
#
# This package owns only /usr/share/wayland-sessions/omedora-xr.desktop. The
# common launcher belongs to hypxrland, while omedora-settings keeps the stable
# "Omedora" session installed beside "Omedora XR" as the fallback.

Name:           hypxrland-omedora
Version:        1.1.0
Release:        1%{?dist}
Summary:        Omedora XR wayland-session entry

License:        MIT
URL:            https://github.com/omedora/omedora
Source0:        omedora-xr.desktop

BuildArch:      noarch
BuildRequires:  desktop-file-utils

# Requiring the branded stable session is deliberate: installing Omedora XR
# must add a choice to the greeter, never replace the known-good fallback.
Requires:       hypxrland-stack >= 1.1.0-1
Requires:       omedora-settings >= 0.2.0~beta.2

%description
The Omedora XR display-manager session entry. It installs the complete Fedora
HypXRland runtime stack and launches the private compositor through uwsm using
~/.config/hypr/hyprland-xr.conf while retaining the ordinary "Omedora"
Hyprland session as a stable fallback.

%prep
# Nothing to unpack; Source0 is the package-owned desktop entry.

%build
# No build step for this noarch data-only package.

%install
install -Dpm0644 %{SOURCE0} \
  %{buildroot}%{_datadir}/wayland-sessions/omedora-xr.desktop

%check
desktop-file-validate \
  %{buildroot}%{_datadir}/wayland-sessions/omedora-xr.desktop

%files
%{_datadir}/wayland-sessions/omedora-xr.desktop

%changelog
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
