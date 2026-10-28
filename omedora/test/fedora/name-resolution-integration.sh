#!/bin/bash
#
# L2: every package name Omarchy hands the Fedora package helpers resolves
# with real dnf, and every language Setup > Language offers has a langpack.
#
#   1. Names from install/omarchy-base.packages, the Fedora baseline, and the
#      literal `omarchy-pkg-add|install|aur-add <name>` calls in the commands,
#      menu and hardware scripts that run on Fedora. Each is resolved through
#      install/packages/fedora.toml the way pkg.py does (absent = the same
#      name through dnf); every dnf/copr target must be provided by an enabled
#      repository (Fedora, RPM Fusion, the Omedora COPR). A name absent from
#      the map that dnf cannot resolve fails `omarchy-pkg-add` at runtime, for
#      the unattended base set and the on-demand installers alike.
#   2. glibc-langpack-<lang> exists for every locale in
#      default/i18n/locales.json (bin/fedora/locale-generate installs it).
#   3. Setup > Language reaches omarchy-locale-generate through pkexec or sudo,
#      which drop OMARCHY_DISTRO. With the RPM's /usr/bin layout and a clean
#      environment, `omarchy-locale-generate ja` must still take the Fedora
#      branch and leave ja_JP.utf8 in `locale -a`.
#
# Runs as root inside omedora-test:fedora<N> (called from integration.sh, or
# directly: run-integration.sh --shell, then bash this file). Needs network.

set -uo pipefail

REPO=${REPO:-/repo}
. "$REPO/test/helpers.sh"
. "$REPO/omedora/test/fedora/lib/container.sh"
ensure_running_as_root

fedora_version=$(. /etc/os-release && echo "$VERSION_ID")
work=$(mktemp -d)
cleanup_paths=()
cleanup() {
  local path
  for path in "${cleanup_paths[@]}"; do
    rm -f "$path"
  done
  rm -rf "$work"
}
trap cleanup EXIT

echo "=== Repositories for name resolution (Fedora $fedora_version) ==="
for kind in free nonfree; do
  rpm -q "rpmfusion-$kind-release" >/dev/null 2>&1 ||
    dnf install -y -q \
      "https://mirrors.rpmfusion.org/$kind/fedora/rpmfusion-$kind-release-$fedora_version.noarch.rpm" \
      >/dev/null 2>&1 || true
done
copr=$(OMARCHY_PATH="$REPO" "$REPO/bin/omedora-copr")
dnf -y -q copr enable "$copr" >/dev/null 2>&1 || true
dnf -q makecache >/dev/null 2>&1 || true
pass "repositories prepared (RPM Fusion + $copr)"

echo "=== Package names resolve with real dnf ==="
# Literal installer arguments come only from code that runs on Fedora: the
# commands and menu (Fedora dispatches them through pkg.py) and the hardware
# scripts install/hardware/all-fedora.sh actually runs. Arch-only commands are
# listed with the reason they never reach dnf.
OMARCHY_FEDORA_VERSION=$fedora_version python3 - "$REPO" >"$work/targets" <<'PY'
import os
import re
import sys
import tomllib
from pathlib import Path

repo = Path(sys.argv[1])
version = int(os.environ["OMARCHY_FEDORA_VERSION"])
pkg_map = tomllib.loads((repo / "install/packages/fedora.toml").read_text())

# Commands whose package calls are Arch-only by construction on Fedora.
arch_only = {
  "omarchy-update-keyring",        # exits before pacman-key on Fedora
  "omarchy-toggle-hybrid-gpu",     # supergfxctl/asusctl are skipped in the map
  "omarchy-windows-vm",            # menu-gated; Fedora uses its own virt stack
}

def names_from_list(path):
  for line in path.read_text().splitlines():
    line = line.split("#", 1)[0].strip()
    if line:
      yield line, path.relative_to(repo).as_posix(), "base"

call = re.compile(r"omarchy-pkg-(?:add|install|aur-add)((?:[ \t]+[A-Za-z0-9][A-Za-z0-9@._+-]*)+)")
def names_from_code(path, kind="command"):
  text = path.read_text(errors="replace")
  for match in call.finditer(text):
    line_start = text.rfind("\n", 0, match.start()) + 1
    prefix = text[line_start:match.start()].lstrip()
    if prefix.startswith("#"):
      continue
    for word in match.group(1).split():
      yield word, path.relative_to(repo).as_posix(), kind

sources = []
sources += names_from_list(repo / "install/omarchy-base.packages")
sources += names_from_list(repo / "omedora/install/fedora-baseline.packages")
for path in sorted((repo / "bin").glob("omarchy-*")):
  if path.is_file() and path.name not in arch_only:
    sources += names_from_code(path)
sources += names_from_code(repo / "default/omarchy/omarchy-menu.jsonc")
hardware = (repo / "install/hardware/all-fedora.sh").read_text()
for script in re.findall(r'\$OMARCHY_INSTALL/(hardware/[^"\s]+\.sh)', hardware):
  sources += names_from_code(repo / "install" / script, "base")

