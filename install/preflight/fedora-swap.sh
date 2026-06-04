# Fedora coexistence: apply the foreign-repo package replacement the user
# consented to at the plan-then-confirm gate (fedora-plan.sh).
#
# The gate runs BEFORE the omedora repos are enabled, so it can't perform the
# swap itself — it only records the user's "Replace" choice by exporting
# OMEDORA_REPLACE_FOREIGN=1 (that export reaches here because run_logged's
# child shell inherits install.sh's environment). This step runs AFTER
# fedora-repos.sh has enabled the omedora COPR + RPM Fusion, so the omedora
# targets resolve. The user already consented at the gate (that was the single
# yes), so apply non-interactively with --yes.
#
# omedora-replace-foreign drives `sudo dnf` swap/distro-sync, disabling the
# foreign repo for the transaction. It's a no-op if nothing is left to replace.
#
# Sourced only from install/preflight/all.sh on Fedora hosts, after
# fedora-repos.sh. The Arch path is unchanged.

if [[ -n ${OMEDORA_REPLACE_FOREIGN:-} ]]; then
  echo -e "\e[32mFedora: replacing foreign-repo Hyprland packages with omedora's builds (you chose Replace)\e[0m"
  omedora-replace-foreign --yes
fi
