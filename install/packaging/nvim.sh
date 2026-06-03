# Set up omarchy's Neovim config (LazyVim starter + omarchy overrides).
#
# On Arch this is provided by the omarchy-nvim package, whose omarchy-nvim-setup
# helper copies the prebuilt config + baked plugin cache into the user's
# ~/.config/nvim and ~/.local/share/nvim and links the active omarchy theme.
#
# On Fedora we do NOT package omarchy-nvim as an RPM: its build bakes the plugin
# cache by running a headless `:Lazy! sync` that fetches ~50 plugins from GitHub,
# which fails in COPR's offline mock build. Instead the installer bootstraps the
# same config directly here, on the user's networked machine, and lets Lazy sync
# the plugins locally. The config is fetched from the SAME commit-pinned
# omacom-io/omarchy-pkgs source the (retired) omarchy-nvim.spec used, so the
# behavior matches the Arch package and stays reproducible.
#
# Fail-soft throughout: a network/nvim hiccup logs and continues rather than
# aborting the whole install (matching the prior graceful-degrade intent).

if [[ $(omarchy-distro 2>/dev/null || echo arch) == "arch" ]]; then
  # Arch: omarchy-nvim package ships omarchy-nvim-setup.
  if command -v omarchy-nvim-setup >/dev/null 2>&1; then
    omarchy-nvim-setup
  else
    echo "omarchy-nvim-setup not installed; skipping Neovim config bootstrap."
  fi
  return 0 2>/dev/null || exit 0
fi

# --- Fedora: installer-side bootstrap (no omarchy-nvim RPM) ----------------

# omacom-io/omarchy-pkgs commit that the retired omarchy-nvim.spec pinned. The
# omarchy lua/plugin/lazyvim.json overrides + the setup steps come from
# pkgbuilds/omarchy-nvim/ at this commit. Bump deliberately to re-vendor.
OMARCHY_NVIM_PKGS_COMMIT="3ee1cd94953d30ee441329190d41fd69662576e1"
# LazyVim starter commit the spec pinned (the base config layer). Pinned (not a
# moving branch) for reproducibility.
OMARCHY_NVIM_LAZYVIM_COMMIT="803bc181d7c0d6d5eeba9274d9be49b287294d99"

CONFIG_DIR="$HOME/.config/nvim"

if ! command -v nvim >/dev/null 2>&1; then
  echo "nvim not installed; skipping Neovim config bootstrap." >&2
  return 0 2>/dev/null || exit 0
fi
if ! command -v git >/dev/null 2>&1; then
  echo "git not installed; skipping Neovim config bootstrap." >&2
  return 0 2>/dev/null || exit 0
fi

# Idempotent: if the config is already in place, don't clobber a user's setup.
if [[ -e "$CONFIG_DIR/lazyvim.json" ]]; then
  echo "Neovim config already present at $CONFIG_DIR; skipping bootstrap."
  return 0 2>/dev/null || exit 0
fi

# Everything below is best-effort: on any failure, log and continue the install.
omedora_nvim_bootstrap() {
  set -e
  local workdir pkgs_dir starter_dir nvim_pkg ts
  workdir="$(mktemp -d)"
  ts="$(date +%Y%m%d-%H%M%S)"
  trap 'rm -rf "$workdir"' RETURN

  # Fetch the omarchy-pkgs overrides + setup at the pinned commit.
  echo "Fetching omarchy-nvim config (omarchy-pkgs @ ${OMARCHY_NVIM_PKGS_COMMIT:0:12})..."
  pkgs_dir="$workdir/omarchy-pkgs"
  git clone --quiet --filter=blob:none --no-checkout \
    https://github.com/omacom-io/omarchy-pkgs.git "$pkgs_dir"
  git -C "$pkgs_dir" checkout --quiet "$OMARCHY_NVIM_PKGS_COMMIT"
  nvim_pkg="$pkgs_dir/pkgbuilds/omarchy-nvim"

  # Fetch the LazyVim starter (the base config) at the pinned commit.
  echo "Fetching LazyVim starter @ ${OMARCHY_NVIM_LAZYVIM_COMMIT:0:12}..."
  starter_dir="$workdir/starter"
  git clone --quiet --filter=blob:none --no-checkout \
    https://github.com/LazyVim/starter.git "$starter_dir"
  git -C "$starter_dir" checkout --quiet "$OMARCHY_NVIM_LAZYVIM_COMMIT"

  # Back up any existing config (mirrors omarchy-nvim-setup's backup behavior).
  if [[ -d "$CONFIG_DIR" ]]; then
    echo "Backing up existing Neovim config to ${CONFIG_DIR}.backup.$ts"
    mv "$CONFIG_DIR" "${CONFIG_DIR}.backup.$ts"
  fi

  # Build the config exactly as omarchy-nvim.spec's %build did: LazyVim starter
  # as the base, then layer the omarchy lua/plugin/lazyvim.json overrides on top.
  mkdir -p "$(dirname "$CONFIG_DIR")"
  cp -r "$starter_dir" "$CONFIG_DIR"
  rm -rf "$CONFIG_DIR/.git"
  cp -r "$nvim_pkg/lua" "$CONFIG_DIR/"
  cp -r "$nvim_pkg/plugin" "$CONFIG_DIR/"
  cp "$nvim_pkg/lazyvim.json" "$CONFIG_DIR/"
  echo "vim.opt.relativenumber = false" >>"$CONFIG_DIR/lua/config/options.lua"
  echo "vim.g.autoformat = false" >>"$CONFIG_DIR/lua/config/options.lua"

  # Move aside (do NOT delete) any existing Neovim data/state/cache so Lazy
  # resolves cleanly against the new config. A user may have an existing nvim
  # setup with no lazyvim.json (so the idempotency guard above wouldn't catch
  # it) — never destroy their plugin data; back it up alongside the config.
  local d
  for d in "$HOME/.local/share/nvim" "$HOME/.local/state/nvim" "$HOME/.cache/nvim"; do
    [[ -e "$d" ]] && mv "$d" "${d}.backup.$ts"
  done

  # Link the active omarchy theme (as omarchy-nvim-setup does). The target is
  # created/repointed by omarchy's theme machinery; link unconditionally so it
  # resolves once a theme is set.
  ln -snf "$HOME/.config/omarchy/current/theme/neovim.lua" \
    "$CONFIG_DIR/lua/plugins/theme.lua"

  # Download + install all plugins now (network available at install time), so
  # the first interactive launch is ready to go — same end state the prebuilt
  # package's baked cache provided.
  echo "Installing Neovim plugins (headless Lazy sync)..."
  nvim --headless "+Lazy! sync" "+qa!" || true
}

if omedora_nvim_bootstrap; then
  echo "Neovim config bootstrap complete."
else
  echo "Neovim config bootstrap failed; continuing install (set up nvim later)." >&2
fi
unset -f omedora_nvim_bootstrap 2>/dev/null || true
