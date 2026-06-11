# gazelle-tui.spec — Gazelle, a NetworkManager wifi TUI.
#
# This is omedora's Fedora stand-in for impala. impala drives iwd, but Fedora
# Workstation rides NetworkManager and ships no iwd; Gazelle speaks to
# NetworkManager (nmcli + a little dbus) and fills the same "Super+Ctrl+W wifi
# panel" slot, with the bonus of 802.1X enterprise support that impala/iwd
# lacks. omarchy-launch-wifi launches `gazelle` on Fedora and `impala` on Arch.
#
# Packaging shape: unlike terminaltexteffects (a PyPI sdist built with
# pyproject-rpm-macros), upstream gazelle is NOT a pip-installable project — it
# has no pyproject.toml/setup.py, just a flat `app.py` + `network.py` and a
# `gazelle` launcher. So this is a plain "install the scripts" spec: noarch, no
# build step. The %install layout (modules in %{_datadir}/gazelle-tui + a thin
# /usr/bin/gazelle wrapper run under the system interpreter) mirrors upstream's
# own PKGBUILD so we stay faithful to how the author ships it.

Name:           gazelle-tui
Version:        1.8.5
Release:        1%{?dist}
Summary:        Minimal NetworkManager wifi TUI with 802.1X enterprise support

License:        MIT
URL:            https://github.com/Zeus-Deus/gazelle-tui
# GitHub auto-generated tag archive. Pinned by gazelle-tui.spec.sources — note
# our pin is the *current* re-tar of the tag, which differs from the hash in
# upstream's PKGBUILD (GitHub recompressed archives historically); the content
# is identical. See OMEDORA-SOURCES.md.
Source0:        %{url}/archive/v%{version}.tar.gz#/%{name}-%{version}.tar.gz

# Pure Python, no compiled extensions: architecture-independent.
BuildArch:      noarch

# Hard runtime deps mirror upstream's PKGBUILD `depends` (Fedora-renamed):
#   python3            the interpreter the wrapper invokes
#   python3-textual    the TUI framework (requirements.txt: textual>=0.47.0)
#   python3-dbus       network.py reads a few NM properties over the system bus
#   NetworkManager     provides nmcli — the primary backend — and the daemon
Requires:       python3
Requires:       python3-textual >= 0.47.0
Requires:       python3-dbus
Requires:       NetworkManager
# Optional features (VPN/WWAN). Weak deps so a plain `dnf install gazelle-tui`
# pulls them, while omedora's installer (which sets install_weak_deps=False)
# stays lean. tomllib is stdlib on Fedora's Python (3.11+), so the PKGBUILD's
# python-tomli optdep is not needed here.
Recommends:     NetworkManager-openvpn
Recommends:     wireguard-tools
Recommends:     ModemManager

%description
Gazelle is a minimal NetworkManager TUI for managing wifi from the terminal.
It handles WPA/WPA2/WPA3-PSK, full 802.1X enterprise (PEAP/TTLS/TLS), hidden
SSIDs, WPA3-OWE, VPN (OpenVPN/WireGuard) and WWAN/cellular, and auto-matches the
active Omarchy theme. omedora launches it in place of impala on Fedora, where
impala's iwd backend is not used (NetworkManager is), via omarchy-launch-wifi.

%prep
%autosetup -n %{name}-%{version}

%build
# Nothing to compile — pure-Python scripts installed verbatim in %%install.

%install
# Mirror upstream's PKGBUILD: the two modules live under %{_datadir}/%{name},
# and a thin launcher on PATH runs them under the system interpreter with that
# directory on sys.path.
install -d %{buildroot}%{_datadir}/%{name}
install -Dm644 app.py     %{buildroot}%{_datadir}/%{name}/app.py
install -Dm644 network.py %{buildroot}%{_datadir}/%{name}/network.py

# Pin the interpreter to /usr/bin/python3 so a conda/venv python that happens to
# be first on PATH can't shadow it (same rationale as upstream's wrapper).
install -Dm755 /dev/stdin %{buildroot}%{_bindir}/gazelle <<'EOF'
#!/usr/bin/bash
exec /usr/bin/python3 -c "
import sys
sys.path.insert(0, '%{_datadir}/%{name}')
from app import Gazelle
app = Gazelle()
app.run()
"
EOF

%files
%license LICENSE
%doc README.md
%dir %{_datadir}/%{name}
%{_datadir}/%{name}/app.py
%{_datadir}/%{name}/network.py
%{_bindir}/gazelle

%changelog
* Mon Jun 02 2026 omedora <noreply@omedora> - 1.8.5-1
- Initial RPM of Gazelle (NetworkManager wifi TUI). impala replacement on
  Fedora; launched by omarchy-launch-wifi when omarchy-distro is fedora.
