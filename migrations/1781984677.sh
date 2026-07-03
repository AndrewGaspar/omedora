# Fedora: Snapper + limine-snapper-sync are Arch/Limine-only and skip-mapped on
# Omedora (snapshots go through omedora-snapshot). This repair migration would
# always see needs_repair=1 and exec the Arch snapper.sh — skip it (mark done).
[[ "${OMARCHY_DISTRO:-$(omarchy-distro 2>/dev/null || echo arch)}" == "fedora" ]] && exit 0

echo "Normalize Snapper snapshot services"

OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"
snapper_config_script=/usr/share/omarchy/install/config/snapper.sh
if [[ ! -f $snapper_config_script ]]; then
  snapper_config_script="$OMARCHY_PATH/install/config/snapper.sh"
fi

as_root() {
  if (( EUID == 0 )); then
    "$@"
  else
    sudo "$@"
  fi
}

unit_enabled() {
  systemctl is-enabled --quiet "$1" >/dev/null 2>&1
}

unit_active() {
  systemctl is-active --quiet "$1" >/dev/null 2>&1
}

needs_repair=0

[[ -f /etc/snapper/configs/root ]] || needs_repair=1

if ! unit_enabled snapper-cleanup.timer || ! unit_active snapper-cleanup.timer; then
  needs_repair=1
fi

if ! unit_enabled limine-snapper-sync.service || ! unit_active limine-snapper-sync.service; then
  needs_repair=1
fi

(( needs_repair )) || exit 0

as_root env OMARCHY_PATH="$OMARCHY_PATH" bash -euo pipefail "$snapper_config_script"
