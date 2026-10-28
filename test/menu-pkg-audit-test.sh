#!/bin/bash
#
# L1 audit: every package the menu checks or installs resolves on Fedora.
#
# Upstream's menu names Arch/AUR packages in two places: `when:` / `disabled:`
# / `checked:` guards (omarchy-pkg-present / -missing) and the actions of the
# Install and Setup > Defaults rows, including the omarchy-install-* scripts
# they run. On Fedora each name goes through install/packages/fedora.toml, and
# an unmapped name goes to dnf unchanged. Every name found must be one of:
#
#   - mapped in fedora.toml (dnf / copr / flathub / skip);
#   - in SAME_ON_FEDORA below: reviewed names that resolve unchanged on
#     Fedora 44 + RPM Fusion (`dnf repoquery`, rechecked by
#     OMEDORA_AUDIT_REPOQUERY=1 where dnf exists);
#   - reached only from a row with a Fedora `when` gate (omarchy-distro).
#
# A skip-mapped package an ungated row INSTALLS is an error (the row would
# report success and install nothing) unless PARTIAL_SKIPS says the row still
# works without it. A skip-mapped package in a remove.* `when` is an error
# unless pkg.py reports it absent with every RPM and Flatpak installed, i.e.
# the Remove row can never show for it.
#
# This is the gate a rebase trips when upstream adds an AUR-only app.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"

# node parses the menu through MenuModel.js. It is not an Omarchy base package,
# so an installed system (the L3 smoke reruns this suite there) may lack it:
# skip there, but never in CI, where it is preinstalled.
if ! command -v node >/dev/null; then
  [[ -z ${CI:-} ]] || fail "node is required to parse the menu"
  echo "ok - # SKIP node is not installed; parsing the menu needs it"
  exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

ROOT="$ROOT" node -e '
  const fs = require("fs"), path = require("path")
  const menu = require(path.join(process.env.ROOT, "shell/plugins/menu/MenuModel.js"))
  const items = menu.parseMenuJsonc(fs.readFileSync(path.join(process.env.ROOT, "default/omarchy/omarchy-menu.jsonc"), "utf8"))
  process.stdout.write(JSON.stringify(items.map(({ id, when, disabled, checked, action }) => ({ id, when, disabled, checked, action }))))
' >"$TMP/rows.json"

# Skip-mapped names in remove.* guards, checked against the real pkg.py below.
python3 - "$ROOT" "$TMP/rows.json" "$TMP/remove-skips" <<'PY'
import json
import os
import re
import shlex
import subprocess
import sys
import tomllib
from pathlib import Path

root = Path(sys.argv[1])
rows = json.loads(Path(sys.argv[2]).read_text())
package_map = tomllib.loads((root / "install/packages/fedora.toml").read_text())

# Reviewed: these names resolve unchanged on Fedora 44 (main/updates) or RPM
# Fusion (steam, dropbox: nonfree), verified with `dnf repoquery` 2026-10-27.
SAME_ON_FEDORA = {
  "alacritty", "chromium", "clang", "dropbox", "firefox", "flatpak", "foot",
  "fprintd", "freerdp", "fuse3", "gum", "helix", "kitty", "libyaml", "lutris",
  "neovim", "ollama", "pam-u2f", "php", "rlwrap", "steam", "tailscale",
  "wine-mono", "winetricks", "wtype",
  # omarchy-install-gaming-retroarch's Fedora arm installs Fedora's own names.
  "retroarch", "retroarch-assets", "retroarch-database", "retroarch-filters",
  "libretro-beetle-ngp", "libretro-beetle-pce-fast", "libretro-beetle-vb",
  "libretro-beetle-wswan", "libretro-bsnes-mercury", "libretro-desmume2015",
  "libretro-gambatte", "libretro-gw", "libretro-handy", "libretro-mgba",
  "libretro-nestopia", "libretro-pcsx-rearmed", "libretro-prosystem",
  "libretro-stella2014",
}

