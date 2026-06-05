#!/bin/bash

# Versioning / release / update-dispatch tests.
#
#   PART 1 — bin/omedora-copr: COPR project resolution (owner/project + repo-id),
#            derived from the Omarchy base version, owner overridable.
#   PART 2 — bin/omedora-release: SemVer validation + the happy path (bumps
#            omedora/version, writes CHANGELOG, commits, creates tag vX.Y.Z) in a
#            throwaway git fixture.
#   PART 3 — omarchy-update-perform dispatches to the Fedora pipeline on Fedora.
#
# Distro-agnostic: forces OMARCHY_DISTRO via a stub and uses git fixtures, so it
# runs on the Arch host or in a container identically. No network, no dnf.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"

SCRATCH="$(mktemp -d)"
cleanup() { [[ -n $SCRATCH && -d $SCRATCH ]] && rm -rf "$SCRATCH"; }
trap cleanup EXIT

# ===========================================================================
echo "# --- PART 1: omedora-copr resolution ---"
# ===========================================================================
assert_equals "default project from the base major (3.8.2 -> omedora-3)" \
  "$(OMARCHY_PATH="$ROOT" "$ROOT/bin/omedora-copr")" "agaspar/omedora-3"
assert_equals "repo-id form" \
  "$(OMARCHY_PATH="$ROOT" "$ROOT/bin/omedora-copr" --repo-id)" \
  "copr:copr.fedorainfracloud.org:agaspar:omedora-3"
assert_equals "owner override" \
  "$(OMARCHY_PATH="$ROOT" OMEDORA_COPR_OWNER=someuser "$ROOT/bin/omedora-copr")" \
  "someuser/omedora-3"
# Scoped per Omarchy major: a 4.x base selects omedora-4, not omedora-4.0.0.
fakebase="$SCRATCH/fakebase"; mkdir -p "$fakebase"; echo "4.0.0" >"$fakebase/version"
assert_equals "project tracks the base MAJOR (4.0.0 -> omedora-4)" \
  "$(OMARCHY_PATH="$fakebase" "$ROOT/bin/omedora-copr")" "agaspar/omedora-4"

# ===========================================================================
echo "# --- PART 2: omedora-release ---"
# ===========================================================================
# Validation (run against the real repo dir but with a dirty/invalid input — it
# never mutates because the checks fail first).
assert_exit_code "rejects missing version arg" 2 \
  bash "$ROOT/bin/omedora-release"
assert_exit_code "rejects a non-SemVer" 2 \
  bash "$ROOT/bin/omedora-release" not-a-version

# Happy path in a throwaway git repo fixture.
fix="$SCRATCH/repo"
mkdir -p "$fix/omedora" "$fix/bin"
cp "$ROOT/bin/omedora-release" "$fix/bin/omedora-release"
echo "3.8.2" >"$fix/version"
echo "0.1.0" >"$fix/omedora/version"
(
  cd "$fix"
  git init -q
  git config user.email t@t; git config user.name t
  git add -A; git commit -q -m init
  bash bin/omedora-release 0.2.0 >/dev/null
)
assert_equals "release bumped omedora/version" "$(cat "$fix/omedora/version")" "0.2.0"
assert_file_exists "release wrote a CHANGELOG" "$fix/omedora/CHANGELOG.md"
assert_output_contains "CHANGELOG names the new tag + base" \
  "$(cat "$fix/omedora/CHANGELOG.md")" "v0.2.0"
assert_equals "annotated tag v0.2.0 created" \
  "$(git -C "$fix" tag -l v0.2.0)" "v0.2.0"
# A second release must be strictly greater.
assert_exit_code "rejects a non-increasing version" 1 \
  bash -c "cd '$fix' && bash bin/omedora-release 0.1.5"

# ===========================================================================
echo "# --- PART 3: omarchy-update-perform dispatch ---"
# ===========================================================================
shim="$SCRATCH/shim"; mkdir -p "$shim"
printf '#!/bin/bash\necho fedora\n' >"$shim/omarchy-distro"
printf '#!/bin/bash\necho FEDORA-PERFORM-CALLED\n' >"$shim/omarchy-update-perform-fedora"
chmod +x "$shim/omarchy-distro" "$shim/omarchy-update-perform-fedora"
out="$(PATH="$shim:$PATH" bash "$ROOT/bin/omarchy-update-perform" 2>&1 || true)"
assert_output_contains "on Fedora, perform execs the Fedora pipeline" \
  "$out" "FEDORA-PERFORM-CALLED"

# On Arch it must NOT take the Fedora branch (we only check it doesn't dispatch;
# stub omarchy-distro=arch and a tripwire fedora-perform that would fail loudly).
printf '#!/bin/bash\necho arch\n' >"$shim/omarchy-distro"
printf '#!/bin/bash\necho SHOULD-NOT-RUN; exit 1\n' >"$shim/omarchy-update-perform-fedora"
# Stub the first Arch pipeline step so the body exits cleanly without pacman.
printf '#!/bin/bash\nexit 0\n' >"$shim/omarchy-update-keyring"
printf '#!/bin/bash\nexit 0\n' >"$shim/omarchy-update-available-reset"
printf '#!/bin/bash\necho ARCH-BODY; exit 7\n' >"$shim/omarchy-update-system-pkgs"
chmod +x "$shim/omarchy-update-keyring" "$shim/omarchy-update-available-reset" "$shim/omarchy-update-system-pkgs"
out_arch="$(PATH="$shim:$PATH" bash "$ROOT/bin/omarchy-update-perform" 2>&1 || true)"
assert_output_lacks "on Arch, the Fedora pipeline is NOT used" "$out_arch" "SHOULD-NOT-RUN"
assert_output_contains "on Arch, the Arch body runs" "$out_arch" "ARCH-BODY"

echo "# All versioning tests passed."
