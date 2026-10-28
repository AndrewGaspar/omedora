#!/bin/bash
#
# L2: Remove > Security > Fingerprint and Fido2 against real Fedora rpm, dnf
# and authselect (run by integration.sh, as root, inside omedora-test).
#
# The host is set up the way Omedora's setups leave it: authselect's
# with-fingerprint on (the Fedora fingerprint setup; Workstation's default),
# the lock-screen fingerprint service, and the PAM lines upstream's FIDO2
# setup writes (taken from the shipped script). Then both removers run
# non-interactively, and:
#   - libfido2 stays, named as needed, so openssh-clients and libssh stay;
#   - fprintd, fprintd-pam, libfprint and pam-u2f are gone;
#   - authselect no longer has with-fingerprint and its check passes, and no
#     stack loads pam_fprintd;
#   - /etc/pam.d/sudo is Fedora's file again and polkit's own PAM file applies.

set -uo pipefail

REPO=${REPO:-/repo}
. "$REPO/test/helpers.sh"
. "$REPO/omedora/test/fedora/lib/container.sh"

ensure_running_as_root
export PATH="$REPO/bin:$PATH"
export OMARCHY_PATH="$REPO"
unset OMARCHY_DISTRO

if ! dnf -y -q install --setopt=install_weak_deps=False \
  openssh-clients libssh fprintd fprintd-pam libfprint pam-u2f libfido2 authselect polkit sudo \
  >/tmp/auth-removers-install.out 2>&1; then
  cat /tmp/auth-removers-install.out >&2
  fail "install the fingerprint, FIDO2 and ssh packages"
fi
pass "install the fingerprint, FIDO2 and ssh packages"

authselect_before=$(authselect current --raw 2>/dev/null || true)
authselect select local with-fingerprint --force >/dev/null || fail "authselect select local with-fingerprint"
grep -q pam_fprintd.so /etc/pam.d/system-auth && pass "with-fingerprint puts pam_fprintd in system-auth" \
  || fail "with-fingerprint puts pam_fprintd in system-auth"

fedora_sudo=$(cat /etc/pam.d/sudo)
[[ ! -e /etc/pam.d/polkit-1 && -f /usr/lib/pam.d/polkit-1 ]] \
  && pass "polkit's PAM file is the vendor one in /usr/lib/pam.d" \
  || fail "polkit's PAM file is the vendor one in /usr/lib/pam.d"

printf '#%%PAM-1.0\nauth required pam_fprintd.so\naccount include system-auth\n' >/etc/pam.d/omarchy-lock-fingerprint
# Upstream's FIDO2 setup_pam_config, exactly as shipped.
eval "$(sed -n '/^setup_pam_config() {/,/^}/p' "$REPO/bin/omarchy-setup-security-fido2")"
setup_pam_config >/dev/null
mkdir -p /etc/fido2 && printf 'root:key\n' >/etc/fido2/fido2
grep -q pam_u2f.so /etc/pam.d/sudo && [[ -f /etc/pam.d/polkit-1 ]] \
  && pass "upstream's FIDO2 setup wrote sudo and polkit-1" \
  || fail "upstream's FIDO2 setup wrote sudo and polkit-1"

if fingerprint_out=$(omarchy-remove-security-fingerprint </dev/null 2>&1); then
  pass "the fingerprint remover exits 0"
else
  printf '%s\n' "$fingerprint_out" >&2
  fail "the fingerprint remover exits 0"
fi
if fido2_out=$(omarchy-remove-security-fido2 </dev/null 2>&1); then
  pass "the FIDO2 remover exits 0"
else
  printf '%s\n' "$fido2_out" >&2
  fail "the FIDO2 remover exits 0"
fi

assert_dnf_installed "openssh-clients is still installed" openssh-clients
assert_dnf_installed "libssh is still installed" libssh
assert_dnf_installed "libfido2 is kept" libfido2
assert_output_contains "libfido2 is kept with a message naming its dependents" "$fido2_out" "Kept libfido2: needed by"
assert_output_contains "the message names openssh-clients" "$fido2_out" "openssh-clients"
assert_dnf_not_installed "fprintd is removed" fprintd
assert_dnf_not_installed "fprintd-pam is removed" fprintd-pam
assert_dnf_not_installed "libfprint is removed" libfprint
assert_dnf_not_installed "pam-u2f is removed" pam-u2f
assert_dnf_installed "dnf is still installed" dnf5

current=$(authselect current 2>&1)
assert_output_lacks "authselect no longer lists with-fingerprint" "$current" "with-fingerprint"
if authselect check >/tmp/authselect-check.out 2>&1; then
  pass "authselect check passes"
else
  cat /tmp/authselect-check.out >&2
  fail "authselect check passes"
fi
if grep -qs pam_fprintd /etc/pam.d/system-auth /etc/pam.d/password-auth; then
  fail "no authselect stack loads pam_fprintd"
fi
pass "no authselect stack loads pam_fprintd"
[[ ! -e /etc/pam.d/omarchy-lock-fingerprint ]] && pass "the lock screen fingerprint service is removed" \
  || fail "the lock screen fingerprint service is removed"

assert_equals "/etc/pam.d/sudo is Fedora's again" "$(cat /etc/pam.d/sudo)" "$fedora_sudo"
[[ ! -e /etc/pam.d/polkit-1 ]] && pass "the setup's /etc/pam.d/polkit-1 is removed, so polkit's own applies" \
  || fail "the setup's /etc/pam.d/polkit-1 is removed, so polkit's own applies"
[[ ! -e /etc/fido2 ]] && pass "/etc/fido2 is removed" || fail "/etc/fido2 is removed"
if grep -rqs 'pam_u2f\|pam_fprintd' /etc/pam.d/sudo /etc/pam.d/system-auth /etc/pam.d/password-auth; then
  fail "sudo's stack loads neither pam_u2f nor pam_fprintd"
fi
pass "sudo's stack loads neither pam_u2f nor pam_fprintd"

# Run again: nothing left to do, and nothing fails.
omarchy-remove-security-fingerprint </dev/null >/tmp/fingerprint-again.out 2>&1 \
  && pass "the fingerprint remover is idempotent" \
  || { cat /tmp/fingerprint-again.out >&2; fail "the fingerprint remover is idempotent"; }
omarchy-remove-security-fido2 </dev/null >/tmp/fido2-again.out 2>&1 \
  && pass "the FIDO2 remover is idempotent" \
  || { cat /tmp/fido2-again.out >&2; fail "the FIDO2 remover is idempotent"; }
assert_dnf_installed "openssh-clients survives a second run" openssh-clients

# Leave the container's PAM as it found it for later sections.
if [[ -n $authselect_before ]]; then
  # shellcheck disable=SC2086  # "<profile> <feature>..." splits into arguments
  authselect select $authselect_before --force >/dev/null 2>&1 || true
fi

echo "# auth removers integration passed"
