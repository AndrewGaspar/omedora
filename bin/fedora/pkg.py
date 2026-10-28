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
  installed [<pkg>...]      Print each named package `present` would accept, one
                            per line, from one rpm query and one flatpak listing
  drop <pkg> [<pkg>...]     Remove if installed (best-effort per source); like
                            pacman -R, never removes an RPM another installed
                            package still needs (--rpm: names are RPM names)
  aur-add <pkg> [<pkg>...]  Tier-fallback install (alias for `add` on Fedora)

Env vars:
  OMARCHY_FEDORA_MAP         Path to fedora.toml (default: derived from script)
  OMARCHY_PKG_DRY_RUN        If set, log commands instead of executing
"""

from __future__ import annotations

import argparse
import os
import re
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
    # RPMs that, when installed, already satisfy this entry — another provider
    # of the same software, or a package that Conflicts with `names` and must
    # be kept (docker-ce for the moby-engine mapping). See packages.md §2.
    satisfied_by: list[str] = field(default_factory=list)

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
            satisfied_by=[str(n) for n in raw.get("satisfied_by", [])],
        )

    def targets(self) -> list[str]:
        """What `add` would install for this entry (RPM names or the app id)."""
        return [self.app_id] if self.source == "flathub" else self.names


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


# Answers `prefetch` gathered in bulk. The menu asks about every package it
# guards at once, and a process per name is what it cannot afford.
_rpm_answers: dict[str, bool] = {}
_flatpak_ids: set[str] | None = None


def prefetch(entries: list[Entry]) -> None:
    """Answer every RPM and Flatpak lookup these entries need in two queries.

    `rpm -q` matches a package by name, or by name.arch (the map names i686
    libraries that way), and never by what a package provides. Queried with
    a format printing both forms, a name counts exactly when it comes back
    as a line of its own; one it does not find prints "package X is not
    installed" instead. `flatpak list` covers the user and system
    installations `flatpak info` searches. Nothing is remembered from a
    query that cannot run, so the per-name lookups still answer.
    """
    global _flatpak_ids
    rpm_names = sorted({
        name
        for entry in entries if entry.source != "skip"
        for name in [*entry.satisfied_by, *(entry.names if entry.source in ("dnf", "copr") else [])]
    })
    if rpm_names and shutil.which("rpm") is not None:
        result = subprocess.run(
            ["rpm", "-q", "--qf", "%{NAME}\\n%{NAME}.%{ARCH}\\n", "--", *rpm_names],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        )
        found = set(result.stdout.splitlines())
        _rpm_answers.update((name, name in found) for name in rpm_names)
    if any(entry.source == "flathub" for entry in entries) and shutil.which("flatpak") is not None:
        result = subprocess.run(
            ["flatpak", "list", "--columns=application"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        )
        if result.returncode == 0:
            _flatpak_ids = set(result.stdout.split())


def is_installed_rpm(name: str) -> bool:
    if name in _rpm_answers:
        return _rpm_answers[name]
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
    if _flatpak_ids is not None:
        return app_id in _flatpak_ids
    if shutil.which("flatpak") is None:
        return False
    result = subprocess.run(
        ["flatpak", "info", app_id],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return result.returncode == 0


def installed_provider(entry: Entry) -> str | None:
    """The first installed `satisfied_by` RPM, or None.

    Such a package is the user's own (their Docker CE, say). Omedora never
    installs, removes, or replaces it: while it is present the entry simply
    counts as installed.
    """
    for name in entry.satisfied_by:
        if is_installed_rpm(name):
            return name
    return None


def targets_installed(entry: Entry) -> bool:
    """True when the entry's own install targets are all present."""
    if entry.source in ("dnf", "copr"):
        return all(is_installed_rpm(n) for n in entry.names) if entry.names else False
    if entry.source == "flathub":
        return is_installed_flatpak(entry.app_id)
    return False


def is_entry_installed(entry: Entry) -> bool:
    if entry.source == "skip":
        # Nothing is installed for a skip entry, so it is never present: a
        # guard like `omarchy-pkg-present superwhisper-bin` must not offer to
        # remove, or call, what Fedora never got. `missing` stays its exact
        # complement, as upstream's helpers and the menu's shadows of them
        # assume; `add` reports the skip and installs nothing.
        return False
    if installed_provider(entry) is not None:
        return True
    return targets_installed(entry)


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


