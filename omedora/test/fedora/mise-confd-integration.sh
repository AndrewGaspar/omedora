#!/bin/bash
#
# L2: the mise Omedora ships reads Omarchy 4.5's system config cleanly.
#
# omedora-settings installs etc/mise/conf.d/omarchy*.toml into /etc/mise/conf.d.
# They use keys a too-old mise rejects or ignores: [wrappers.*], lazy and
# auto_update tool options, upgrade.auto_prune and system_{installs,shims}_dir.
# Install mise from the Omedora COPR, lay the files out as the spec does, and
# require that mise lists all three, reports no unknown field, applies the
# settings, and creates lazy shims with `mise reshim --system`.
#
# Runs as root inside omedora-test:fedora<N> (called from integration.sh);
# mise itself runs as the image's omedora user, offline.

set -uo pipefail

REPO=${REPO:-/repo}
. "$REPO/test/helpers.sh"
. "$REPO/omedora/test/fedora/lib/container.sh"
ensure_running_as_root

user=omedora
id "$user" >/dev/null 2>&1 || fail "test image has the $user user"
floor=$(sed -nE 's/^MIN_VERSION="([^"]+)"/\1/p' "$REPO/test/mise-spec-test.sh")
spec_version=$(awk '/^Version:/ {print $2; exit}' "$REPO/omedora/packaging/copr/mise.spec")
[[ -n $floor && -n $spec_version ]] || fail "read the mise floor and spec version"

echo "=== mise from the Omedora COPR ==="
copr=$(OMARCHY_PATH="$REPO" "$REPO/bin/omedora-copr")
dnf -y -q copr enable "$copr" >/dev/null 2>&1 || true
if dnf install -y -q --setopt=install_weak_deps=False mise >/tmp/mise-install.out 2>&1; then
  pass "mise installs from $copr"
else
  cat /tmp/mise-install.out >&2
  fail "mise installs from $copr"
fi
installed=$(rpm -q --qf '%{VERSION}' mise)
if [[ $(printf '%s\n%s\n' "$floor" "$installed" | sort -V | head -1) == "$floor" ]]; then
  pass "installed mise $installed >= the $floor floor (spec pins $spec_version)"
else
  fail "installed mise $installed is older than the $floor floor"
fi

confd=/etc/mise/conf.d
mkdir -p "$confd"
installed_files=()
for source in "$REPO"/etc/mise/conf.d/omarchy*.toml; do
  target="$confd/${source##*/}"
  [[ -e $target ]] || installed_files+=("$target")
  install -pm644 "$source" "$target"
done
cleanup() { rm -f "${installed_files[@]}" "$confd/zz-omedora-bogus.toml"; }
trap cleanup EXIT
for source in "$REPO"/etc/mise/conf.d/omarchy*.toml; do
  grep -qF "%{_sysconfdir}/mise/conf.d/${source##*/}" "$REPO/omedora/packaging/copr/omedora-settings.spec" \
    || fail "omedora-settings packages $confd/${source##*/}"
done
pass "omedora-settings packages every conf.d file mirrored here"

as_user() {
  runuser -u "$user" -- env -i HOME="/home/$user" USER="$user" PATH=/usr/bin:/bin \
    MISE_OFFLINE=1 bash -c "cd /tmp && $1"
}

echo "=== mise reads Omarchy's system config ==="
config_ls=$(as_user 'mise config ls 2>/tmp/mise-config-ls.err')
for file in omarchy.toml omarchy-tools.toml omarchy-agent-accounts.toml; do
  assert_output_contains "mise config ls lists $confd/$file" "$config_ls" "$confd/$file"
done

as_user 'mise settings ls >/dev/null 2>/tmp/mise-settings.err; mise ls >/dev/null 2>/tmp/mise-ls.err; mise reshim --system 2>/tmp/mise-reshim.err'
warnings=$(cat /tmp/mise-config-ls.err /tmp/mise-settings.err /tmp/mise-ls.err /tmp/mise-reshim.err | grep -i 'unknown' || true)
if [[ -z $warnings ]]; then
  pass "mise reports no unknown field in Omarchy's conf.d (wrappers, settings, tool options)"
else
  printf '%s\n' "$warnings" >&2
  fail "mise reports no unknown field in Omarchy's conf.d"
fi

# Negative control: the same commands do flag an unknown section and setting,
# so the clean result above means something on this mise.
printf '[settings]\nomedora_bogus_setting = 1\n[omedora_bogus_section]\nkey = 1\n' >"$confd/zz-omedora-bogus.toml"
bogus=$(as_user 'mise config ls 2>&1 >/dev/null')
rm -f "$confd/zz-omedora-bogus.toml"
assert_output_contains "mise flags an unknown setting (negative control)" "$bogus" "omedora_bogus_setting"
assert_output_contains "mise flags an unknown section (negative control)" "$bogus" "omedora_bogus_section"

assert_equals "upgrade.auto_prune is false system-wide" \
  "$(as_user 'mise settings get upgrade.auto_prune 2>/dev/null')" "false"
assert_equals "system_installs_dir resolves into the user's home" \
  "$(as_user 'mise settings get system_installs_dir 2>/dev/null')" "/home/$user/.local/share/mise/installs"
assert_equals "system_shims_dir resolves into the user's home" \
  "$(as_user 'mise settings get system_shims_dir 2>/dev/null')" "/home/$user/.local/share/mise/shims"

# lazy = true tools get a shim before they are installed; the first run
# installs them. A mise that ignored `lazy` would create none.
shims=/home/$user/.local/share/mise/shims
[[ -L $shims/claude && $(readlink "$shims/claude") == */mise ]] \
  && pass "mise reshim --system creates the lazy claude shim" \
  || { ls -la "$shims" >&2 2>/dev/null; fail "mise reshim --system creates the lazy claude shim"; }
rm -rf "/home/$user/.local/share/mise" "/home/$user/.cache/mise" "/home/$user/.local/state/mise"
