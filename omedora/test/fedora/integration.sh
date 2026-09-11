#!/bin/bash

# L2 integration tests for the package-backed Omedora 4 Fedora path.

set -uo pipefail

REPO=${REPO:-/repo}
[[ -d $REPO/bin ]] || { echo "expected repo at $REPO" >&2; exit 1; }

cd "$REPO" || exit
. "$REPO/test/helpers.sh"
. "$REPO/omedora/test/fedora/lib/container.sh"

ensure_running_as_root
export PATH="$REPO/bin:$PATH"
export OMARCHY_PATH="$REPO"

echo "=== Fedora identity and L1 portability ==="
assert_equals "omarchy-distro returns fedora" "$(omarchy-distro)" "fedora"

for test in distro-test.sh pkg-map-test.sh pkg-helper-test.sh migration-gating-test.sh update-flow-test.sh; do
  if bash "$REPO/test/$test" >"/tmp/$test.out" 2>&1; then
    pass "$test passes on Fedora"
  else
    tail -40 "/tmp/$test.out" >&2
    fail "$test failed on Fedora"
  fi
done

if "$REPO/bin/omarchy-dev-validate-fedora-packages" >/tmp/validate.out 2>&1; then
  pass "real Fedora package map validates"
else
  cat /tmp/validate.out >&2
  fail "real Fedora package map validates"
fi

help_output=$("$REPO/bin/omarchy" --help 2>&1)
assert_output_contains "shared dispatcher retains upstream branding on Fedora" "$help_output" "Omarchy command center"
omedora_help=$("$REPO/bin/omedora" --help 2>&1)
assert_output_contains "omedora alias reaches the same dispatcher" "$omedora_help" "Omarchy command center"

echo "=== Real rpm/dnf package-helper path ==="
dnf -y remove cowsay >/dev/null 2>&1 || true
assert_dnf_not_installed "cowsay starts absent" cowsay

if omarchy-pkg-add cowsay >/tmp/pkg-add.out 2>&1; then
  assert_dnf_installed "omarchy-pkg-add installs an unchanged Fedora name" cowsay
else
  cat /tmp/pkg-add.out >&2
  fail "omarchy-pkg-add installs an unchanged Fedora name"
fi

if omarchy-pkg-drop cowsay >/tmp/pkg-drop.out 2>&1; then
  assert_dnf_not_installed "omarchy-pkg-drop removes the Fedora package" cowsay
else
  cat /tmp/pkg-drop.out >&2
  fail "omarchy-pkg-drop removes the Fedora package"
fi

# Exercise a real Arch-to-Fedora name translation through add/present/missing,
# not just an unchanged package name.
dnf -y remove fd-find >/dev/null 2>&1 || true
if omarchy-pkg-missing fd; then
  pass "translated fd starts missing when fd-find is absent"
else
  fail "translated fd starts missing when fd-find is absent"
fi
if omarchy-pkg-present fd; then
  fail "translated fd is not present before fd-find is installed"
else
  pass "translated fd is not present before fd-find is installed"
fi
if omarchy-pkg-add fd >/tmp/pkg-add-translated.out 2>&1; then
  assert_dnf_installed "omarchy-pkg-add installs translated fd-find" fd-find
else
  cat /tmp/pkg-add-translated.out >&2
  fail "omarchy-pkg-add installs translated fd-find"
fi
if omarchy-pkg-present fd; then
  pass "translated fd is present when fd-find is installed"
else
  fail "translated fd is present when fd-find is installed"
fi
if omarchy-pkg-missing fd; then
  fail "translated fd is not missing after fd-find is installed"
else
  pass "translated fd is not missing after fd-find is installed"
fi
omarchy-pkg-drop fd >/tmp/pkg-drop-translated.out 2>&1
assert_dnf_not_installed "omarchy-pkg-drop removes translated fd-find" fd-find

# sof-firmware has no Fedora package of that name; migrations/1784401744.sh
# reaches it through omarchy-pkg-add on Intel audio hardware and used to abort
# `omedora update` (issue #10). The map must translate it to alsa-sof-firmware
# and treat an existing alsa-sof-firmware install as present.
dnf -y remove alsa-sof-firmware >/dev/null 2>&1 || true
assert_dnf_not_installed "alsa-sof-firmware starts absent" alsa-sof-firmware
sof_dry_run=$(OMARCHY_PKG_DRY_RUN=1 omarchy-pkg-add sof-firmware 2>&1)
assert_output_contains "sof-firmware dry-run resolves to alsa-sof-firmware" \
  "$sof_dry_run" "dnf install -y --setopt=install_weak_deps=False alsa-sof-firmware"
assert_output_lacks "sof-firmware dry-run never passes the Arch name to dnf" \
  "$sof_dry_run" "install_weak_deps=False sof-firmware"
if omarchy-pkg-missing sof-firmware; then
  pass "translated sof-firmware starts missing when alsa-sof-firmware is absent"
else
  fail "translated sof-firmware starts missing when alsa-sof-firmware is absent"
fi

if dnf -y install --setopt=install_weak_deps=False alsa-sof-firmware >/tmp/sof-install.out 2>&1; then
  assert_dnf_installed "real dnf installs alsa-sof-firmware" alsa-sof-firmware
else
  cat /tmp/sof-install.out >&2
  fail "real dnf installs alsa-sof-firmware"
fi
if omarchy-pkg-missing sof-firmware; then
  fail "translated sof-firmware is not missing once alsa-sof-firmware is installed"