def cmd_installed(entries: list[Entry], _: argparse.Namespace) -> int:
    """Print each entry `present` would accept on its own, once, in order.

    The menu's guard batch builds its package set from this instead of asking
    `present` once per row; the answers are the same by construction.
    """
    prefetch(entries)
    seen: set[str] = set()
    for entry in entries:
        if entry.package not in seen and is_entry_installed(entry):
            print(entry.package)
        seen.add(entry.package)
    return 0


def cmd_app_id(entries: list[Entry], _: argparse.Namespace) -> int:
    """Print the Flatpak app id of the first Flathub-mapped entry.

    A Flathub app registers its launcher as <app-id>.desktop, not under the
    Arch desktop id, so callers that launch by desktop id need this instead.
    Exit 1 (no output) when no entry comes from Flathub.
    """
    for entry in entries:
        if entry.source == "flathub" and entry.app_id:
            print(entry.app_id)
            return 0
    return 1


def cmd_add(entries: list[Entry], args: argparse.Namespace) -> int:
    """Install each entry per its source. Coalesces dnf installs into one call."""
    dnf_names: list[str] = []
    coprs_to_enable: set[str] = set()
    flathub_ids: list[str] = []
    skipped: list[Entry] = []
    satisfied: list[tuple[Entry, str]] = []

    for entry in entries:
        if entry.source == "skip":
            skipped.append(entry)
            continue
        provider = installed_provider(entry)
        if provider is not None:
            satisfied.append((entry, provider))
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

    # One line per kept provider. omedora/install/plan.sh parses the
    # "Keeping installed " prefix to disclose these at the plan gate.
    for entry, provider in satisfied:
        info(
            f"Keeping installed {provider}: it satisfies '{entry.package}', "
            f"so {' '.join(entry.targets())} will not be installed"
        )

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


# One unmet dependency in `rpm -e --test` output (always run under LC_ALL=C):
#   "\tlibfido2.so.1()(64bit) is needed by (installed) libssh-0.12.2-1.fc44.x86_64"
_NEEDED_BY = re.compile(r"^\s*(?P<dep>.+?) is needed by \(installed\) (?P<nevra>\S+)\s*$")
_NOT_INSTALLED = re.compile(r"^error: package (?P<name>\S+) is not installed\s*$")


def _rpm(args: list[str]) -> subprocess.CompletedProcess:
    """Run a read-only rpm query in the C locale, so its messages parse."""
    return subprocess.run(
        ["rpm", *args],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        env={**os.environ, "LC_ALL": "C"},
    )


def _nevra_name(nevra: str) -> str:
    """The package name of an rpm NEVRA such as openssh-clients-10.2p1-16.fc44.x86_64."""
    base = nevra.rsplit(".", 1)[0] if "." in nevra else nevra
    parts = base.rsplit("-", 2)
    return parts[0] if len(parts) == 3 else nevra


def _rpm_capabilities(names: list[str]) -> dict[str, set[str]]:
    """What each target name provides: its Provides and its files, in one query.

    A target may be a bare name or name.arch (the map names i686 libraries
    that way); both forms key the same installed package.
    """
    result = _rpm([
        "-q", "--qf",
        "[%{=NAME}\t%{=ARCH}\t%{PROVIDENAME}\n][%{=NAME}\t%{=ARCH}\t%{FILENAMES}\n]",
        "--", *names,
    ])
    caps: dict[str, set[str]] = {name: set() for name in names}
    for line in result.stdout.splitlines():
        fields = line.split("\t", 2)
        if len(fields) != 3:
            continue
        pkg, arch, cap = fields
        for key in (pkg, f"{pkg}.{arch}"):
            if key in caps:
                caps[key].add(cap)
    return caps


def _satisfiers(dep: str, candidates: list[str], caps: dict[str, set[str]]) -> list[str]:
    """The candidates that satisfy one unmet dependency rpm reported.

    rpm prints the dependency as written: a name or soname, a versioned
    "name >= 1.2", a file path, or a rich "(a or b)" expression. Any word of it
    a candidate provides counts, so a rich dependency keeps every candidate it
    names. When nothing matches, `rpm --whatprovides` answers for this one
    dependency; failing that, every candidate is kept, since keeping too much
    is the safe side of this question.
    """
    words: set[str] = set()
    for token in dep.split():
        # A rich expression's parentheses cling to its words, and a soname
        # carries its own: "(libfoo.so.1()(64bit)" and "bar)". Try each form.
        token = token.lstrip("(")
        while token:
            words.add(token)
            if not token.endswith(")"):
                break
            token = token[:-1]
    found = [name for name in candidates if words & caps.get(name, set())]
    if found:
        return found
    result = _rpm(["-q", "--whatprovides", "--qf", "%{NAME}\n", "--", dep])
    providers = set(result.stdout.split()) if result.returncode == 0 else set()
    found = [name for name in candidates if name in providers or name.rsplit(".", 1)[0] in providers]
    return found or list(candidates)


