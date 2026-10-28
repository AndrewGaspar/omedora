echo "Replace the Disk Usage TUI with Disktree"

# omedora: skipped on Fedora — disktree-bin isn't packaged yet (skip-mapped),
# so dropping dua-cli would leave users with no disk-usage tool.
[[ "$(omarchy-distro)" == "fedora" ]] && exit 0

omarchy-pkg-add disktree-bin
omarchy-pkg-drop dua-cli

rm -f "$HOME/.local/share/applications/Disk Usage.desktop"
if [[ -d $HOME/.local/share/applications ]]; then
  update-desktop-database "$HOME/.local/share/applications"
fi
