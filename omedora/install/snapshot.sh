# Take the pre-install btrfs snapshot the user opted into at the plan gate
# (plan.sh sets OMEDORA_SNAPSHOT=1). Runs FIRST after the gate — before any
# repo is enabled or package installed — so it captures the pristine
# pre-install state. The snapshot is read-only; roll the whole install back
# later with `omedora snapshot rollback <name>` (/home is a separate subvolume
# and is never touched). Best-effort: a snapshot failure warns but does NOT
# abort the install.
#
# Ported from omedora-3's install/preflight/fedora-snapshot.sh.

if [[ -n ${OMEDORA_SNAPSHOT:-} ]]; then
  echo -e "\e[32mOmedora: taking a pre-install btrfs snapshot (you opted in at the gate)\e[0m"
  "$OMEDORA_REPO_ROOT/bin/omedora-snapshot" create preinstall ||
    echo -e "\e[33mOmedora: pre-install snapshot failed; continuing without it.\e[0m" >&2
fi
