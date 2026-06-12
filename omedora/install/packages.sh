# Install the Omedora package payload (disclosed at the plan gate):
#   1. the omedora RPM (pulls omedora-settings) — /usr/bin/omarchy-*,
#      /usr/share/omarchy/**, /etc/skel seeds, the GDM session entry
#   2. the full omarchy-base set, resolved through install/packages/fedora.toml
#      by bin/fedora/pkg.py (one batched dnf transaction + flatpaks; entries
#      mapped `skip` are skipped with their reasons)
#
# install/omarchy-other.packages is deliberately ignored: it is the Arch ISO's
# hardware tier (kernels, firmware, DKMS) — out of scope on Fedora, where the
# user's Fedora install owns drivers (see omedora/architecture.md §14).

echo -e "\n\e[32mOmedora: installing the omedora packages\e[0m"

sudo dnf install -y omedora

# Resolve the base set through the package map. pkg.py batches all dnf names
# into a single transaction and verifies each installed afterwards.
base_pkgs=()
while IFS= read -r line; do
  line="${line%%#*}"; line="${line//[[:space:]]/}"
  [[ -n $line ]] && base_pkgs+=("$line")
done <"$OMEDORA_REPO_ROOT/install/omarchy-base.packages"

echo -e "\e[32mOmedora: installing the base package set (${#base_pkgs[@]} packages before mapping)\e[0m"
python3 "$OMEDORA_REPO_ROOT/bin/fedora/pkg.py" add "${base_pkgs[@]}"
