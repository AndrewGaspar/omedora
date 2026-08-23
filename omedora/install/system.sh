# Run the root-owned system setup from the INSTALLED payload — the same
# omarchy-apply-system the Arch ISO calls in the target chroot. On Fedora the
# Arch-only scripts inside it are gated (pacman/sddm/pam edits return early)
# and the rest dispatch to -fedora siblings (firewalld, service enables,
# docker daemon.json only-if-absent). See omedora/architecture.md
# §"Omarchy 4 setup-system gating map" for the per-file decisions.
#
# OMEDORA_SETUP_FROM_REPO=1 (dev/test seam): run setup from the CLONED repo
# tree instead of /usr/share/omarchy — used while the published COPR build
# lags the branch (the RPM payload is built from this same tree on release).

echo -e "\n\e[32mOmedora: applying system setup (omarchy-apply-system)\e[0m"

setup_env=(OMARCHY_LOG_TO_STDOUT="${OMARCHY_LOG_TO_STDOUT:-1}")
setup_cmd=(omarchy-apply-system)
if [[ -n ${OMEDORA_SETUP_FROM_REPO:-} ]]; then
  setup_env+=(
    OMARCHY_PATH="$OMEDORA_REPO_ROOT"
    OMARCHY_INSTALL="$OMEDORA_REPO_ROOT/install"
    PATH="$OMEDORA_REPO_ROOT/bin:$PATH"
  )
  setup_cmd=("$OMEDORA_REPO_ROOT/bin/omarchy-apply-system")
fi

sudo env "${setup_env[@]}" "${setup_cmd[@]}" \
  --install-user "$USER" --first-install
