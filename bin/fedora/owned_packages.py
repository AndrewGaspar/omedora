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
DEFAULT_SPEC_DIR = REPO_ROOT / "omedora" / "packaging" / "copr"


def read_spec_names(path: Path) -> set[str] | None:
    """Names of the packages omedora's COPR actually builds (spec filenames).

    "Owned" should mean PINNED — provided by omedora's own COPR — not merely
    "installed via dnf": a base package like libyaml is plain Fedora, and
    flagging it as foreign (e.g. a container image's synthetic repo id) is a
    false positive. When the spec dir isn't available (an installed system
    without the packaging tree), return None and the caller skips the filter —
    the doctor's friendly-repo check alone is sufficient there.
    """
    if not path.is_dir():
        return None
    names = {p.stem for p in path.glob("*.spec")}
    return names or None


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


def resolve_owned(
    base: list[str], pkg_map: dict[str, dict], spec_names: set[str] | None = None
) -> list[str]:
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
        # Owned means PINNED by omedora's COPR: when the spec set is known,
        # only entries that resolve to (or collide with) one of our own
        # packages count. Plain Fedora packages (libyaml, jq, ...) are not
        # ours to police — the doctor would false-positive on them wherever
        # repo provenance is unusual (container images, local mirrors).
        if spec_names is not None and not ({pkg, *names} & spec_names):
            continue
        # Include the upstream/base name (the map key) alongside omedora's
        # possibly-renamed package(s), so conflict detection catches a foreign
        # `hyprland` even though omedora installs it as `hyprland-omedora`.
        for n in (pkg, *names):
            if n not in seen:
                seen.add(n)
                owned.append(n)
    return owned


def resolve_map(base: list[str], pkg_map: dict[str, dict]) -> list[tuple[str, list[str]]]:
    """Base/upstream name -> omedora's install target name(s).

    Emitted as `<base>\t<comma-joined targets>` per dnf/copr entry. The
    replacement engine uses this to decide the mechanism for a detected
    foreign-repo package: if the targets are just [base] (same name), it
    distro-syncs that name from the omedora repo; if the targets differ
    (e.g. hyprland -> hyprland-omedora), it `dnf swap`s base for the targets.
    """
    out: list[tuple[str, list[str]]] = []
    seen: set[str] = set()
    for pkg in base:
        raw = pkg_map.get(pkg)
        if raw is None:
            source, names = "dnf", [pkg]
        else:
            source = str(raw.get("source", "dnf"))
            names = [str(n) for n in raw.get("names", [pkg])]
        if source not in ("dnf", "copr"):
            continue
        if pkg in seen:
            continue
        seen.add(pkg)
        out.append((pkg, names))
    return out


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

    argv = sys.argv[1:] if argv is None else argv
    if "--map" in argv:
        for pkg, names in resolve_map(base, pkg_map):
            print(f"{pkg}\t{','.join(names)}")
        return 0

    spec_dir = Path(os.environ.get("OMEDORA_SPEC_DIR", DEFAULT_SPEC_DIR))
    for name in resolve_owned(base, pkg_map, read_spec_names(spec_dir)):
        print(name)
    return 0


if __name__ == "__main__":
    sys.exit(main())