seen = set()
for name, origin, kind in sources:
  if name in seen:
    continue
  seen.add(name)
  entry = pkg_map.get(name)
  if entry is not None:
    since, until = entry.get("since"), entry.get("until")
    if (since is not None and version < int(since)) or (until is not None and version >= int(until)):
      print(f"{name}\tinactive\t-\t{origin}\t{kind}")
      continue
  source = "dnf" if entry is None else entry.get("source", "dnf")
  mapped = "unmapped" if entry is None else "mapped"
  if source in ("dnf", "copr"):
    if source == "copr":
      print(f"{name}\tcopr:{entry.get('copr', '')}\t-\t{origin}\t{kind}")
      continue
    for target in (entry or {}).get("names", [name]):
      print(f"{name}\t{mapped}\t{target}\t{origin}\t{kind}")
  else:
    print(f"{name}\t{source}\t-\t{origin}\t{kind}")
PY
(( $(wc -l <"$work/targets") > 100 )) \
  && pass "collected $(wc -l <"$work/targets") package-name rows" \
  || { cat "$work/targets" >&2; fail "collected the package names Omarchy passes"; }

mapfile -t dnf_targets < <(awk -F'\t' '$3 != "-" {print $3}' "$work/targets" | sort -u)
dnf repoquery --available --qf '%{name}\n' "${dnf_targets[@]}" 2>/dev/null | sort -u >"$work/by-name"
: >"$work/unresolved"
for target in "${dnf_targets[@]}"; do
  grep -qxF "$target" "$work/by-name" && continue
  # dnf install also accepts a provide (e.g. a virtual name).
  [[ -n $(dnf repoquery --available --whatprovides "$target" -q 2>/dev/null) ]] && continue
  awk -F'\t' -v t="$target" '$3 == t' "$work/targets" >>"$work/unresolved"
done
report_unresolved() {
  awk -F'\t' -v k="$1" '$5 == k {printf "  %s (%s, from %s)\n", $3, $2, $4}' "$work/unresolved" | sort -u
}

# The base set, the Fedora baseline and the hardware scripts Fedora runs are
# installed unattended: every name must resolve.
base_unresolved=$(report_unresolved base)
base_count=$(awk -F'\t' '$5 == "base" && $3 != "-"' "$work/targets" | wc -l)
if [[ -z $base_unresolved ]]; then
  pass "all $base_count base/baseline/hardware dnf targets resolve from enabled repositories"
else
  printf '%s\n' "$base_unresolved" >&2
  fail "base/baseline/hardware dnf targets resolve from no enabled repository"
fi

# Optional installers (Install menu, AI, services, editors, gaming) run on
# demand, but an unmapped name dnf cannot resolve still fails the command at
# runtime, so every one must resolve too. A package Fedora cannot provide is
# mapped to skip and its command gated (as for sunshine), which takes it out of
# this list.
command_unresolved=$(report_unresolved command)
command_count=$(awk -F'\t' '$5 == "command" && $3 != "-"' "$work/targets" | wc -l)
if [[ -z $command_unresolved ]]; then
  pass "all $command_count installer dnf targets resolve from enabled repositories"
else
  printf '%s\n' "$command_unresolved" >&2
  fail "installer dnf targets resolve from no enabled repository (map them, or skip and gate the command)"
fi

echo "=== glibc langpacks for the language registry ==="
mapfile -t langs < <(jq -r '.[].locale' "$REPO/default/i18n/locales.json" | sed -nE 's/^([a-z]{2,3})_[A-Z]{2}\.UTF-8$/\1/p' | sort -u)
(( ${#langs[@]} > 10 )) || fail "the locale registry lists languages"
langpacks=("${langs[@]/#/glibc-langpack-}")
dnf repoquery --available --qf '%{name}\n' "${langpacks[@]}" 2>/dev/null | sort -u >"$work/langpacks"
missing=()
for package in "${langpacks[@]}"; do
  grep -qxF "$package" "$work/langpacks" || missing+=("$package")
done
(( ${#missing[@]} == 0 )) \
  && pass "glibc-langpack exists for all ${#langpacks[@]} registry languages" \
  || fail "no glibc langpack for: ${missing[*]}"

echo "=== omarchy-locale-generate under a pkexec-style clean environment ==="
# Mirror the omedora RPM: bin/ is copied into /usr/bin (with bin/fedora/ beside
# it) and the registry lives under /usr/share/omarchy. Only add what is absent,
# and remove exactly what was added.
link() {
  [[ -e $2 || -L $2 ]] && return 0
  ln -s "$1" "$2"
  cleanup_paths+=("$2")
}
link "$REPO/bin/omarchy-locale-generate" /usr/bin/omarchy-locale-generate
link "$REPO/bin/omarchy-distro" /usr/bin/omarchy-distro
link "$REPO/bin/fedora" /usr/bin/fedora
link "$REPO" /usr/share/omarchy

dnf remove -y -q glibc-langpack-ja >/dev/null 2>&1 || true
if locale -a 2>/dev/null | grep -qix 'ja_JP.utf8'; then
  echo "  (glibc-all-langpacks provides ja_JP already; the install step is not exercised)"
fi
if env -i PATH=/usr/bin /usr/bin/omarchy-locale-generate ja >"$work/locale.out" 2>&1; then
  pass "omarchy-locale-generate ja succeeds without OMARCHY_DISTRO"
else
  cat "$work/locale.out" >&2
  fail "omarchy-locale-generate ja succeeds without OMARCHY_DISTRO"
fi
locale -a 2>/dev/null | grep -qix 'ja_JP.utf8' \
  && pass "ja_JP.utf8 is available after generation" \
  || fail "ja_JP.utf8 is available after generation"
