# Setup default work directory (and tries)
mkdir -p "$HOME/Work"
mkdir -p "$HOME/Work/tries"

# Add ./bin to path for all items in ~/Work
cat >"$HOME/Work/.mise.toml" <<'EOF'
[env]
_.path = "{{ cwd }}/bin"
EOF

# mise is required from here on. On Fedora it's currently in fedora.toml
# as skip (no Fedora packaging yet), so the binary may be missing — degrade
# gracefully rather than fail the whole install.
if ! command -v mise >/dev/null 2>&1; then
  echo "mise not installed; skipping mise trust + node install."
  return 0 2>/dev/null || exit 0
fi

mise trust ~/Work/.mise.toml

if [[ -n ${OMARCHY_CHROOT_INSTALL:-} ]]; then
  NODE_TARBALL=$(find /opt/packages -name "node-v*-linux-x64.tar.gz" -type f 2>/dev/null | head -n1)

  NODE_VERSION=$(basename "$NODE_TARBALL" | sed 's/node-v\(.*\)-linux-x64.tar.gz/\1/')
  NODE_INSTALL_DIR="$HOME/.local/share/mise/installs/node/$NODE_VERSION"

  mkdir -p "$NODE_INSTALL_DIR"
  tar -xzf "$NODE_TARBALL" \
      --strip-components=1 \
      -C "$NODE_INSTALL_DIR"

  mise use -g node@"$NODE_VERSION"
else
  mise use -g node@latest
fi
