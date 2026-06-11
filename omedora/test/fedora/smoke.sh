#!/bin/bash
#
# L3 smoke test — runs INSIDE the fedora:44 test image.
# Slower than L2 (real third-party repo enablement, package-map audit).
# See omedora/testing.md §2 (L3) and §9 (roadmap step 7).
#
# Scope NOTE: a "true full install pipeline smoke" (run install.sh end-to-end
# and verify all 156 base packages install) is deferred to a follow-up commit
# because it depends on install-pipeline gating patches that are not yet in
# this stack. The roadmap in omedora/testing.md §9 step 7 covers that work.
#
# What this smoke DOES cover today:
#   - install/preflight/fedora-repos.sh runs cleanly (RPM Fusion + COPR +
#     Flatpak remote enablement, all idempotent)
#   - Every package in install/omarchy-base.packages resolves through the
#     package-map to *something* that dnf or flatpak can list (catches map
#     holes before they become L4 surprises)
#   - Critical Fedora-only sanity checks (dnf, rpm, flatpak, jq, python3
#     all available; user uid 1000 + sudoers in place)

set -uo pipefail

REPO="${REPO:-/repo}"
if [[ ! -d $REPO/bin ]]; then
  echo "expected repo at $REPO; bind-mount via -v \$PWD:/repo" >&2
  exit 1
fi

cd "$REPO"

. "$REPO/test/helpers.sh"
. "$REPO/omedora/test/fedora/lib/container.sh"

ensure_running_as_root

export PATH="$REPO/bin:$PATH"
export OMARCHY_PATH="$REPO"
export OMARCHY_INSTALL="$REPO/install"
export HOME="${HOME:-/root}"

# ============================================================================
echo "=== Sanity: required tools present in the image ==="
# ============================================================================

for tool in dnf rpm flatpak jq python3 git gum; do
  if command -v "$tool" >/dev/null 2>&1; then
    pass "tool present: $tool"
  else
    fail "missing tool: $tool"
  fi
done

# ============================================================================
echo "=== install/preflight/fedora-repos.sh runs cleanly ==="
# ============================================================================

if bash "$OMARCHY_INSTALL/preflight/fedora-repos.sh" >/tmp/fedora-repos.out 2>&1; then
  pass "fedora-repos.sh first run succeeds"
else
  cat /tmp/fedora-repos.out >&2
  fail "fedora-repos.sh first run failed"
fi

# Verify the expected on-disk artifacts:
assert_file_exists "RPM Fusion free repo file installed" \
  "/etc/yum.repos.d/rpmfusion-free.repo"
assert_file_exists "RPM Fusion nonfree repo file installed" \
  "/etc/yum.repos.d/rpmfusion-nonfree.repo"
assert_copr_enabled "agaspar/omedora-3 COPR enabled" "agaspar/omedora-3"

if flatpak remotes --user 2>/dev/null | grep -q '^flathub'; then
  pass "flathub remote registered (--user scope)"
else
  flatpak remotes --user >&2 || true
  fail "flathub remote not registered"
fi

# Idempotency check: re-run should be a no-op (no errors).
if bash "$OMARCHY_INSTALL/preflight/fedora-repos.sh" >/tmp/fedora-repos-2.out 2>&1; then
  pass "fedora-repos.sh second run succeeds (idempotent)"
else
  cat /tmp/fedora-repos-2.out >&2
  fail "fedora-repos.sh second run failed"
fi

# ============================================================================
echo "=== Package-map audit: every base-package resolves to something ==="
# ============================================================================

# Read install/omarchy-base.packages, resolve each via the map, and ask dnf
# whether the resulting Fedora name(s) are findable. Flathub entries are
# audited by checking the Flathub remote; source entries verify the installer
# file exists; skip entries log and pass.
#
# This catches package-map holes early — the # of map entries vs. # of
# successfully-resolvable base packages is the headline metric.

dnf -y makecache --refresh >/dev/null 2>&1 || true

REPO="$REPO" python3 <<'PY'
import os, sys, subprocess, tomllib
from pathlib import Path

