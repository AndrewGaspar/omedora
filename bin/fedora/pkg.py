#!/usr/bin/env python3
"""
Fedora-side package helper for omedora.

Invoked by the bin/omarchy-pkg-* shell wrappers when omarchy-distro is fedora.
Handles map resolution (install/packages/fedora.toml) and dispatches to dnf,
rpm, or flatpak. Source-installed packages run their installer script from
install/packages/installers/.

Subcommands:
  add <pkg> [<pkg>...]      Install if missing
  missing <pkg> [<pkg>...]  Exit 0 if ANY package is missing, 1 if all present
  present <pkg> [<pkg>...]  Exit 0 if ALL packages present, 1 if any missing
  drop <pkg> [<pkg>...]     Remove if installed (best-effort per source)
  aur-add <pkg> [<pkg>...]  Tier-fallback install (alias for `add` on Fedora)

Env vars:
  OMARCHY_FEDORA_MAP         Path to fedora.toml (default: derived from script)
  OMARCHY_FEDORA_INSTALLERS  Path to installer scripts (default: derived)
  OMARCHY_PKG_DRY_RUN        If set, log commands instead of executing
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import tomllib
from collections.abc import Iterable
from dataclasses import dataclass, field
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
DEFAULT_MAP = REPO_ROOT / "install" / "packages" / "fedora.toml"
DEFAULT_INSTALLERS = REPO_ROOT / "install" / "packages" / "installers"


@dataclass
class Entry:
    package: str
    source: str = "dnf"            # default when entry absent
    names: list[str] = field(default_factory=list)
    copr: str = ""
    app_id: str = ""
    installer: str = ""
    reason: str = ""

    @classmethod
    def from_map(cls, package: str, raw: dict | None) -> "Entry":
        if raw is None:
            return cls(package=package, names=[package])
        return cls(
            package=package,
            source=str(raw.get("source", "dnf")),
            names=[str(n) for n in raw.get("names", [package])],
            copr=str(raw.get("copr", "")),
            app_id=str(raw.get("app_id", "")),
            installer=str(raw.get("installer", "")),
            reason=str(raw.get("reason", "")),
        )


def load_map(path: Path) -> dict[str, dict]:
    if not path.is_file():
        die(f"package map not found at {path}")
    with path.open("rb") as fp:
        return tomllib.load(fp)


def die(msg: str, code: int = 1) -> None:
    print(f"omedora-pkg: {msg}", file=sys.stderr)
    sys.exit(code)


def warn(msg: str) -> None:
    print(f"omedora-pkg: {msg}", file=sys.stderr)


def info(msg: str) -> None:
    # Keep emit pattern consistent with shell helpers (green prefix).
    print(f"\033[32m{msg}\033[0m")


def resolve(packages: Iterable[str], pkg_map: dict[str, dict]) -> list[Entry]:
    return [Entry.from_map(p, pkg_map.get(p)) for p in packages]


def run(cmd: list[str], dry_run: bool, check: bool = True) -> int:
    """Run a command. Honors OMARCHY_PKG_DRY_RUN — when set, just logs."""
    if dry_run:
        info(f"[dry-run] {' '.join(cmd)}")
        return 0
    result = subprocess.run(cmd, check=False)
    if check and result.returncode != 0:
        sys.exit(result.returncode)
    return result.returncode


def is_installed_rpm(name: str) -> bool:
    if shutil.which("rpm") is None:
        # No rpm on PATH (e.g., dry-run smoke check from an Arch host).
        # Treat as "not installed" so dry-runs surface every install.
        return False
    return subprocess.run(
        ["rpm", "-q", name],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    ).returncode == 0


def is_installed_flatpak(app_id: str) -> bool:
    if shutil.which("flatpak") is None:
        return False
    result = subprocess.run(
        ["flatpak", "info", app_id],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return result.returncode == 0


def is_installed_source(package: str) -> bool:
    """Source installers write a version marker; check it exists."""
    marker = (
        Path.home() / ".local" / "state" / "omedora"
        / "installed-versions" / package
    )
    return marker.is_file()


def is_entry_installed(entry: Entry) -> bool:
    if entry.source == "skip":
        # Skip entries are treated as "always installed" so they don't trip
        # missing-checks. They're effectively no-ops.
        return True
    if entry.source in ("dnf", "copr"):
        return all(is_installed_rpm(n) for n in entry.names) if entry.names else False
    if entry.source == "flathub":
        return is_installed_flatpak(entry.app_id)
    if entry.source == "source":
        return is_installed_source(entry.package)
    return False


# ---------------------------------------------------------------------------
# Subcommand handlers
# ---------------------------------------------------------------------------

def cmd_missing(entries: list[Entry], _: argparse.Namespace) -> int:
    """Exit 0 if ANY entry is missing, 1 if ALL present (matches omarchy-pkg-missing semantics)."""
    for entry in entries:
        if not is_entry_installed(entry):
            return 0
    return 1


def cmd_present(entries: list[Entry], _: argparse.Namespace) -> int:
    """Exit 0 if ALL entries present, 1 if any missing."""
    for entry in entries:
        if not is_entry_installed(entry):
            return 1
    return 0


def cmd_add(entries: list[Entry], args: argparse.Namespace) -> int:
    """Install each entry per its source. Coalesces dnf installs into one call."""
    dnf_names: list[str] = []
    coprs_to_enable: set[str] = set()
    flathub_ids: list[str] = []
    source_installers: list[Entry] = []
    skipped: list[Entry] = []

    for entry in entries:
        if entry.source == "skip":
            skipped.append(entry)
            continue
        if is_entry_installed(entry):
            continue
        if entry.source == "dnf":
            dnf_names.extend(entry.names)
        elif entry.source == "copr":
            coprs_to_enable.add(entry.copr)
            dnf_names.extend(entry.names)
        elif entry.source == "flathub":
            flathub_ids.append(entry.app_id)
        elif entry.source == "source":
            source_installers.append(entry)
        else:
            die(f"unknown source '{entry.source}' for package '{entry.package}'")

    for entry in skipped:
        warn(f"skipping '{entry.package}' on Fedora: {entry.reason or 'no reason given'}")

    # Enable COPRs first (idempotent).
    for copr in sorted(coprs_to_enable):
        info(f"Ensuring COPR enabled: {copr}")
        run(["sudo", "dnf", "copr", "enable", "-y", copr], args.dry_run)

    # Install dnf packages in a single dnf call.
    if dnf_names:
        info(f"Installing via dnf: {' '.join(dnf_names)}")
        run(["sudo", "dnf", "install", "-y", "--setopt=install_weak_deps=False",
             *dnf_names], args.dry_run)

    # Install Flatpaks (per app).
    for app_id in flathub_ids:
        info(f"Installing via flatpak: {app_id}")
        run(["flatpak", "install", "--user", "-y", "flathub", app_id], args.dry_run)

    # Run source installers (each is a separate script).
    installers_dir = Path(os.environ.get("OMARCHY_FEDORA_INSTALLERS", DEFAULT_INSTALLERS))
    for entry in source_installers:
        installer_path = installers_dir / entry.installer
        if not installer_path.is_file():
            die(f"installer '{entry.installer}' for '{entry.package}' "
                f"not found at {installer_path}")
        info(f"Running source installer: {entry.installer}")
        run(["bash", str(installer_path)], args.dry_run)

    # Post-install verification for dnf/copr packages.
    if dnf_names and not args.dry_run:
        for name in dnf_names:
            if not is_installed_rpm(name):
                print(
                    f"\033[31mError: Package '{name}' did not install\033[0m",
                    file=sys.stderr,
                )
                return 1

    return 0


def cmd_drop(entries: list[Entry], args: argparse.Namespace) -> int:
    """Remove each entry per its source. Coalesces dnf removes into one call."""
    dnf_names: list[str] = []
    flathub_ids: list[str] = []

    for entry in entries:
        if entry.source == "skip":
            continue
        if not is_entry_installed(entry):
            continue
        if entry.source in ("dnf", "copr"):
            dnf_names.extend(entry.names)
        elif entry.source == "flathub":
            flathub_ids.append(entry.app_id)
        elif entry.source == "source":
            warn(
                f"package '{entry.package}' was source-installed; "
                "dropping is not automated. Remove manually if desired."
            )

    if dnf_names:
        info(f"Removing via dnf: {' '.join(dnf_names)}")
        run(["sudo", "dnf", "remove", "-y", *dnf_names], args.dry_run)

    for app_id in flathub_ids:
        info(f"Removing via flatpak: {app_id}")
        run(["flatpak", "uninstall", "--user", "-y", app_id], args.dry_run)

    return 0


# `aur-add` on Fedora is functionally identical to `add` — the tier fallback
# in the map handles what AUR would have on Arch.
cmd_aur_add = cmd_add


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="omedora-pkg", description=__doc__)
    parser.add_argument(
        "--dry-run",
        action="store_true",
        default=bool(os.environ.get("OMARCHY_PKG_DRY_RUN")),
        help="Print commands instead of executing",
    )
    subparsers = parser.add_subparsers(dest="action", required=True)

    for name in ("add", "missing", "present", "drop", "aur-add"):
        sp = subparsers.add_parser(name)
        sp.add_argument("packages", nargs="+", metavar="PKG")

    args = parser.parse_args(argv)

    map_path = Path(os.environ.get("OMARCHY_FEDORA_MAP", DEFAULT_MAP))
    pkg_map = load_map(map_path)
    entries = resolve(args.packages, pkg_map)

    handlers = {
        "add": cmd_add,
        "missing": cmd_missing,
        "present": cmd_present,
        "drop": cmd_drop,
        "aur-add": cmd_aur_add,
    }
    return handlers[args.action](entries, args)


if __name__ == "__main__":
    sys.exit(main())
