# Per-user finalization — the runtime tweaks /etc/skel can't seed (skill
# symlinks, xdg user dirs + GTK bookmarks, theme, mise, default keyring, and
# the default browser/mailto handlers). On Fedora the browser/mailto claims
# are only-if-unset (an existing installed default is respected — disclosed at
# the plan gate), and ~/.XCompose is backed up before being written.
#
# --first-install marks the shipped user migrations complete for this user and
# selects the headless theme-set path (no compositor needed), exactly like the
# Arch ISO's target-chroot call.
#
# OMEDORA_SETUP_FROM_REPO=1: same dev/test seam as system.sh.

echo -e "\n\e[32mOmedora: finalizing user setup (omarchy-finalize-user)\e[0m"

finalize_cmd=(omarchy-finalize-user)
if [[ -n ${OMEDORA_SETUP_FROM_REPO:-} ]]; then
  export OMARCHY_PATH="$OMEDORA_REPO_ROOT"
  export OMARCHY_INSTALL="$OMEDORA_REPO_ROOT/install"
  export PATH="$OMEDORA_REPO_ROOT/bin:$PATH"
  finalize_cmd=("$OMEDORA_REPO_ROOT/bin/omarchy-finalize-user")
fi

"${finalize_cmd[@]}" --force --first-install

# Fedora chromium naming/flags bridge (user-level; see the file header).
source "$OMEDORA_REPO_ROOT/omedora/install/chromium-bridge.sh"