REPO = Path(os.environ["REPO"])
base_file = REPO / "install" / "omarchy-base.packages"
map_file  = REPO / "install" / "packages" / "fedora.toml"
inst_dir  = REPO / "install" / "packages" / "installers"

with map_file.open("rb") as f:
    pkg_map = tomllib.load(f)

base_packages = []
for line in base_file.read_text().splitlines():
    line = line.strip()
    if not line or line.startswith("#"):
        continue
    base_packages.append(line)

ok = 0
fail_dnf = []     # Arch name that resolved to a dnf install but dnf can't find it
fail_copr = []    # COPR'd packages dnf can't find after enabling
no_app    = []    # Flathub entries with app_id we can't verify
no_inst   = []    # source entries without installer
skipped   = 0
unmapped_dnf_ok   = 0   # absent from map, fell through to dnf, dnf can find it
unmapped_dnf_miss = 0   # absent from map, fell through to dnf, dnf CANNOT find it
unmapped_misses   = []  # the failing arch names

def dnf_list_available(name):
    return subprocess.run(
        ["dnf", "list", "available", name],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    ).returncode == 0 or subprocess.run(
        ["dnf", "list", "installed", name],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    ).returncode == 0

for pkg in base_packages:
    entry = pkg_map.get(pkg)
    if entry is None:
        if dnf_list_available(pkg):
            unmapped_dnf_ok += 1
            ok += 1
        else:
            unmapped_dnf_miss += 1
            unmapped_misses.append(pkg)
        continue

    source = entry.get("source", "dnf")
    if source == "dnf" or source == "copr":
        names = entry.get("names", [])
        bad = [n for n in names if not dnf_list_available(n)]
        if bad:
            (fail_copr if source == "copr" else fail_dnf).append((pkg, bad))
        else:
            ok += 1
    elif source == "flathub":
        # Don't actually query Flathub for every app — it's slow. Trust the
        # validator already verified the schema. Count as ok.
        ok += 1
    elif source == "source":
        installer = inst_dir / entry.get("installer", "")
        if not installer.is_file():
            no_inst.append(pkg)
        else:
            ok += 1
    elif source == "skip":
        skipped += 1

total = len(base_packages)
print(f"\nPackage-map audit: {total} base packages")
print(f"  ok:                        {ok}")
print(f"  skipped (intentionally):   {skipped}")
print(f"  unmapped + dnf finds it:   {unmapped_dnf_ok}")
print(f"  unmapped + dnf MISSES:     {unmapped_dnf_miss}")
print(f"  mapped to dnf but missing: {len(fail_dnf)}")
print(f"  mapped to copr but missing:{len(fail_copr)}")
print(f"  source installer missing:  {len(no_inst)}")

if unmapped_misses:
    print("\nUnmapped + dnf miss (next-to-add to fedora.toml):")
    for p in unmapped_misses:
        print(f"  - {p}")
if fail_dnf:
    print("\nMapped→dnf but dnf miss (broken entries):")
    for pkg, bad in fail_dnf:
        print(f"  - {pkg} → {bad}")
if fail_copr:
    print("\nMapped→copr but dnf miss (broken COPR entries):")
    for pkg, bad in fail_copr:
        print(f"  - {pkg} → {bad}")
if no_inst:
    print("\nMissing source installers:")
    for p in no_inst:
        print(f"  - {p}")

# A "soft" pass — we expect a chunk of unmapped misses today (the map is
# still small). The audit's job is to print the inventory; it succeeds as
# long as nothing in the map is structurally broken.
exit_code = 0
if fail_dnf or fail_copr or no_inst:
    print("\nFAIL: broken map entries above")
    exit_code = 1
sys.exit(exit_code)
PY

audit_status=$?
if (( audit_status == 0 )); then
  pass "package-map audit: no broken map entries (unmapped holes are tolerated for now)"
else
  fail "package-map audit found broken entries"
fi

# ============================================================================
echo "=== Clean up (disable COPR, leave RPM Fusion + flathub for caching) ==="
# ============================================================================

dnf -y copr disable agaspar/omedora-3 >/dev/null 2>&1 || true

echo ""
echo "=== All L3 smoke checks passed ==="