# Ungated rows that install a skip-mapped package next to the ones that matter.
PARTIAL_SKIPS = {
  ("install.preinstalls", "aether"): "bulk reinstall of the removable preinstalls; the rest install",
  ("install.preinstalls", "cliamp"): "bulk reinstall of the removable preinstalls; the rest install",
  ("install.service.bitwarden", "bitwarden-cli"): "the Bitwarden desktop app installs from Flathub",
  ("install.gaming.lutris", "umu-launcher"): "Lutris runs without umu-launcher",
  ("install.gaming.steam", "lib32-nvidia-utils"): "NVIDIA lib32 userspace comes with the user's driver",
  ("install.gaming.steam", "lib32-nvidia-580xx-utils"): "NVIDIA lib32 userspace comes with the user's driver",
  ("install.gaming.lutris", "lib32-nvidia-utils"): "NVIDIA lib32 userspace comes with the user's driver",
  ("install.gaming.lutris", "lib32-nvidia-580xx-utils"): "NVIDIA lib32 userspace comes with the user's driver",
  ("install.gaming.heroic", "lib32-nvidia-utils"): "NVIDIA lib32 userspace comes with the user's driver",
  ("install.gaming.heroic", "lib32-nvidia-580xx-utils"): "NVIDIA lib32 userspace comes with the user's driver",
}

# Installers that take their packages from the action rather than from a
# literal in their own body: <command> <display-name> <packages> ...
PACKAGE_ARG_COMMANDS = {"omarchy-install-app": 1, "omarchy-install-and-launch": 1, "omarchy-install-font": 1}

NAME = r"[A-Za-z0-9@_][A-Za-z0-9@._+-]*"
GUARD = re.compile(rf"omarchy-pkg-(?:present|missing)((?:[ \t]+{NAME})+)")
ADD = re.compile(r"omarchy-pkg-(?:add|aur-add)((?:[ \t]+(?:\\\n[ \t]*)?[^\s;&|)]+)+)")
# A call with a literal (or no) argument; one passing a variable dispatches on
# the caller's argument and is followed below instead.
CALL = re.compile(r"\b(omarchy-install-[a-z0-9-]+)\b(?![ \t]+\"?\$)(?!-?\$)")

errors = []

def strip_comments(text):
  # Comments and usage text name commands without running them.
  return "\n".join(line for line in text.split("\n")
                   if not line.lstrip().startswith(("#", "echo ", "printf ")))

def fedora_arm(text):
  # A top-of-file `case "${OMARCHY_DISTRO:-$(omarchy-distro ...)}" in fedora)`
  # arm that exits: Fedora only ever runs that arm.
  m = re.search(r'case "\$\{OMARCHY_DISTRO:-\$\(omarchy-distro[^\n]*\n\s*fedora\)(.*?)\n\s*;;', text, re.S)
  if m and re.search(r"^\s*(exit|exec)\b", m.group(1), re.M):
    return m.group(1)
  return None

def case_arms(text, word):
  # Every `word)` / `word | alias)` arm, to its `;;`.
  arms = re.findall(rf"^[ \t]*(?:[\w.-]+[ \t]*\|[ \t]*)*{re.escape(word)}(?:[ \t]*\|[ \t]*[\w.-]+)*\)(.*?);;", text, re.S | re.M)
  return "\n".join(arms)

def array_values(text, var):
  values = []
  for m in re.finditer(rf"\b{var}\+?=\(([^)]*)\)", text):
    values += m.group(1).split()
  # Associative tables feeding the array: [Key]=value lines.
  values += re.findall(rf"^\s*\[[^\]]+\]=({NAME})\s*$", text, re.M)
  return [v.strip('"') for v in values if "$" not in v]

