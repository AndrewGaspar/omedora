#!/usr/bin/env python3
"""Shared Fedora-version handling for Omedora package-map consumers."""

from __future__ import annotations

import os
from pathlib import Path


def fedora_version() -> int:
  value = os.environ.get("OMEDORA_FEDORA_VERSION")
  if value is None:
    os_release = Path("/etc/os-release")
    if not os_release.is_file():
      raise RuntimeError("cannot determine Fedora version: /etc/os-release is missing")
    values = {}
    for line in os_release.read_text().splitlines():
      if "=" in line:
        key, raw = line.split("=", 1)
        values[key] = raw.strip().strip('"')
    value = values.get("VERSION_ID")

  if value is None:
    raise RuntimeError("cannot determine Fedora version: VERSION_ID is missing")
  try:
    return int(value)
  except ValueError as error:
    raise RuntimeError(f"invalid Fedora VERSION_ID: {value!r}") from error


def entry_applies(entry: dict) -> bool:
  since = entry.get("since")
  until = entry.get("until")
  if since is None and until is None:
    return True

  current = fedora_version()
  if since is not None and current < int(since):
    return False
  if until is not None and current >= int(until):
    return False
  return True


def resolve_mapping(
  package: str, package_map: dict[str, dict]
) -> tuple[dict | None, bool]:
  entry = package_map.get(package)
  if entry is None:
    return None, True
  return entry, entry_applies(entry)
