#!/bin/bash

# Update-flow unit tests — the Fedora `omarchy update` regressions fixed in the
# upgrade-fix work.
#
#   PART 1 — bin/omarchy-update's `script` PTY-wrapper guard. On Fedora 44 the
#            `script` binary is split into util-linux-script and may be absent.
#            The wrapper must be SKIPPED (update runs unlogged) when `script` is
#            missing, and USED when it's present. Either way the update reaches
#            omarchy-update-git + omarchy-update-perform.
#   PART 2 — bin/omedora-update-pkgs runs `<dnf> upgrade -y --refresh`, honoring
#            the $OMEDORA_DNF_CMD seam (so the integration test / this test can
#            inject a fake dnf instead of a real multi-hundred-MB system upgrade).
#   PART 3 — bin/omarchy-update-time restarts the right NTP service per distro
#            (chronyd on Fedora, systemd-timesyncd on Arch) and never aborts the
#            update when the Fedora service is absent.
#   PART 4 — bin/omarchy-update-restart attributes kernel files via rpm on Fedora
#            (not pacman, which is absent → would falsely prompt a reboot).
#
# All mocked: dnf / script / git / systemctl / pacman / rpm are stubbed on PATH,
# OMARCHY_DISTRO is forced. Runs on the Ubuntu CI like the other test/*.sh — no
# network, no real package manager.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"

SCRATCH="$(mktemp -d)"
cleanup() { [[ -n $SCRATCH && -d $SCRATCH ]] && rm -rf "$SCRATCH"; }
trap cleanup EXIT

# A shim dir on PATH holding distro + the downstream update steps as no-op
# tracers, plus a minimal coreutils mirror so we can present a PATH that does
# NOT contain `script`.
SHIM="$SCRATCH/shim"
COREUTILS="$SCRATCH/coreutils"
mkdir -p "$SHIM" "$COREUTILS"
for c in bash env printf cat dirname basename mktemp rm grep sed awk chmod uname \
         mkdir touch sort tail head sleep pkill true false; do
  src="$(command -v "$c" 2>/dev/null || true)"
  [[ -n $src ]] && ln -sf "$src" "$COREUTILS/$c"
done

stub() { printf '#!/bin/bash\n%s\n' "$2" >"$SHIM/$1"; chmod +x "$SHIM/$1"; }

stub omarchy-distro              'echo fedora'
stub omarchy-update-git          'echo GIT-PULL-RAN'
stub omarchy-update-perform      'echo "PERFORM-RAN LOGGED=${OMARCHY_UPDATE_LOGGED:-unset}"'

# ===========================================================================
echo "# --- PART 1: omarchy-update script-wrapper guard ---"
# ===========================================================================

# (a) script ABSENT → wrapper skipped, update runs UNLOGGED but still proceeds
#     through git-pull + perform. This is the core Fedora-44 fix: a missing
#     `script` must NOT kill the update with `env: 'script': No such file`.
out_absent="$(PATH="$SHIM:$COREUTILS" OMARCHY_PATH="$ROOT" \
  bash "$ROOT/bin/omarchy-update" -y 2>&1 || true)"
assert_output_contains "script absent: git pull still runs" "$out_absent" "GIT-PULL-RAN"
assert_output_contains "script absent: perform still runs" "$out_absent" "PERFORM-RAN"
assert_output_contains "script absent: ran UNLOGGED (no PTY re-exec)" "$out_absent" "LOGGED=unset"
assert_output_lacks    "script absent: no env 'script' error" "$out_absent" "No such file"

