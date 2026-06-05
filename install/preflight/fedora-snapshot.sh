# Take the pre-install btrfs snapshot the user opted into at the gate
# (fedora-plan.sh sets OMEDORA_SNAPSHOT=1; the export reaches here because
# run_logged's child shell inherits install.sh's environment).
#
# Runs EARLY — after begin.sh but before fedora-repos.sh enables the COPR and
# before any package swap/install — so it captures the pristine pre-install
# state. The snapshot is read-only; roll the whole install back later with
# `omedora snapshot rollback <name>` (your /home is a separate subvolume and is
# never touched). Best-effort: a snapshot failure warns but does NOT abort the
# install.
#
# Sourced only from install/preflight/all.sh on Fedora hosts.

if [[ -n ${OMEDORA_SNAPSHOT:-} ]]; then
  echo -e "\e[32mFedora: taking a pre-install btrfs snapshot (you opted in at the gate)\e[0m"
  omedora-snapshot create preinstall \
    || echo -e "\e[33mFedora: pre-install snapshot failed; continuing without it.\e[0m" >&2
fi
