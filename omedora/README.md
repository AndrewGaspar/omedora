# Omedora documentation

This folder is Omedora's design and contributor documentation — the "why" and
"how" behind the fork. **If you just want to install and use Omedora, start with
the [root README](../README.md)** and the [install guide](install.md).

Omedora is a fork of [basecamp/omarchy](https://github.com/basecamp/omarchy)
retargeted at **stable Fedora Workstation (44+)**. It's structured as a small,
additive **patch stack continuously rebased onto Omarchy's latest stable release**:
most Omarchy files are byte-for-byte unchanged and the Arch code paths inside the
dual-distro helpers stay intact, so the same tree runs on both distros — Arch users
of this fork get upstream Omarchy untouched, Fedora users get the Omedora variant.
Long-term, the goal is that agents (Claude) handle most of the rebase work each
release; this folder is the architectural anchor for that work.

## The documentation set

Read these in roughly this order:

| Doc | What it covers |
|---|---|
| [`install.md`](install.md) | The complete install reference: requirements, quick + manual install, what the installer does, first login, verification, coexistence on an existing machine, troubleshooting, and known issues. |
| [`architecture.md`](architecture.md) | The technical design: dual-distro patch model, package-helper dispatch, install-pipeline gating, CLI rebrand mechanism, update flow, branding. Includes the patch-stack map — the canonical list of files Omedora touches. |
| [`packages.md`](packages.md) | The tiered package-mapping strategy (Fedora main → RPM Fusion → COPR → Flathub → Omedora RPMs → skip) and the TOML schema for `install/packages/fedora.toml`. |
| [`testing.md`](testing.md) | The test pyramid (shell unit → Fedora container integration → smoke → L4-nested full session → L4-VM real Workstation VM). Includes the L4-headless automated suite and the libvirt VM pipeline. |
| [`versioning.md`](versioning.md) | Omedora's SemVer + release-tag scheme, the version-scoped COPR, and the two-channel (git + dnf) update flow. |
| [`update-and-upgrade.md`](update-and-upgrade.md) | The `omedora update` flow on Fedora and what happens at Fedora major-version upgrades. |
| [`rebase-workflow.md`](rebase-workflow.md) | How to rebase onto a new upstream Omarchy release: branching, conflict triage, verification matrix. |
| [`branding.md`](branding.md) | Where "Omedora" surfaces vs where "Omarchy" remains, and the ASCII logo. |
| [`AGENTS.md`](AGENTS.md) | Supplemental rules for Claude (and humans) working on this fork. Read alongside the root [`../AGENTS.md`](../AGENTS.md). |

## Packaging

Everything Fedora and RPM Fusion don't ship is built and served from Omedora's own
COPR — **`agaspar/omedora-3`**. There are **no third-party COPR dependencies**; the
Hyprland stack and tools are vendored as Omedora RPMs under
[`packaging/copr/`](packaging/copr/) (specs adapted from the maintained
`solopasha/hyprlandRPM` spec set). See [`packages.md`](packages.md) for the full
tiering rules and the review checklist for adding any new package source.

## Status

The stable line is the **`omedora-3`** branch (the repo default; rebased on Omarchy
3.8.2). The full Fedora install path is shipped and serving from the
**`agaspar/omedora-3` COPR** (`fedora-44-x86_64`): all vendored RPMs build on the
COPR, the installer enables it and resolves the whole stack, the coexistence gate +
foreign-package replacement are in, and the versioning/release/update machinery is
wired. The install is verified end-to-end on a **real Fedora 44 Workstation VM**
(`test/fedora/vm/`) — provision GNOME+GDM → install from the live COPR → boot the
Omedora session on a real seat → the full assertion suite passes — in addition to
the L4-nested container suite.

## License

Same as upstream Omarchy. See [`../LICENSE`](../LICENSE).