def scan_command(command, arg, via, found, seen):
  key = (command, arg)
  if key in seen:
    return
  seen.add(key)
  path = root / "bin" / command
  if not path.is_file():
    return
  text = strip_comments(path.read_text())
  arm = fedora_arm(text)
  if arm is not None:
    text = arm
  elif arg is not None:
    arms = case_arms(text, arg)
    if arms:
      # The arm that handles this argument, plus the code outside any case.
      text = arms + "\n" + re.sub(r"\bcase\b.*?\besac\b", "", text, flags=re.S)
  positional = {v for v in re.findall(r'^\s*(\w+)="?\$1"?\s*$', text, re.M)}
  for m in ADD.finditer(text):
    for token in m.group(1).replace("\\\n", " ").split():
      token = token.strip('"')
      var = re.fullmatch(r"\$\{?(\w+)(?:\[@\])?\}?", token)
      if var:
        name = var.group(1)
        if name in positional or name == "1":
          if arg is None:
            errors.append(f"{via}: {command} installs ${name} but the action gives no argument")
          else:
            found.setdefault(arg, set()).add(f"{via} > {command}")
        else:
          values = array_values(text, name)
          if not values:
            errors.append(f"{via}: cannot resolve `{token}` in {command}; teach this audit how")
          for v in values:
            found.setdefault(v, set()).add(f"{via} > {command}")
        continue
      if token.startswith("-") or "$" in token:
        continue
      found.setdefault(token, set()).add(f"{via} > {command}")
  for call in set(CALL.findall(text)) - {command}:
    scan_command(call, None, via, found, seen)
  # `omarchy-install-<kind> "$var"` / `omarchy-install-dictation-$backend`
  # dispatch on the argument this command was given.
  if arg is not None:
    for m in re.finditer(r'\b(omarchy-install-[a-z0-9-]+?)-?\$\{?\w+\}?|\b(omarchy-install-[a-z0-9-]+) "?\$\w+"?', text):
      if m.group(1):
        scan_command(f"{m.group(1)}-{arg}", None, via, found, seen)
      else:
        scan_command(m.group(2), arg, via, found, seen)
  else:
    # No argument to dispatch on: follow such a call through its whole body.
    for m in re.finditer(r'\b(omarchy-install-[a-z0-9-]+) "?\$\w+"?', text):
      scan_command(m.group(1), None, via, found, seen)

def action_words(action):
  words = []
  for word in shlex.split(action.replace(";", " ; ")):
    # A quoted command handed to a launcher runs as its own words.
    words += shlex.split(word) if word.startswith("omarchy-") and " " in word else [word]
  return words

def gated(row):
  return "omarchy-distro" in (row.get("when") or "") and "fedora" in (row.get("when") or "")

uses = {}          # name -> set of "row (kind)"
installs = {}      # (row id, name) -> via
for row in rows:
  rid = row["id"]
  if gated(row):
    continue
  for key in ("when", "disabled", "checked"):
    for m in GUARD.finditer(row.get(key) or ""):
      for name in m.group(1).split():
        uses.setdefault(name, set()).add(f"{rid} ({key})")
  action = row.get("action") or ""
  if not action or not re.match(r"(install|setup\.default)\.", rid):
    continue
  words = action_words(action)
  assigned = {}
  for word in words:
    m = re.fullmatch(rf"(\w+)=({NAME})", word)
    if m:
      assigned.setdefault(m.group(1), []).append(m.group(2))
  found, seen = {}, set()
  for i, word in enumerate(words):
    if not word.startswith("omarchy-"):
      continue
    if word in PACKAGE_ARG_COMMANDS:
      packages = words[i + 1 + PACKAGE_ARG_COMMANDS[word]] if len(words) > i + 1 + PACKAGE_ARG_COMMANDS[word] else ""
      for name in packages.split():
        var = re.fullmatch(r"\$\{?(\w+)\}?", name)
        for resolved in (assigned.get(var.group(1), []) if var else [name]):
          found.setdefault(resolved, set()).add(rid)
        if var and not assigned.get(var.group(1)):
          errors.append(f"{rid}: cannot resolve `{name}`; teach this audit how")
      continue
    arg = words[i + 1] if i + 1 < len(words) and re.fullmatch(NAME, words[i + 1]) else None
    if word.startswith("omarchy-default-dictation") and arg:
      scan_command(f"omarchy-install-dictation-{arg}", None, rid, found, seen)
    scan_command(word, arg, rid, found, seen)
  for name, via in found.items():
    uses.setdefault(name, set()).add(f"{rid} (installs)")
    installs[(rid, name)] = sorted(via)[0]

