#!/usr/bin/env python3
"""Resolve the RPM set managed by Omedora's Fedora update transaction."""

from __future__ import annotations

import os
import subprocess
import tomllib
from pathlib import Path

from package_map import resolve_mapping


def resolve_tree_root() -> Path:
  script_root = Path(__file__).resolve().parent.parent.parent
  candidates = [script_root]
  if os.environ.get("OMARCHY_PATH"):
    candidates.append(Path(os.environ["OMARCHY_PATH"]))
  candidates.append(Path("/usr/share/omarchy"))
  for root in candidates:
    if (root / "install" / "packages" / "fedora.toml").is_file():
      return root
  return script_root


ROOT = resolve_tree_root()
MAP_PATH = Path(
  os.environ.get(
    "OMARCHY_FEDORA_MAP", ROOT / "install" / "packages" / "fedora.toml"
  )
)
BASE_PATH = Path(
  os.environ.get("OMARCHY_BASE_PKGS", ROOT / "install" / "omarchy-base.packages")
)
BASELINE_PATH = Path(
  os.environ.get(
    "OMEDORA_BASELINE_PKGS",
    ROOT / "omedora" / "install" / "fedora-baseline.packages",
  )
)


def read_packages(path: Path) -> list[str]:
  packages: list[str] = []
  for line in path.read_text().splitlines():
    package = line.split("#", 1)[0].strip()
    if package:
      packages.append(package)
  return packages


def rpm_names(package: str, package_map: dict[str, dict]) -> list[str]:
  entry, active = resolve_mapping(package, package_map)
  if not active:
    return []
  if entry is None:
    return [package]
  if entry.get("source") not in ("dnf", "copr"):
    return []
  return [str(name) for name in entry.get("names", [package])]


def is_installed(name: str) -> bool:
  return subprocess.run(
    ["rpm", "-q", name],
    stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL,
    check=False,
  ).returncode == 0


def main() -> int:
  with MAP_PATH.open("rb") as file:
    package_map = tomllib.load(file)

  base = read_packages(BASE_PATH) + read_packages(BASELINE_PATH)
  base_set = set(base)
  managed = ["omedora", "omedora-settings"]

  # Base targets are unconditional: `dnf install` both upgrades existing RPMs
  # and installs packages added to the base list since the previous release.
  for package in base:
    managed.extend(rpm_names(package, package_map))

  # Map entries outside the base set are optional. Keep them current only when
  # the user already has the mapped RPM installed.
  for package in sorted(package_map):
    if package in base_set:
      continue
    for name in rpm_names(package, package_map):
      if is_installed(name):
        managed.append(name)

  print(*dict.fromkeys(managed), sep="\n")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
