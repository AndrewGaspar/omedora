# Includes lazyvim and the themes.
# omarchy-nvim-setup ships with the omarchy-nvim package. On Fedora that
# package is mapped to skip (no Fedora packaging yet), so the helper may not
# be present; degrade gracefully rather than fail the install.
if command -v omarchy-nvim-setup >/dev/null 2>&1; then
  omarchy-nvim-setup
else
  echo "omarchy-nvim-setup not installed; skipping Neovim config bootstrap."
fi