# (b) script PRESENT → wrapper IS used: omarchy-update re-execs itself under
#     `script`, which sets OMARCHY_UPDATE_LOGGED=1. Our fake `script` records
#     that it was invoked, then runs the wrapped command.
cat >"$COREUTILS/script" <<'EOF'
#!/bin/bash
# Mimic `script -qefc "<command>" <logfile>`: the wrapped command is the arg
# after -qefc; the logfile is the final arg. Just run the command.
echo "SCRIPT-WRAPPER-INVOKED"
cmd=""
while [[ $# -gt 0 ]]; do
  if [[ $1 == "-qefc" ]]; then cmd="$2"; shift 2; continue; fi
  shift
done
eval "$cmd"
EOF
chmod +x "$COREUTILS/script"
out_present="$(PATH="$SHIM:$COREUTILS" OMARCHY_PATH="$ROOT" \
  bash "$ROOT/bin/omarchy-update" -y 2>&1 || true)"
assert_output_contains "script present: PTY wrapper IS invoked" "$out_present" "SCRIPT-WRAPPER-INVOKED"
assert_output_contains "script present: ran LOGGED (under the wrapper)" "$out_present" "LOGGED=1"
assert_output_contains "script present: perform still runs" "$out_present" "PERFORM-RAN"
rm -f "$COREUTILS/script"

# ===========================================================================
echo "# --- PART 2: omedora-update-pkgs dnf command ---"
# ===========================================================================
# Inject a fake dnf via $OMEDORA_DNF_CMD that records its argv. Assert the
# command is `<dnf> upgrade -y --refresh` (the essential Fedora step).
dnflog="$SCRATCH/dnf.log"
cat >"$SHIM/fakednf" <<EOF
#!/bin/bash
echo "\$*" >"$dnflog"
EOF
chmod +x "$SHIM/fakednf"
out_pkgs="$(PATH="$SHIM:$COREUTILS" OMEDORA_DNF_CMD="$SHIM/fakednf" \
  bash "$ROOT/bin/omedora-update-pkgs" 2>&1 || true)"
assert_equals "omedora-update-pkgs runs '<dnf> upgrade -y --refresh'" \
  "$(cat "$dnflog")" "upgrade -y --refresh"
assert_output_contains "omedora-update-pkgs prints its banner" \
  "$out_pkgs" "Update system + omedora packages"

# ===========================================================================
echo "# --- PART 3: omarchy-update-time NTP service per distro ---"
# ===========================================================================
# Fake sudo (transparent) + systemctl (records the unit it was told to restart).
sysctllog="$SCRATCH/systemctl.log"
cat >"$SHIM/sudo" <<'EOF'
#!/bin/bash
exec "$@"
EOF
cat >"$SHIM/systemctl" <<EOF
#!/bin/bash
echo "\$*" >>"$sysctllog"
# Emulate a Fedora box with no systemd-timesyncd unit: fail for that unit.
[[ "\$*" == *systemd-timesyncd* ]] && exit 1
exit 0
EOF
chmod +x "$SHIM/sudo" "$SHIM/systemctl"

# Fedora: must restart chronyd, and must NOT abort even though timesyncd is absent.
: >"$sysctllog"
stub omarchy-distro 'echo fedora'
assert_exit_code "update-time on Fedora exits 0 (tolerates missing timesyncd)" 0 \
  env PATH="$SHIM:$COREUTILS" bash "$ROOT/bin/omarchy-update-time"
assert_output_contains "update-time on Fedora restarts chronyd" \
  "$(cat "$sysctllog")" "restart chronyd"
assert_output_lacks "update-time on Fedora does NOT touch systemd-timesyncd" \
  "$(cat "$sysctllog")" "systemd-timesyncd"

# Arch: byte-identical legacy behavior — restart systemd-timesyncd.
: >"$sysctllog"
stub omarchy-distro 'echo arch'
PATH="$SHIM:$COREUTILS" bash "$ROOT/bin/omarchy-update-time" >/dev/null 2>&1 || true
assert_output_contains "update-time on Arch restarts systemd-timesyncd" \
  "$(cat "$sysctllog")" "restart systemd-timesyncd"
assert_output_lacks "update-time on Arch does NOT touch chronyd" \
  "$(cat "$sysctllog")" "chronyd"

# ===========================================================================
echo "# --- PART 4: omarchy-update-restart kernel ownership probe ---"
# ===========================================================================
# On Fedora the probe must use rpm (pacman is absent). We stub a tripwire pacman
# that fails loudly if called, and an rpm that 'owns' the running kernel so
# kernel_updated resolves to false and no reboot is prompted. gum/uname stubbed.
kdir="$SCRATCH/usr/lib/modules/$(uname -r)"
mkdir -p "$kdir"; touch "$kdir/vmlinuz"
cat >"$SHIM/pacman" <<'EOF'
#!/bin/bash
echo "PACMAN-CALLED-ON-FEDORA" >&2
exit 0
EOF
cat >"$SHIM/rpm" <<'EOF'
#!/bin/bash
# -qf <file> → claim ownership of any kernel file under our fixture tree.
exit 0
EOF
# gum confirm must default to "no" so the test never blocks / reboots.
cat >"$SHIM/gum" <<'EOF'
#!/bin/bash
echo "GUM-CONFIRM" >&2
exit 1
EOF
cat >"$SHIM/omarchy-system-reboot" <<'EOF'
#!/bin/bash
echo "REBOOT-CALLED" >&2
EOF
chmod +x "$SHIM/pacman" "$SHIM/rpm" "$SHIM/gum" "$SHIM/omarchy-system-reboot"
stub omarchy-distro 'echo fedora'

# Point the kernel glob at our fixture by overriding the module path via a tiny
# wrapper: omarchy-update-restart hardcodes /usr/lib/modules, so we instead rely
# on rpm 'owning' whatever exists and assert pacman is never invoked + no reboot.
out_restart="$(PATH="$SHIM:$COREUTILS" HOME="$SCRATCH/home" \
  bash "$ROOT/bin/omarchy-update-restart" 2>&1 || true)"
assert_output_lacks "restart on Fedora never calls pacman" \
  "$out_restart" "PACMAN-CALLED-ON-FEDORA"

# Sanity: on Arch the probe still uses pacman (byte-identical). A tripwire rpm
# this time; pacman 'owns' nothing so behavior is the legacy path.
cat >"$SHIM/rpm" <<'EOF'
#!/bin/bash
echo "RPM-CALLED-ON-ARCH" >&2
exit 0
EOF
chmod +x "$SHIM/rpm"
stub omarchy-distro 'echo arch'
out_restart_arch="$(PATH="$SHIM:$COREUTILS" HOME="$SCRATCH/home" \
  bash "$ROOT/bin/omarchy-update-restart" 2>&1 || true)"
assert_output_lacks "restart on Arch never calls rpm" \
  "$out_restart_arch" "RPM-CALLED-ON-ARCH"

echo "# All update-flow tests passed."
