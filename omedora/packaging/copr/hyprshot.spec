# hyprshot.spec — mouse-driven screenshot helper for Hyprland (omedora).
#
# Trivial noarch bash script. Adapted from solopasha/hyprlandRPM. omedora
# conventions: pinned Version, explicit Release + changelog.

Name:           hyprshot
Version:        1.3.0
Release:        1%{?dist}
Summary:        Utility to easily take screenshots in Hyprland using your mouse
BuildArch:      noarch

License:        GPL-3.0-only
URL:            https://github.com/Gustash/Hyprshot
Source0:        %{url}/archive/%{version}/%{name}-%{version}.tar.gz

Requires:       jq grim slurp wl-clipboard /usr/bin/notify-send
Recommends:     hyprpicker

%description
Hyprshot is a utility to easily take screenshots in Hyprland using your mouse.
It allows taking screenshots of windows, regions and monitors which are saved
to a folder of your choosing and copied to your clipboard.

%prep
# GitHub tag archive unpacks to Hyprshot-%{version}/.
%autosetup -n Hyprshot-%{version}

%build

%install
install -Dpm0755 %{name} -t %{buildroot}/%{_bindir}

%files
%license LICENSE
%doc README.md
%{_bindir}/%{name}

%changelog
* Sat May 30 2026 omedora <noreply@omedora> - 1.3.0-1
- Initial omedora build of hyprshot 1.3.0 (adapted from solopasha/hyprlandRPM).