def plan_rpm_removal(names: list[str]) -> tuple[list[str], dict[str, list[str]]]:
    """Split installed RPM names into (removable, kept -> the packages needing it).

    pacman -R refuses to remove a package another installed package depends
    on; `dnf remove` instead removes the dependents too (libfido2 would take
    openssh-clients, libssh and, through libcurl, dnf itself). This restores
    pacman's answer one package at a time: `rpm -e --test` reports every
    dependency the removal would break, whether on a name, a soname, a file or
    a rich expression, and each target that satisfies one is kept. Keeping a
    target can strand another one it needs, so the test repeats on what is
    left until it passes; each round keeps at least one target, so it ends.
    Dependents inside the removal set are fine: rpm only reports packages
    outside it.
    """
    remaining = list(dict.fromkeys(names))
    kept: dict[str, set[str]] = {}
    if not remaining or shutil.which("rpm") is None:
        return remaining, {}
    caps = _rpm_capabilities(remaining)
    while remaining:
        result = _rpm(["-e", "--test", "--allmatches", "--", *remaining])
        if result.returncode == 0:
            break
        needed: dict[str, set[str]] = {}
        gone: set[str] = set()
        for line in result.stdout.splitlines():
            if match := _NEEDED_BY.match(line):
                requirer = _nevra_name(match["nevra"])
                for name in _satisfiers(match["dep"], remaining, caps):
                    needed.setdefault(name, set()).add(requirer)
            elif match := _NOT_INSTALLED.match(line):
                gone.add(match["name"])
        if not needed and not gone:
            die(
                "could not check what still needs "
                f"{' '.join(remaining)}; nothing was removed:\n{result.stdout.strip()}"
            )
        for name, requirers in needed.items():
            kept.setdefault(name, set()).update(requirers)
        remaining = [name for name in remaining if name not in needed and name not in gone]
    return remaining, {name: sorted(requirers) for name, requirers in kept.items()}


def cmd_drop(entries: list[Entry], args: argparse.Namespace) -> int:
    """Remove each entry per its source. Coalesces dnf removes into one call.

    An RPM another installed package still needs is kept with a line naming
    them, the rest are removed, and the exit status stays 0: as with pacman
    refusing a dependency, the system is consistent and nothing failed, so the
    upstream removers (which run under set -e) carry on with their cleanup.
    """
    dnf_names: list[str] = []
    flathub_ids: list[str] = []

    for entry in entries:
        if entry.source == "skip":
            continue
        # Only the entry's own targets are ever removed. A satisfied_by
        # provider is the user's package, never omedora's to drop.
        if not targets_installed(entry):
            continue
        if entry.source in ("dnf", "copr"):
            dnf_names.extend(entry.names)
        elif entry.source == "flathub":
            flathub_ids.append(entry.app_id)

    dnf_names, kept = plan_rpm_removal(dnf_names)
    for name, requirers in kept.items():
        shown = ", ".join(requirers[:6]) + (f" and {len(requirers) - 6} more" if len(requirers) > 6 else "")
        print(f"\033[33mKept {name}: needed by {shown}\033[0m")

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

    for name in ("add", "missing", "present", "drop", "aur-add", "app-id"):
        sp = subparsers.add_parser(name)
        sp.add_argument("packages", nargs="+", metavar="PKG")
    subparsers.add_parser("installed").add_argument("packages", nargs="*", metavar="PKG")
    subparsers.choices["drop"].add_argument(
        "--rpm",
        action="store_true",
        help="The names are RPM names, as installed: remove them untranslated",
    )

    args = parser.parse_args(argv)

    map_path = Path(os.environ.get("OMARCHY_FEDORA_MAP", DEFAULT_MAP))
    pkg_map = load_map(map_path)
    entries = resolve(args.packages, pkg_map)
    if getattr(args, "rpm", False):
        entries = [Entry(package=name, names=[name]) for name in args.packages]

    handlers = {
        "add": cmd_add,
        "missing": cmd_missing,
        "present": cmd_present,
        "drop": cmd_drop,
        "aur-add": cmd_aur_add,
        "app-id": cmd_app_id,
        "installed": cmd_installed,
    }
    return handlers[args.action](entries, args)


if __name__ == "__main__":
    sys.exit(main())
