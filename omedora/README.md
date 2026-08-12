# Omedora documentation

This folder is Omedora's design and contributor documentation — the "why" and
"how" behind the fork. **If you just want to install and use Omedora, start with
the [root README](../README.md).**

This is the **Omarchy 4** line of Omedora — the re-architected, package-backed
generation with the new Quickshell shell. It tracks upstream Omarchy 4 (codename
"quattro") and is currently **beta**. The stable, field-tested line is
[Omedora 3](https://github.com/AndrewGaspar/omedora/tree/omedora-3) (the `omedora-3`
branch).

Omedora is a fork of [basecamp/omarchy](https://github.com/basecamp/omarchy)
retargeted at **stable Fedora Workstation (44+)**. It's structured as a small,
additive **patch stack continuously rebased onto upstream Omarchy 4**: most Omarchy
files are byte-for-byte unchanged and the Arch code paths inside the dual-distro
helpers stay intact, so the same tree runs on both distros. Long-term, the goal is
that agents (Claude) handle most of the rebase work each release; this folder is the
architectural anchor for that work.

## The documentation set

Read these in roughly this order:

| Doc | What it covers |
|---|---|
| [`architecture.md`](architecture.md) | The technical design: the package-backed Omarchy 4 model, dual-distro patch model, package-helper dispatch, install-pipeline gating, CLI rebrand mechanism, update flow, branding. Includes the patch-stack map — the canonical list of files Omedora touches. |
| [`packages.md`](packages.md) | The tiered package-mapping strategy (Fedora main → RPM Fusion → COPR → Flathub → Omedora RPMs → skip), the on-demand package flow, and the TOML schema for `install/packages/fedora.toml`. |
| [`testing.md`](testing.md) | The test pyramid (shell unit → Fedora container integration → smoke → L4-nested full session). Includes the L4-headless automated suite. |
| [`versioning.md`](versioning.md) | Omedora's SemVer + release-tag scheme, the version-scoped COPR, and the two-channel (git + dnf) update flow. |
| [`update-and-upgrade.md`](update-and-upgrade.md) | The `omedora update` flow on the package-backed Omarchy 4 base and what happens at Fedora major-version upgrades. |
| [`rebase-workflow.md`](rebase-workflow.md) | How to resync onto a newer upstream `quattro`: the pin-tag rebase + force-push recipe (correct on this package-backed line, forbidden on omedora-3), conflict triage, byte-identity ALLOW maintenance, verification matrix. |
| [`branding.md`](branding.md) | Where "Omedora" surfaces vs where "Omarchy" remains, and the ASCII logo. |
| [`AGENTS.md`](AGENTS.md) | Supplemental rules for Claude (and humans) working on this fork. Read alongside the root [`../AGENTS.md`](../AGENTS.md). |

## Packaging

Everything Fedora and RPM Fusion don't ship is built and served from Omedora's own
COPR — **`agaspar/omedora-4`**. The base system enables **no third-party COPRs**;
the Hyprland stack, the Quickshell shell, and the tools are vendored as Omedora RPMs
under [`packaging/copr/`](packaging/copr/) (specs adapted from the maintained
`solopasha/hyprlandRPM` spec set). The single allowed third-party COPR,
`scottames/ghostty`, is enabled **only on demand** if a user installs the optional
Ghostty terminal from the menu. See [`packages.md`](packages.md) for the full
tiering rules and the review checklist for adding any new package source.

## Status

**Beta.** The Omarchy 4 port is on the **`omedora-4`** branch, rebased onto
upstream Omarchy 4 ("quattro"). The fresh-install path (`omedora/install-4.sh`),
the package-backed payload (`omedora`/`omedora-settings` RPMs), the dnf-backed
update pipeline, and the Quickshell shell all build and run on the
**`agaspar/omedora-4` COPR** (`fedora-44-x86_64`) and pass the L1 + L4-nested
session suites. The first Omedora 4 beta package wave is in progress.

## License

Same as upstream Omarchy. See [`../LICENSE`](../LICENSE).
