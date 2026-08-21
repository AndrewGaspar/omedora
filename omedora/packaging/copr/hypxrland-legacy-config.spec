# hypxrland-legacy-config.spec — classic hyprlang defaults for HypXRland.
#
# Quattro's stable Hyprland session is configured in Lua, while HypXRland's
# OpenXR directives currently exist only in classic hyprlang. This package
# installs the last Omedora 3 default/hypr *.conf tree beside Quattro's *.lua
# files. Stable Omedora ignores it; hyprland-xr.conf can continue sourcing the
# classic defaults through ~/.local/share/omarchy/default/hypr after an upgrade.

%global commit c83a2dd6cca6d444648f4442062b115a2b443e2e
%global shortcommit %(c=%{commit}; echo ${c:0:9})

Name:           hypxrland-legacy-config
Version:        3.8.4^20260812.1.git%{shortcommit}
Release:        2%{?dist}
Summary:        Classic Hyprland defaults for Omedora XR

License:        MIT
URL:            https://github.com/AndrewGaspar/omedora
Source0:        %{url}/archive/%{commit}/%{name}-%{commit}.tar.gz

BuildArch:      noarch
Requires:       omedora-settings >= 0.2.0~beta.2

%description
HypXRland's OpenXR configuration syntax is not yet available through Quattro's
Lua bindings. This package preserves Omedora 3's immutable classic hyprlang
default tree under /usr/share/omarchy/default/hypr so Omedora XR works on fresh
Omedora 4 installs and after an Omedora 3 to 4 upgrade. It does not replace or
modify Quattro's Lua configuration.

%prep
%autosetup -n omedora-%{commit} -p1

%build
# Data-only compatibility package.

%install
while IFS= read -r -d '' source; do
  install -Dpm0644 "$source" \
    "%{buildroot}%{_datadir}/omarchy/$source"
done < <(find default/hypr -type f -name '*.conf' -print0)

# Adapt the classic session's critical startup path to Quattro. The compositor
# syntax remains classic hyprlang, but its desktop services are the Quattro
# shell and provisioner rather than Omedora 3's retired bar/notification stack.
cat >%{buildroot}%{_datadir}/omarchy/default/hypr/autostart.conf <<'EOF'
exec-once = systemctl --user import-environment $(env | cut -d'=' -f 1)
exec-once = dbus-update-activation-environment --systemd --all
exec-once = omarchy-launch-shell
exec-once = omarchy-provision-first-run
exec-once = omarchy-powerprofiles-init
exec-once = uwsm-app -- omarchy-hyprland-monitor-watch
exec-once = uwsm-app -- udiskie --automount --no-notify --no-tray
exec-once = sleep 2 && omarchy-hook post-boot
EOF

# Translate removed Omedora 3 command names used by the classic bindings.
find %{buildroot}%{_datadir}/omarchy/default/hypr -type f -name '*.conf' -exec sed -i \
  -e 's|omarchy-capture-text-extraction|omarchy-capture-text|g' \
  -e 's|omarchy-toggle-waybar|omarchy-toggle-bar|g' \
  -e 's|omarchy-launch-audio|omarchy-shell shell toggle omarchy.audio|g' \
  -e 's|omarchy-launch-bluetooth|omarchy-shell shell toggle omarchy.bluetooth|g' \
  -e 's|omarchy-launch-wifi|omarchy-shell shell toggle omarchy.network|g' \
  -e 's|omarchy-swayosd-client --output-volume|omarchy-audio-output-volume|g' \
  -e 's|omarchy-swayosd-client --playerctl next|omarchy-shell media next|g' \
  -e 's|omarchy-swayosd-client --playerctl play-pause|omarchy-shell media playPause|g' \
  -e 's|omarchy-swayosd-client --playerctl previous|omarchy-shell media previous|g' \
  -e 's|makoctl dismiss --all|omarchy-shell notifications dismissAll|g' \
  -e 's|makoctl dismiss|omarchy-shell notifications dismissOne|g' \
  -e 's|makoctl invoke|omarchy-shell notifications invokeLast|g' \
  -e 's|makoctl restore|omarchy-shell notifications showHistory|g' \
  -e 's|omarchy-launch-walker -m symbols|omarchy-shell shell toggle omarchy.emojis|g' \
  -e 's|omarchy-launch-walker|omarchy-menu toggle apps|g' \
  {} +

%check
test -f %{buildroot}%{_datadir}/omarchy/default/hypr/envs.conf
test -f %{buildroot}%{_datadir}/omarchy/default/hypr/looknfeel.conf
test -f %{buildroot}%{_datadir}/omarchy/default/hypr/autostart.conf
test -f %{buildroot}%{_datadir}/omarchy/default/hypr/input.conf
test -f %{buildroot}%{_datadir}/omarchy/default/hypr/windows.conf
test -f %{buildroot}%{_datadir}/omarchy/default/hypr/bindings/media.conf
test -f %{buildroot}%{_datadir}/omarchy/default/hypr/bindings/clipboard.conf
test -f %{buildroot}%{_datadir}/omarchy/default/hypr/bindings/tiling-v2.conf
test "$(find %{buildroot}%{_datadir}/omarchy/default/hypr -type f -name '*.conf' | wc -l)" -eq 35
test "$(find %{buildroot}%{_datadir}/omarchy/default/hypr -type f ! -name '*.conf' | wc -l)" -eq 0
grep -F 'exec-once = omarchy-launch-shell' %{buildroot}%{_datadir}/omarchy/default/hypr/autostart.conf
grep -F 'exec-once = omarchy-provision-first-run' %{buildroot}%{_datadir}/omarchy/default/hypr/autostart.conf
! grep -RE 'hypridle|mako|waybar|swaybg|omarchy-first-run|omarchy-launch-walker|omarchy-swayosd-client' \
  %{buildroot}%{_datadir}/omarchy/default/hypr

%files
%license LICENSE
%doc README.md
%{_datadir}/omarchy/default/hypr/

%changelog
* Fri Aug 21 2026 omedora <noreply@omedora> - 3.8.4^20260812.1.gitc83a2dd6c-2
- Require the package-backed Quattro settings payload that owns the parallel
  Lua defaults consumed beside this classic hyprlang bridge.

* Wed Aug 12 2026 omedora <noreply@omedora> - 3.8.4^20260812.1.gitc83a2dd6c-1
- Preserve the immutable Omedora 3 classic hyprlang defaults for Omedora XR.
- Adapt its startup and removed command names to Quattro while installing only
  .conf files beside the package-owned Lua defaults.
