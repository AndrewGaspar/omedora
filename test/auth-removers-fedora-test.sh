#!/bin/bash
#
# L1: Remove > Security > Fingerprint and Fido2 on Fedora.
#
# Both upstream removers sed-edit /etc/pam.d/sudo and polkit-1, then drop their
# packages. On Fedora they dispatch to bin/fedora/remove-security-*:
#   - fingerprint turns off authselect's with-fingerprint (what the Fedora
#     setup turned on), deletes the prints and the lock-screen service, and
#     drops fprintd, fprintd-pam and libfprint once no stack loads pam_fprintd;
#   - fido2 takes out only the exact line and polkit-1 file upstream's setup
#     wrote, never another pam_u2f line, and keeps pam-u2f while PAM loads it.
#
# The siblings work on absolute paths no unprivileged suite can write, and an
# environment override in a root-escalating script would let a caller choose
# the files it edits. Like lock-pam-migration-test.sh, this drives scratch
# copies retargeted at a fixture root, and checks the retargeting covered
# every live path. The dispatch itself runs the shipped files with a sudo that
# only logs.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

stub_bin="$TMP/bin"
calls="$TMP/calls.log"
fake="$TMP/root"
mkdir -p "$stub_bin"
user=$(id -un)

# --- PATH stubs that log exact argv ------------------------------------------
# sudo logs, then runs the command when STUB_SUDO_RUN=1 (the retargeted
# copies, whose every path is under $fake) and never otherwise.
cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash
printf 'sudo %s\n' "$*" >>"$TEST_CALLS"
[[ $1 == "-v" ]] && exit 0
[[ $1 == "-n" ]] && shift
[[ ${STUB_SUDO_RUN:-0} == 1 ]] || exit 0
exec "$@"
SH
# authselect: `current --raw` prints $STUB_AUTHSELECT (fails when it is empty,
# as authselect does on an opted-out system); everything else just logs.
cat >"$stub_bin/authselect" <<'SH'
#!/bin/bash
printf 'authselect %s\n' "$*" >>"$TEST_CALLS"
if [[ $1 == "current" ]]; then
  [[ -n ${STUB_AUTHSELECT:-} ]] || { echo "No existing configuration detected." >&2; exit 2; }
  printf '%s\n' "$STUB_AUTHSELECT"
