# Source installers

Bash scripts that fetch and install packages with no Fedora repo, RPM Fusion,
COPR, or Flathub presence. Each installer:

1. Has no shebang (sourced/invoked via `bash <file>`).
2. Starts with a one-line `echo` describing what it does.
3. Is idempotent: re-running is a no-op when the installed version is current.
4. Writes its installed version to
   `~/.local/state/omedora/installed-versions/<package>` so the update flow
   can detect drift.
5. Cleans up any temp directories it creates.

See [`omedora/packages.md`](../../../omedora/packages.md) §4 for the full
convention.

Referenced from [`install/packages/fedora.toml`](../fedora.toml) entries with
`source = "source"`.
