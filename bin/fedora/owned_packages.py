#!/usr/bin/env python3
"""
Resolve the set of Fedora package names omedora wants to *own* — i.e. the
desktop/compositor components it installs and pins.

Reads install/omarchy-base.packages (the Arch package list) and resolves each
through install/packages/fedora.toml. Emits, one per line, the Fedora package
names for entries whose source is dnf or copr (these become real RPMs on the
system). flathub / source / skip entries are not "owned RPMs" and are omitted.

For each such entry the emitted set includes BOTH the upstream/base name (the
map key, e.g. `hyprland`) AND omedora's mapped name(s) (e.g. `hyprland-omedora`).
The upstream name matters for conflict detection: a foreign Hyprland repo (e.g.
solopasha/hyprland) ships the compositor as plain `hyprland`, even though omedora
installs it renamed as `hyprland-omedora` — so we must inspect both. Including
the base name never causes a false positive, because omedora installs the mapped
name (so plain `hyprland` is only ever present from a foreign/manual source), and
a base name installed from a friendly repo is never flagged.

Used by bin/omarchy-doctor to decide which installed RPMs to inspect for
foreign-repo provenance.

Env:
  OMARCHY_FEDORA_MAP   Path to fedora.toml (default: derived from script).
  OMARCHY_BASE_PKGS    Path to omarchy-base.packages (default: derived).
"""

from __future__ import annotations

import os
import sys
import tomllib
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
DEFAULT_MAP = REPO_ROOT / "install" / "packages" / "fedora.toml"
DEFAULT_BASE = REPO_ROOT / "install" / "omarchy-base.packages"


def read_base_packages(path: Path) -> list[str]:
    pkgs: list[str] = []
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        pkgs.append(line)
    return pkgs


def load_map(path: Path) -> dict[str, dict]:
    with path.open("rb") as fp:
        return tomllib.load(fp)


def resolve_owned(base: list[str], pkg_map: dict[str, dict]) -> list[str]:
    owned: list[str] = []
    seen: set[str] = set()
    for pkg in base:
        raw = pkg_map.get(pkg)
        if raw is None:
            # Absent from the map -> resolves to the same name via dnf.
            source = "dnf"
            names = [pkg]
        else:
            source = str(raw.get("source", "dnf"))
            names = [str(n) for n in raw.get("names", [pkg])]
        if source not in ("dnf", "copr"):
            continue
        # Include the upstream/base name (the map key) alongside omedora's
        # possibly-renamed package(s), so conflict detection catches a foreign
        # `hyprland` even though omedora installs it as `hyprland-omedora`.
        for n in (pkg, *names):
            if n not in seen:
                seen.add(n)
                owned.append(n)
    return owned


def main(argv: list[str] | None = None) -> int:
    map_path = Path(os.environ.get("OMARCHY_FEDORA_MAP", DEFAULT_MAP))
    base_path = Path(os.environ.get("OMARCHY_BASE_PKGS", DEFAULT_BASE))

    if not base_path.is_file():
        print(f"owned_packages: base list not found at {base_path}", file=sys.stderr)
        return 1
    if not map_path.is_file():
        print(f"owned_packages: package map not found at {map_path}", file=sys.stderr)
        return 1

    base = read_base_packages(base_path)
    pkg_map = load_map(map_path)
    for name in resolve_owned(base, pkg_map):
        print(name)
    return 0


if __name__ == "__main__":
    sys.exit(main())
