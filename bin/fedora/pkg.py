#!/usr/bin/env python3
"""
Fedora-side package helper for omedora.

Invoked by the bin/omarchy-pkg-* shell wrappers when omarchy-distro is fedora.
Handles map resolution (install/packages/fedora.toml) and dispatches to dnf,
rpm, or flatpak.

Subcommands:
  add <pkg> [<pkg>...]      Install if missing
  missing <pkg> [<pkg>...]  Exit 0 if ANY package is missing, 1 if all present
  present <pkg> [<pkg>...]  Exit 0 if ALL packages present, 1 if any missing
  drop <pkg> [<pkg>...]     Remove if installed (best-effort per source)
  aur-add <pkg> [<pkg>...]  Tier-fallback install (alias for `add` on Fedora)

Env vars:
  OMARCHY_FEDORA_MAP         Path to fedora.toml (default: derived from script)
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

from package_map import resolve_mapping

def _resolve_tree_root() -> Path:
    """Root of the omarchy tree this helper belongs to.

    Three homes, in precedence order:
      1. the script's own checkout (bin/fedora/ -> repo root) when the map
         exists there — dev checkouts and the install bootstrap;
      2. $OMARCHY_PATH — the live tree on an installed system;
      3. /usr/share/omarchy — the packaged default (the omedora RPM installs
         this helper at /usr/bin/fedora/, so script-relative resolution lands
         at /usr, which is wrong on installed systems).
    """
    script_root = Path(__file__).resolve().parent.parent.parent
    candidates = [script_root]
    if os.environ.get("OMARCHY_PATH"):
        candidates.append(Path(os.environ["OMARCHY_PATH"]))
    candidates.append(Path("/usr/share/omarchy"))
    for root in candidates:
        if (root / "install" / "packages" / "fedora.toml").is_file():
            return root
    return script_root


REPO_ROOT = _resolve_tree_root()
DEFAULT_MAP = REPO_ROOT / "install" / "packages" / "fedora.toml"
@dataclass
class Entry:
    package: str
    source: str = "dnf"            # default when entry absent
    names: list[str] = field(default_factory=list)
    copr: str = ""
    app_id: str = ""
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
    entries = []
    for package in packages:
        raw, active = resolve_mapping(package, pkg_map)
        if active:
            entries.append(Entry.from_map(package, raw))
        else:
            entries.append(Entry(
                package=package,
                source="skip",
                reason="mapping does not apply to this Fedora release",
            ))
    return entries


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


def is_entry_installed(entry: Entry) -> bool:
    if entry.source == "skip":
        # Skip entries are treated as "always installed" so they don't trip
        # missing-checks. They're effectively no-ops.
        return True
    if entry.source in ("dnf", "copr"):
        return all(is_installed_rpm(n) for n in entry.names) if entry.names else False
    if entry.source == "flathub":
        return is_installed_flatpak(entry.app_id)
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

    # Install Flatpaks (per app). Tolerate failure when there's no DBus
    # session bus (e.g., container builds): a `flatpak install --user` call
    # without DBus produces "Could not connect: No such file or directory"
    # and exits non-zero. Skipping with a warning lets the rest of the
    # install proceed; production users (with a real session) re-run
    # `omedora update` later to pick the flatpaks up.
    # OMEDORA_VM_FAST: the L4-VM test harness's fast mode. Flatpak runtimes are
    # multi-GB and dominate the VM install time; skipping them keeps a faithful
    # dnf/COPR install (the thing the VM tier is actually validating) while
    # cutting ~10-20min off the run. Off by default — full runs still install
    # Flatpaks. (Same shape as the DBus-absent skip below.)
    if flathub_ids and os.environ.get("OMEDORA_VM_FAST"):
        warn(
            f"OMEDORA_VM_FAST set; skipping {len(flathub_ids)} Flatpak "
            "install(s) (fast L4-VM mode). dnf/COPR packages still install."
        )
    elif flathub_ids and not (os.environ.get("DBUS_SESSION_BUS_ADDRESS")
                            or os.path.exists(f"/run/user/{os.getuid()}/bus")):
        warn(
            f"no DBus session bus detected; skipping {len(flathub_ids)} "
            "Flatpak install(s). Re-run from a desktop session to pick them "
            "up, or set DBUS_SESSION_BUS_ADDRESS in a build env."
        )
    else:
        for app_id in flathub_ids:
            info(f"Installing via flatpak: {app_id}")
            # check=False so a single Flatpak failure doesn't abort the
            # whole install — the user can retry the failing one later.
            run(["flatpak", "install", "--user", "-y", "flathub", app_id],
                args.dry_run, check=False)

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