remove_skips = set()
for name, where in sorted(uses.items()):
  entry = package_map.get(name)
  if entry is None:
    if name not in SAME_ON_FEDORA:
      errors.append(f"{name}: unmapped and not a reviewed same-name package; used by {sorted(where)}")
    continue
  if name in SAME_ON_FEDORA:
    errors.append(f"{name}: in SAME_ON_FEDORA but also mapped in fedora.toml; drop it from the allowlist")
  if entry.get("source") != "skip":
    continue
  for use in sorted(where):
    rid, kind = use.rsplit(" (", 1)
    if kind == "installs)" and (rid, name) not in PARTIAL_SKIPS:
      errors.append(f"{name}: skip-mapped, but ungated {rid} installs it ({installs[(rid, name)]}); gate the row on Fedora or map the package")
    if kind == "when)" and rid.startswith("remove."):
      remove_skips.add(name)

for name in sorted(SAME_ON_FEDORA - set(uses)):
  errors.append(f"{name}: SAME_ON_FEDORA entry no longer used by any ungated menu row; drop it")
for (rid, name) in sorted(PARTIAL_SKIPS):
  if (rid, name) not in installs or package_map.get(name, {}).get("source") != "skip":
    errors.append(f"PARTIAL_SKIPS ({rid}, {name}) is stale; drop it")

# Opt-in: recheck the allowlist against the live repos (Fedora + RPM Fusion).
if os.environ.get("OMEDORA_AUDIT_REPOQUERY") and subprocess.run(["sh", "-c", "command -v dnf"], capture_output=True).returncode == 0:
  for name in sorted(SAME_ON_FEDORA):
    out = subprocess.run(["dnf", "repoquery", "-q", "--qf", "%{name}\n", name], capture_output=True, text=True).stdout.split()
    if name not in out:
      errors.append(f"{name}: SAME_ON_FEDORA, but `dnf repoquery {name}` finds no package by that name")

Path(sys.argv[3]).write_text("\n".join(sorted(remove_skips)) + "\n")
if errors:
  for line in errors:
    print(f"# {line}", file=sys.stderr)
  print(f"not ok - menu packages resolve on Fedora ({len(errors)} problem(s))", file=sys.stderr)
  sys.exit(1)
print(f"ok - menu packages resolve on Fedora ({len(uses)} names: mapped, reviewed same-name, or behind a Fedora gate)")
PY

# A skip-mapped package in a remove.* `when` must read as absent even when
# every RPM and Flatpak answers installed, or its Remove row would show.
while IFS= read -r name; do
  [[ -n $name ]] || continue
  status=0
  OMARCHY_DISTRO=fedora OMEDORA_FEDORA_VERSION=44 MOCK_LOG=/dev/null MOCK_RPM_INSTALLED="*" MOCK_FLATPAK_INSTALLED="" \
    PATH="$ROOT/test/mocks:$ROOT/bin:$PATH" "$ROOT/bin/omarchy-pkg-present" "$name" >/dev/null 2>&1 || status=$?
  ((status != 0)) || fail "skip-mapped $name in a remove.* when reads as installed on Fedora"
done <"$TMP/remove-skips"
pass "skip-mapped packages in remove.* guards never read as installed ($(grep -c . "$TMP/remove-skips") checked)"