fi
exit 0
SH
cat >"$stub_bin/fprintd-delete" <<'SH'
#!/bin/bash
printf 'fprintd-delete %s\n' "$*" >>"$TEST_CALLS"
echo "No devices available"
exit 1
SH
cat >"$stub_bin/omarchy-pkg-drop" <<'SH'
#!/bin/bash
printf 'omarchy-pkg-drop %s\n' "$*" >>"$TEST_CALLS"
SH
# rpm -qf: a file is package-owned when STUB_RPM_OWNED is 1.
cat >"$stub_bin/rpm" <<'SH'
#!/bin/bash
printf 'rpm %s\n' "$*" >>"$TEST_CALLS"
[[ ${STUB_RPM_OWNED:-0} == 1 ]]
SH
chmod +x "$stub_bin"/*

calls_matching() { grep -c -- "^$1" "$calls" || true; }
log_has() { grep -qF -- "$1" "$calls"; }

# --- retargeted copies ------------------------------------------------------
retarget() {
  local source=$1 copy=$2
  sed -e "s#/etc/pam\\.d/#$fake/etc/pam.d/#g" \
    -e "s#/usr/lib/pam\\.d/#$fake/usr/lib/pam.d/#g" \
    -e "s#/var/lib/fprint/#$fake/var/lib/fprint/#g" \
    -e "s#^authdir=/etc/fido2\$#authdir=$fake/etc/fido2#" \
    "$source" >"$copy"
  # Every remaining /etc, /usr/lib or /var path must be file content the
  # scripts match on (pam_u2f's authfile argument), never a path they touch.
  if grep -vE '^[[:space:]]*#' "$copy" | sed "s#${fake}[^[:space:]\"]*##g" |
    grep -oE '/(etc|var|usr/lib)/[^[:space:]"$]*' | grep -vxF '/etc/fido2/fido2' | grep -q .; then
    fail "$(basename "$source"): the scratch copy redirects every live path"
  fi
  pass "$(basename "$source"): the scratch copy redirects every live path"
}

fingerprint_copy="$TMP/remove-security-fingerprint"
fido2_copy="$TMP/remove-security-fido2"
retarget "$ROOT/bin/fedora/remove-security-fingerprint" "$fingerprint_copy"
retarget "$ROOT/bin/fedora/remove-security-fido2" "$fido2_copy"
grep -Fxq 'authdir=/etc/fido2' "$ROOT/bin/fedora/remove-security-fido2" ||
  fail "the FIDO2 sibling names its registration directory as a fixed literal"

run_copy() {
  local copy=$1
  : >"$calls"
  set +e
  ( export PATH="$stub_bin:$ROOT/bin:$PATH" TEST_CALLS="$calls" STUB_SUDO_RUN=1 OMARCHY_DISTRO=fedora
    bash "$copy" ) >"$TMP/out" 2>&1
  rc=$?
  set -e
}

# Fedora 44's /etc/pam.d/sudo, as the sudo package ships it.
fedora_sudo='#%PAM-1.0
auth       include      system-auth
account    include      system-auth
password   include      system-auth
session    optional     pam_keyinit.so revoke
session    required     pam_limits.so
session    include      system-auth'

reset_fake() {
  rm -rf "$fake"
  mkdir -p "$fake/etc/pam.d" "$fake/usr/lib/pam.d" "$fake/etc/authselect" "$fake/var/lib/fprint/$user"
  printf '%s\n' "$fedora_sudo" >"$fake/etc/pam.d/sudo"
  printf 'auth include system-auth\n' >"$fake/usr/lib/pam.d/polkit-1"
  printf 'auth required pam_unix.so\n' >"$fake/etc/authselect/system-auth"
  ln -s "$fake/etc/authselect/system-auth" "$fake/etc/pam.d/system-auth"
  printf 'print\n' >"$fake/var/lib/fprint/$user/print"
}

# --- fingerprint: authselect with-fingerprint on ------------------------------
reset_fake
printf 'auth required pam_fprintd.so\n' >"$fake/etc/pam.d/omarchy-lock-fingerprint"
STUB_AUTHSELECT="local with-fingerprint with-silent-lastlog" run_copy "$fingerprint_copy"
assert_equals "fingerprint: exits 0" "$rc" "0"
log_has "sudo fprintd-delete $user" && pass "fingerprint: deletes the user's prints through fprintd" \
  || { cat "$calls" >&2; fail "fingerprint: deletes the user's prints through fprintd"; }
assert_output_contains "fingerprint: an absent reader is said plainly" "$(cat "$TMP/out")" "No fingerprint reader is available now"
[[ ! -e $fake/etc/pam.d/omarchy-lock-fingerprint ]] && pass "fingerprint: removes the lock screen service" \
  || fail "fingerprint: removes the lock screen service"
log_has "sudo authselect disable-feature with-fingerprint" && log_has "sudo authselect apply-changes" \
  && pass "fingerprint: turns off authselect's with-fingerprint and applies it" \
  || { cat "$calls" >&2; fail "fingerprint: turns off authselect's with-fingerprint and applies it"; }
assert_equals "fingerprint: never calls authselect enable-feature" "$(calls_matching 'sudo authselect enable')" "0"
[[ ! -e $fake/var/lib/fprint/$user ]] && pass "fingerprint: removes the user's saved prints" \
  || fail "fingerprint: removes the user's saved prints"
log_has "omarchy-pkg-drop fprintd fprintd-pam libfprint" && pass "fingerprint: drops fprintd, fprintd-pam and libfprint" \
  || { cat "$calls" >&2; fail "fingerprint: drops fprintd, fprintd-pam and libfprint"; }
assert_equals "fingerprint: never sed-edits PAM" "$(grep -c 'sed' "$calls" || true)" "0"
assert_equals "fingerprint: Fedora's sudo stack is untouched" "$(cat "$fake/etc/pam.d/sudo")" "$fedora_sudo"
# disable-feature runs before the drop, so no stack points at a removed module.
if (( $(grep -n '^sudo authselect disable-feature' "$calls" | cut -d: -f1) < $(grep -n 'omarchy-pkg-drop' "$calls" | cut -d: -f1) )); then
  pass "fingerprint: PAM is switched off before the packages go"
else
  cat "$calls" >&2; fail "fingerprint: PAM is switched off before the packages go"
fi

# --- fingerprint: feature already off ------------------------------------------
reset_fake
STUB_AUTHSELECT="local with-silent-lastlog" run_copy "$fingerprint_copy"
assert_equals "fingerprint (feature off): exits 0" "$rc" "0"
assert_equals "fingerprint (feature off): no authselect change" "$(calls_matching 'sudo authselect')" "0"
log_has "omarchy-pkg-drop fprintd fprintd-pam libfprint" && pass "fingerprint (feature off): still drops the packages" \
  || { cat "$calls" >&2; fail "fingerprint (feature off): still drops the packages"; }

# --- fingerprint: authselect opt-out, hand-managed stack still loads it --------
reset_fake
rm "$fake/etc/pam.d/system-auth"
printf 'auth sufficient pam_fprintd.so\nauth required pam_unix.so\n' >"$fake/etc/pam.d/system-auth"
STUB_AUTHSELECT="" run_copy "$fingerprint_copy"
assert_equals "fingerprint (opt-out): exits 0" "$rc" "0"
assert_equals "fingerprint (opt-out): no authselect change" "$(calls_matching 'sudo authselect')" "0"
assert_equals "fingerprint (opt-out): keeps the packages PAM still loads" "$(calls_matching omarchy-pkg-drop)" "0"
assert_output_contains "fingerprint (opt-out): says why the packages stay" "$(cat "$TMP/out")" "still loads pam_fprintd.so"
assert_equals "fingerprint (opt-out): the hand-managed stack is untouched" \
  "$(cat "$fake/etc/pam.d/system-auth")" $'auth sufficient pam_fprintd.so\nauth required pam_unix.so'

# --- fido2: undo what upstream's setup wrote ----------------------------------
# The stacks come from the shipped setup, so a change there is caught here.
setup_fido2="$ROOT/bin/omarchy-setup-security-fido2"
setup_sudo_line=$(sed -n "s/^.*sudo sed -i '1i \\(auth .*pam_u2f.*\\)' \\/etc\\/pam.d\\/sudo\$/\\1/p" "$setup_fido2")
setup_polkit=$(sed -n "/sudo tee \\/etc\\/pam.d\\/polkit-1 >\\/dev\\/null <<'EOF'/,/^EOF\$/p" "$setup_fido2" | sed '1d;$d')
[[ -n $setup_sudo_line && -n $setup_polkit ]] || fail "fido2: read the PAM changes from the shipped setup"
pass "fido2: read the PAM changes from the shipped setup"

reset_fake
printf '%s\n%s\n' "$setup_sudo_line" "$fedora_sudo" >"$fake/etc/pam.d/sudo"
printf '%s\n' "$setup_polkit" >"$fake/etc/pam.d/polkit-1"
mkdir -p "$fake/etc/fido2" && printf 'u:key\n' >"$fake/etc/fido2/fido2"
STUB_RPM_OWNED=0 run_copy "$fido2_copy"
assert_equals "fido2: exits 0" "$rc" "0"
assert_equals "fido2: sudo is back to Fedora's stack, byte for byte" "$(cat "$fake/etc/pam.d/sudo")" "$fedora_sudo"
[[ ! -e $fake/etc/pam.d/polkit-1 && -e $fake/usr/lib/pam.d/polkit-1 ]] \
  && pass "fido2: the setup's /etc polkit-1 goes, so polkit's own file applies again" \
  || fail "fido2: the setup's /etc polkit-1 goes, so polkit's own file applies again"
[[ ! -e $fake/etc/fido2 ]] && pass "fido2: removes /etc/fido2" || fail "fido2: removes /etc/fido2"
log_has "omarchy-pkg-drop libfido2 pam-u2f" && pass "fido2: drops libfido2 and pam-u2f (drop keeps what is needed)" \
  || { cat "$calls" >&2; fail "fido2: drops libfido2 and pam-u2f"; }
assert_equals "fido2: never touches authselect" "$(calls_matching 'authselect')" "0"

# The other stack upstream has written (pam_unix) is recognised too.
reset_fake
printf '%s\n' 'auth      sufficient pam_u2f.so cue authfile=/etc/fido2/fido2' 'auth      required pam_unix.so' '' \
  'account   required pam_unix.so' 'password  required pam_unix.so' 'session   required pam_unix.so' >"$fake/etc/pam.d/polkit-1"
STUB_RPM_OWNED=0 run_copy "$fido2_copy"
[[ ! -e $fake/etc/pam.d/polkit-1 ]] && pass "fido2: the older pam_unix polkit-1 stack is removed too" \
  || fail "fido2: the older pam_unix polkit-1 stack is removed too"

# A package-owned or edited polkit-1 only loses the setup's line.
reset_fake
printf '%s\n' 'auth      sufficient pam_u2f.so cue authfile=/etc/fido2/fido2' 'auth include system-auth' 'account include system-auth' >"$fake/etc/pam.d/polkit-1"
STUB_RPM_OWNED=1 run_copy "$fido2_copy"
assert_equals "fido2: a package-owned polkit-1 keeps everything but the setup's line" \
  "$(cat "$fake/etc/pam.d/polkit-1")" $'auth include system-auth\naccount include system-auth'

# --- fido2: pam_u2f lines Omarchy did not write -----------------------------
reset_fake
printf '%s\n%s\n%s\n' "$setup_sudo_line" 'auth sufficient pam_u2f.so cue' "$fedora_sudo" >"$fake/etc/pam.d/sudo"
STUB_RPM_OWNED=0 run_copy "$fido2_copy"
assert_equals "fido2 (admin line): exits 0" "$rc" "0"
assert_equals "fido2 (admin line): only the setup's line is removed" \
  "$(cat "$fake/etc/pam.d/sudo")" "$(printf '%s\n%s' 'auth sufficient pam_u2f.so cue' "$fedora_sudo")"
assert_equals "fido2 (admin line): pam-u2f stays while PAM loads it" "$(calls_matching omarchy-pkg-drop)" "0"
assert_output_contains "fido2 (admin line): says which service still loads it" "$(cat "$TMP/out")" "$fake/etc/pam.d/sudo"

# authselect's with-pam-u2f writes pam_u2f into system-auth (a symlink).
reset_fake
printf 'auth sufficient pam_u2f.so cue\nauth required pam_unix.so\n' >"$fake/etc/authselect/system-auth"
STUB_RPM_OWNED=0 run_copy "$fido2_copy"
assert_equals "fido2 (with-pam-u2f): pam-u2f stays while authselect loads it" "$(calls_matching omarchy-pkg-drop)" "0"
assert_equals "fido2 (with-pam-u2f): authselect's stack is untouched" \
  "$(cat "$fake/etc/authselect/system-auth")" $'auth sufficient pam_u2f.so cue\nauth required pam_unix.so'

# --- dispatch: the shipped removers hand Fedora to the siblings --------------
# sudo only logs here (STUB_SUDO_RUN unset), so the live paths are only read.
for name in fingerprint fido2; do
  remover="$ROOT/bin/omarchy-remove-security-$name"
  : >"$calls"
  ( export PATH="$stub_bin:$ROOT/bin:$PATH" TEST_CALLS="$calls" OMARCHY_DISTRO=fedora STUB_AUTHSELECT="local"
    bash "$remover" ) >"$TMP/out" 2>&1 || true
  if grep -q '/pam_u2f\\.so/d\|/pam_fprintd\\.so/d\|omarchy-hw-laptop-closed' "$calls"; then
    cat "$calls" >&2; fail "$name: Fedora never runs upstream's PAM sed edits"
  fi
  pass "$name: Fedora never runs upstream's PAM sed edits"
  if grep -Fq 'libfprint-git' "$calls"; then
    cat "$calls" >&2; fail "$name: Fedora never runs upstream's package list"
  fi
  pass "$name: Fedora never runs upstream's package list"
done
: >"$calls"
( export PATH="$stub_bin:$ROOT/bin:$PATH" TEST_CALLS="$calls" OMARCHY_DISTRO=fedora STUB_AUTHSELECT="local"
  bash "$ROOT/bin/omarchy-remove-security-fingerprint" ) >"$TMP/out" 2>&1 || true
log_has "authselect current --raw" && pass "fingerprint: Fedora dispatches to the authselect sibling" \
  || { cat "$calls" "$TMP/out" >&2; fail "fingerprint: Fedora dispatches to the authselect sibling"; }

echo "# all auth-removers-fedora tests passed"
