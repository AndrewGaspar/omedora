# omarchy-nvim.spec — omarchy's pre-built LazyVim distribution (omedora).
#
# omarchy-nvim is NOT upstream LazyVim and NOT a plain config clone: it's a real
# package (omacom-io/omarchy-pkgs) that ships, under /usr/share/omarchy-nvim/,
# a LazyVim starter customized with omarchy's lua/ + plugin/ overrides AND a
# PRE-BAKED plugin cache (the data/ tree, produced by running headless
# `:Lazy! sync` at build time) so first nvim launch is instant/offline. It also
# ships /usr/bin/omarchy-nvim-setup, which copies that tree into the user's
# ~/.config/nvim + ~/.local/share/nvim and links the omarchy theme.
#
# omedora's install already calls omarchy-nvim-setup if present
# (install/packaging/nvim.sh), so this RPM drops in with no shared-file edits —
# same pattern as omarchy-walker. This is a FROM-SOURCE build: it reproduces the
# omarchy-pkgs PKGBUILD's build() (headless Lazy sync) and package() steps.
#
# Two build-time Sources, both fetched by spectool -g (build-local.sh):
#   Source0: omacom-io/omarchy-pkgs tarball — we only use pkgbuilds/omarchy-nvim/
#            (the lua/plugin/lazyvim.json overrides + the omarchy-nvim-setup
#            script). omarchy-pkgs is a rolling repo with no release tags, so we
#            pin to a commit for a reproducible build (bump it + Version on
#            update; Version tracks the PKGBUILD's pkgver).
#   Source1: the LazyVim starter tarball (what the PKGBUILD's source= points at).
# The Lazy sync step downloads plugins from GitHub at build time (network, like
# swayosd's cargo fetch); a COPR host has network too.

%global pkgs_commit 3ee1cd94953d30ee441329190d41fd69662576e1
# LazyVim starter pinned to a commit (not refs/heads/main) so the source is
# reproducible and the .sources sha256 pin is stable. Bump deliberately when
# re-vendoring against a newer starter (the starter is only the base config
# layer baked at build time; see %build).
%global lazyvim_commit 803bc181d7c0d6d5eeba9274d9be49b287294d99

Name:           omarchy-nvim
Version:        2026.5.25
Release:        1%{?dist}
Summary:        omarchy's pre-built LazyVim configuration with cached plugins
BuildArch:      noarch

# omarchy's lua/plugin overrides are MIT; bundled LazyVim starter is also MIT.
License:        MIT
URL:            https://github.com/omacom-io/omarchy-pkgs

# omarchy-pkgs repo (we use only pkgbuilds/omarchy-nvim/ from it). GitHub's
# archive for a commit unpacks to omarchy-pkgs-<commit>/.
Source0:        %{url}/archive/%{pkgs_commit}/omarchy-pkgs-%{pkgs_commit}.tar.gz
# LazyVim starter (the base config the omarchy overrides layer on top of).
# Pinned to a commit (renamed for a stable filename) — was refs/heads/main,
# a moving branch whose sha256 pin broke on every upstream push.
Source1:        https://github.com/LazyVim/starter/archive/%{lazyvim_commit}.tar.gz#/lazyvim-starter-%{lazyvim_commit}.tar.gz

# --- Build toolchain -------------------------------------------------------
# neovim runs the headless `:Lazy! sync`; git clones the plugins; node/npm +
# tree-sitter-cli are needed by some LazyVim plugins' build steps (matches the
# PKGBUILD's makedepends).
BuildRequires:  neovim
BuildRequires:  git
BuildRequires:  nodejs
BuildRequires:  npm
BuildRequires:  tree-sitter-cli

# --- Runtime ---------------------------------------------------------------
# Neovim runs the config; git restores the cached plugin working trees in
# omarchy-nvim-setup; gum drives the setup script's confirm prompt.
Requires:       neovim >= 0.9.0
Requires:       git
Requires:       gum

# Pre-baked plugin cache: no source for debuginfo, nothing to strip.
%global debug_package %{nil}

%description
omarchy-nvim is omarchy's batteries-included Neovim setup: a LazyVim starter
customized with omarchy's plugin and behavior overrides, shipped with its plugin
cache pre-built so the first launch is instant and offline-capable. The
omarchy-nvim-setup helper installs it into the current user's Neovim config and
links the active omarchy theme.

%prep
# omarchy-pkgs tarball unpacks to omarchy-pkgs-<commit>/. Work from the
# omarchy-nvim subdir; stage the LazyVim starter alongside it.
%setup -q -n omarchy-pkgs-%{pkgs_commit}
tar -xf %{SOURCE1}   # -> starter-%{lazyvim_commit}/

%build
set -e
PKG=pkgbuilds/omarchy-nvim

# Isolated HOME so the headless nvim run doesn't touch the build user's real
# config (mirrors the PKGBUILD's build-home sandbox).
export HOME="$PWD/build-home"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_STATE_HOME="$HOME/.local/state"
export XDG_CACHE_HOME="$HOME/.cache"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"

# LazyVim starter -> nvim config, then layer omarchy's overrides on top.
cp -r starter-%{lazyvim_commit} "$XDG_CONFIG_HOME/nvim"
rm -rf "$XDG_CONFIG_HOME/nvim/.git"
cp -r "$PKG/lua" "$XDG_CONFIG_HOME/nvim/"
cp -r "$PKG/plugin" "$XDG_CONFIG_HOME/nvim/"
cp "$PKG/lazyvim.json" "$XDG_CONFIG_HOME/nvim/"
echo "vim.opt.relativenumber = false" >>"$XDG_CONFIG_HOME/nvim/lua/config/options.lua"
echo "vim.g.autoformat = false" >>"$XDG_CONFIG_HOME/nvim/lua/config/options.lua"

# Download + install all plugins into the cache (network at build time).
echo "Installing LazyVim plugins (headless)..."
nvim --headless "+Lazy! sync" "+qa!" || true

%install
set -e
PKG=pkgbuilds/omarchy-nvim
SHARE=%{buildroot}%{_datadir}/%{name}
install -dm755 "$SHARE"

# Ship the customized config + the pre-baked plugin data tree.
cp -a "$PWD/build-home/.config/nvim" "$SHARE/config"
cp -a "$PWD/build-home/.local/share/nvim" "$SHARE/data"
# Drop the regenerable site/ cache contents but keep the dir (matches PKGBUILD).
rm -rf "$SHARE/data/site"/*
mkdir -p "$SHARE/data/site"

# Normalize perms: dirs 755, files 644.
chmod -R 755 "$SHARE"
find "$SHARE" -type f -exec chmod 644 {} \;

# The user-facing setup helper.
install -Dm755 "$PKG/omarchy-nvim-setup" %{buildroot}%{_bindir}/omarchy-nvim-setup

%files
%{_bindir}/omarchy-nvim-setup
%{_datadir}/%{name}

%changelog
* Sat May 30 2026 omedora <noreply@omedora> - 2026.5.25-1
- Initial from-source build of omarchy-nvim, reproducing the omarchy-pkgs
  PKGBUILD: LazyVim starter + omarchy lua/plugin overrides with the plugin
  cache pre-built via headless `:Lazy! sync`, plus the omarchy-nvim-setup helper.
- Plugins fetched from GitHub at build time (network), matching the upstream
  PKGBUILD's build step.