else
  pass "translated sof-firmware is not missing once alsa-sof-firmware is installed"
fi

# Log every dnf invocation omarchy-pkg-add makes (sudo passthrough keeps PATH
# so the logging shim is what `sudo dnf` reaches) and confirm no transaction.
mkdir -p /tmp/sof-bin
cat >/tmp/sof-bin/sudo <<'EOF'
#!/bin/bash
exec "$@"
EOF
cat >/tmp/sof-bin/dnf <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>/tmp/sof-dnf.log
exec /usr/bin/dnf "$@"
EOF
chmod +x /tmp/sof-bin/sudo /tmp/sof-bin/dnf
: >/tmp/sof-dnf.log
if PATH="/tmp/sof-bin:$PATH" omarchy-pkg-add sof-firmware >/tmp/sof-add.out 2>&1; then
  pass "omarchy-pkg-add sof-firmware succeeds when alsa-sof-firmware is installed"
else
  cat /tmp/sof-add.out >&2
  fail "omarchy-pkg-add sof-firmware succeeds when alsa-sof-firmware is installed"
fi
if [[ -s /tmp/sof-dnf.log ]]; then
  cat /tmp/sof-dnf.log >&2
  fail "omarchy-pkg-add sof-firmware performs no dnf transaction when already installed"
else
  pass "omarchy-pkg-add sof-firmware performs no dnf transaction when already installed"
fi

dnf -y remove alsa-sof-firmware >/tmp/sof-remove.out 2>&1
assert_dnf_not_installed "alsa-sof-firmware is removed again" alsa-sof-firmware

skip_output=$(omarchy-pkg-add ufw grok-bot 2>&1)
assert_output_contains "ufw is explicitly skipped" "$skip_output" "skipping 'ufw'"
assert_output_contains "grok-bot is explicitly skipped" "$skip_output" "skipping 'grok-bot'"

echo "=== Managed update resolution with real rpm queries ==="
mapfile -t managed < <(python3 "$REPO/bin/fedora/managed_packages.py")
managed_text=$(printf '%s\n' "${managed[@]}")
assert_output_contains "managed set includes omedora" "$managed_text" "omedora"
assert_output_contains "managed set includes omedora-settings" "$managed_text" "omedora-settings"
assert_output_contains "managed set includes a mapped base RPM" "$managed_text" "dotnet-runtime-10.0"
assert_output_contains "managed set includes Fedora baseline" "$managed_text" "util-linux-script"
if grep -qx 'bash' <<<"$managed_text"; then
  fail "managed set excludes unrelated installed bash RPM"
else
  pass "managed set excludes unrelated installed bash RPM"
fi
assert_output_lacks "managed set excludes skipped grok-bot" "$managed_text" "grok-bot"

echo "=== Omedora 4 COPR metadata ==="
copr=$(omedora-copr)
assert_equals "Omedora 4 selects its isolated COPR" "$copr" "agaspar/omedora-4"
if dnf -y copr enable "$copr" >/tmp/copr-enable.out 2>&1; then
  pass "$copr enables cleanly"
else
  cat /tmp/copr-enable.out >&2
  fail "$copr enables cleanly"
fi

if dnf repoquery --available omedora >/tmp/omedora-repoquery.out 2>&1 && grep -q '^omedora' /tmp/omedora-repoquery.out; then
  pass "Omedora core RPM resolves from enabled repositories"
else
  cat /tmp/omedora-repoquery.out >&2
  fail "Omedora core RPM resolves from enabled repositories"
fi

echo "=== Scoped updater transaction with real dnf/rpm ==="
dnf -y remove cowsay >/dev/null 2>&1 || true
cat >/tmp/managed-resolver <<'EOF'
#!/bin/bash
printf 'cowsay\n'
EOF
cat >/tmp/managed-dnf <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>/tmp/managed-dnf.log
exec /usr/bin/dnf "$@"
EOF
chmod +x /tmp/managed-resolver /tmp/managed-dnf
: >/tmp/managed-dnf.log
if OMEDORA_MANAGED_RESOLVER=/tmp/managed-resolver \
  OMEDORA_DNF_CMD=/tmp/managed-dnf \
  omarchy-update-system-pkgs >/tmp/managed-update.out 2>&1; then
  assert_dnf_installed "scoped updater installs its resolved package with real dnf" cowsay
else
  cat /tmp/managed-update.out >&2
  fail "scoped updater completes with real dnf/rpm"
fi
managed_install=$(grep '^install ' /tmp/managed-dnf.log | tail -1)
assert_output_contains "real updater transaction includes the managed target" "$managed_install" "cowsay"
assert_output_lacks "real updater transaction excludes unrelated installed bash" "$managed_install" "bash"
if grep -qE '^(upgrade|update)([[:space:]]|$)' /tmp/managed-dnf.log; then
  cat /tmp/managed-dnf.log >&2
  fail "real updater transaction is never an unscoped upgrade"
else
  pass "real updater transaction is never an unscoped upgrade"
fi
dnf -y remove cowsay >/dev/null 2>&1 || true

dnf -y copr disable "$copr" >/dev/null 2>&1 || true

echo "=== Core selection/provenance with real dnf5 repositories ==="
if bash "$REPO/omedora/test/fedora/core-update-integration.sh" \
  >/tmp/core-update-integration.out 2>&1; then
  cat /tmp/core-update-integration.out
else
  cat /tmp/core-update-integration.out >&2
  fail "real dnf5 core selection/provenance integration"
fi

echo "=== All Fedora L2 integration tests passed ==="
