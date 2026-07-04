# Package mapping

This doc covers how omedora translates Omarchy's Arch-named package surface onto Fedora install sources. It defines:

- The **tiered fallback** rule that picks an install source for any given package.
- The **TOML schema** for `install/packages/fedora.toml`, the data file that overrides defaults.
- The **resolution algorithm** the helper commands follow when called with package names.
- The **RPM/COPR tier** — how packages with no Fedora/COPR/Flathub home are built as RPMs under `omedora/packaging/copr/` and served from the omedora repo.
- A **review checklist** for proposing new entries.

For the higher-level architecture, see [`architecture.md` §3–§4](architecture.md#3-package-helper-dispatch).

---

## 1. The package-source tiers

When omedora installs a package on Fedora, it picks an install source in this order. Earlier tiers always win.

| # | Tier | `source` | Notes |
| --- | --- | --- | --- |
| 1 | **Fedora main repos / RPM Fusion** (`dnf install <name>`) | `dnf` | Default. If the package name is unchanged from Arch, no map entry needed. If the name differs, the map provides the Fedora name. RPM Fusion (enabled in preflight) is the same `dnf` codepath — for multimedia codecs and the handful of nonfree libs. |
| 2 | **The omedora repo** (`dnf install <name>` from RPMs we build) | `dnf` | Packages that aren't anywhere in Fedora's ecosystem but that we build ourselves as RPMs under [`omedora/packaging/copr/`](#4-the-rpmcopr-tier-omedorapackagingcopr). Same `source = "dnf"` install path — the RPMs are served from a repo dnf already trusts (a local repo today, a published COPR later). The `names` point at the RPM's package name(s). |
| 3 | **Vetted third-party COPR** (`dnf copr enable <copr>` then `dnf install <name>`) | `copr` | Third-party COPRs we don't maintain. Allowed COPRs are an explicit allowlist (see [§7](#7-review-checklist)). One deliberate exception: **`scottames/ghostty`** for `[ghostty]` — the ghostty-docs-endorsed canonical Fedora COPR, adopted because an in-house Zig build is blocked by ghostty's zig 0.15.x pin vs Fedora 44's zig 0.16 (TODO: revisit vendoring). It is enabled **lazily** — `pkg.py` runs `dnf copr enable` only when a package with a `copr` source is actually installed, and ghostty is on-demand (not a base package), so a machine gains the COPR only if the user picks Install > Terminal > Ghostty. (The former `lionheartp/Hyprland` entry was removed once the hyprwm stack was fully vendored under tier 2.) New COPRs require review. |
| 4 | **Flathub** (`flatpak install -y flathub <app_id>`) | `flathub` | For proprietary or otherwise unpackaged GUI apps. Flathub remote is enabled in preflight. |
| 5 | **Skip** (`source = "skip"`, logged) | `skip` | Not installed on Fedora at all — hardware/Arch-specific packages, bootloader components, or things still awaiting a packaging decision. Always carries a `reason`. |

Tiers 1 and 2 are **both** `source = "dnf"`: the difference is only *which repo* satisfies the name. A reader of `fedora.toml` tells them apart by the `reason` field and by whether the `names` resolve to a Fedora-shipped package or to one of our [`omedora/packaging/copr/`](#4-the-rpmcopr-tier-omedorapackagingcopr) RPMs. This unification is deliberate — `dnf` resolution, dependency handling, and clean install/remove/upgrade work identically whether a name comes from Fedora main or from our repo.

> **Retired tier — source installers.** Earlier drafts had a sixth tier: per-package shell "source installers" (`source = "source"`, `bash install/packages/installers/<name>.sh`). That approach is **retired.** Anything that previously would have been a source installer is now either built as an RPM in [`omedora/packaging/copr/`](#4-the-rpmcopr-tier-omedorapackagingcopr) (tier 2) or left as `source = "skip"` with a TODO until it is. `install/packages/installers/` retains only a `README.md` pointer; the directory is otherwise dead. Do not add new source installers.

**Why preference for earlier tiers:**

- Closer-to-distro tiers benefit from Fedora's update flow, signing, dependency resolution, SELinux contexts, and security patches.
- Each tier we descend introduces more failure modes (COPR maintainer disappearing, Flathub manifest drift, a spec rotting when upstream's release-asset layout changes).
- The map is also a **trust boundary** — every third-party COPR or Flathub manifest used must be reviewed. The RPMs we build ourselves (tier 2) are reviewed as ordinary source in this repo.

**When to break the order:** rarely. Reasons that justify it:

- The Fedora main repo package is severely lagging (multiple major versions behind) and a COPR is current.
- The Flatpak version is functionally broken in the omedora desktop session (e.g., portal mismatch).
- Building our own RPM is the *only* way to get a working install for a particular Fedora version.

If you break the order, document it in the entry's `reason` field.

---

## 2. The `install/packages/fedora.toml` schema

The map is one TOML table per Arch package. **Absence from the map ⇒ Fedora-main-repos install under the same name.** Only add an entry when:

1. The Fedora package name differs from the Arch name, or
2. The package isn't in Fedora main repos at all (needs RPM Fusion / COPR / Flathub / source), or
3. The package should be deliberately skipped on Fedora (with a reason).

### Keys

| Key | Type | Required when | Description |
| --- | --- | --- | --- |
| `source` | string | always | One of `dnf`, `copr`, `flathub`, `skip`. (`dnf` covers both Fedora main/RPM Fusion and the omedora repo — see [§1](#1-the-package-source-tiers).) |
| `names` | array of string | `source ∈ {dnf, copr}` | The Fedora package name(s) to install. Multiple allowed when one Arch package fans out into several packages (e.g., a metapackage, or `omarchy-walker` → `walker` + `elephant`). For omedora-repo RPMs these are the RPM `Name:` fields from [`omedora/packaging/copr/`](#4-the-rpmcopr-tier-omedorapackagingcopr). |
| `copr` | string | `source = "copr"` | The third-party COPR identifier (`owner/repo`) to enable before install. Must be on the allowlist (see [§7](#7-review-checklist)). |
| `app_id` | string | `source = "flathub"` | The Flathub app ID, e.g., `md.obsidian.Obsidian`. |
| `reason` | string | `source = "skip"`; recommended elsewhere when the choice isn't obvious | One-line explanation. Lives in the file so reviewers and agents understand intent. For omedora-repo packages, the `reason` is where we note that the name resolves to one of our RPMs rather than a Fedora-shipped one. |
| `since` | string | optional | Fedora version where this entry first applies (e.g., `"44"`). Lets the map carry historical entries when behavior changed between Fedora releases. |
| `until` | string | optional | Fedora version where this entry stops applying (exclusive). Used together with `since` to express "in main repos from F46 onward, COPR before that." |

### Layout

```toml
# install/packages/fedora.toml
#
# Translation table from Arch package names to Fedora install sources.
# Absence from this file means: "Same name, in Fedora main repos."
#
# Schema is documented in omedora/packages.md. Validate with:
#   omarchy dev validate-fedora-packages    (planned helper)

# --- renamed packages (different name, in Fedora main) -------------------

[nvim]
source = "dnf"
names = ["neovim"]

[ttf-jetbrains-mono-nerd]
source = "dnf"
names = ["omedora-nerd-fonts"]
reason = "Fedora's plain jetbrains-mono-fonts-all lacks the Nerd Font icon glyphs. The omedora-nerd-fonts RPM (omedora/packaging/copr/) bundles the patched families; served from the omedora repo (local now, COPR later)."

# --- omedora-repo packages (RPMs we build; still source = "dnf") ----------

[omarchy-walker]
source = "dnf"
names = ["walker", "elephant"]
reason = "Neither in Fedora repos. Both packaged as RPMs in omedora/packaging/copr/ (walker pulls gtk4-layer-shell; elephant ships its providers + user service) and served from the omedora repo (local now, COPR later)."

[swayosd]
source = "dnf"
names = ["swayosd"]
reason = "Not in Fedora repos and ships no prebuilt binaries, so omedora/packaging/copr/swayosd.spec builds it from source (meson+cargo). Served from the omedora repo."

# --- Hyprland stack (vendored omedora RPMs, served from the omedora repo) --
# Formerly pulled from the third-party lionheartp/Hyprland COPR; that COPR was
# retired in task #66 when the whole hyprwm stack was vendored under
# omedora/packaging/copr/ and routed through source = "dnf" (the omedora repo).

[hyprland]
source = "dnf"
names = ["hyprland-omedora"]
reason = "Hyprland not in Fedora main repos as of F44. Vendored as omedora/packaging/copr/hyprland.spec (split into hyprland-no-session = binaries, hyprland = plain session entry, hyprland-uwsm). On Fedora we install hyprland-omedora (omedora/packaging/copr/hyprland-omedora.spec), which ships omedora's own uwsm wayland-session entry (omedora.desktop, formerly a sudo-cp) and Requires hyprland-no-session + uwsm — so the compositor binaries arrive transitively WITHOUT the visible plain/uwsm session entries."

[hyprlock]
source = "dnf"
names = ["hyprlock"]
reason = "Vendored as omedora/packaging/copr/hyprlock.spec; served from the omedora repo."

# --- Flathub packages ---------------------------------------------------

[obsidian]
source = "flathub"
app_id = "md.obsidian.Obsidian"

[typora]
source = "flathub"
app_id = "io.typora.Typora"
reason = "Proprietary; Flathub is the canonical install path on Fedora."

# --- Explicitly skipped packages ----------------------------------------

# Skipping ufw also means the post-login firewall step is Arch-gated:
# install/first-run/firewall.sh (pure `ufw`) carries a top-of-file
# `[[ … == "arch" ]] || exit 0`, since Fedora's default firewalld is already
# active and `ufw` is never installed. See architecture.md §6.
[ufw]
source = "skip"
reason = "Fedora ships firewalld; omedora does not replace the firewall."

[ufw-docker]
source = "skip"
reason = "Companion to ufw; not needed under firewalld."

[intel-ipu7-camera]
source = "skip"
reason = "Fedora handles via akmod-ipu7 if user opts in; kernel-module install is out of omedora scope."

[linux-firmware-marvell]
source = "skip"
reason = "Surface-specific firmware; users on Surface devices install via Fedora's own channels."

[limine]
source = "skip"
reason = "Bootloader; omedora does not own the boot stack on Fedora."

[snapper]
source = "skip"
reason = "Snapshot integration relies on Limine on Arch; out of scope on Fedora."

# --- Version-conditional entries (since/until) ---------------------------

# Example shape only — promote a COPR/omedora-repo package to Fedora main once
# it lands there, without losing the historical entry:
#
# [somepkg]
# source = "dnf"
# names = ["somepkg"]
# since = "46"        # in Fedora main from F46 onward
```

---

## 3. How `omarchy-pkg-add` resolves an entry

Pseudocode for the Fedora-side resolution loop:

```
for each package_name in args:
  entry = lookup(package_map, package_name)

  if entry is None:
    # Default: same name, Fedora main repos
    dnf_install [package_name]
    continue

  if entry.since and current_fedora_version < entry.since:
    continue using next applicable entry or default
  if entry.until and current_fedora_version >= entry.until:
    continue using next applicable entry or default

  case entry.source:
    dnf:
      # Resolves from Fedora main, RPM Fusion, OR the omedora repo —
      # all the same to dnf once the repo is enabled.
      dnf_install entry.names
    copr:
      ensure_copr_enabled entry.copr
      dnf_install entry.names
    flathub:
      flatpak_install --user flathub entry.app_id
    skip:
      log "Skipping <package_name> on Fedora: <entry.reason>"
      continue
```

Notes:

- Failures from `dnf install` are surfaced; the helper exits non-zero like upstream.
- Failures from `flatpak install` are also surfaced; we don't silently swallow them. The skip-with-log behavior is **only** for `source = "skip"` entries.
- There is no `source` case: per-package source installers are [retired](#1-the-package-source-tiers). Packages that aren't in Fedora/RPM Fusion/a vetted COPR/Flathub are either built as omedora-repo RPMs (`source = "dnf"`) or `source = "skip"`.
- Resolution is identical whether a `dnf` name lives in Fedora main or the omedora repo. The omedora repo only has to be *enabled* for the second case to work — see [§4](#4-the-rpmcopr-tier-omedorapackagingcopr) and [§5](#5-how-the-omedora-repo-is-injected-at-build-time).

---

## 4. The RPM/COPR tier (`omedora/packaging/copr/`)

This is how omedora installs the apps that have **no Fedora, RPM Fusion, vetted-COPR, or Flathub home** — walker, elephant, swayosd, `tte`, the Nerd Fonts. Rather than vendor a shell installer (the [retired](#1-the-package-source-tiers) approach), we build each one as a proper **RPM** and serve it from a dnf repo. In `fedora.toml` these are plain `source = "dnf"` entries pointing at the RPM `names`; everything downstream (dependency resolution, clean upgrade/remove) is ordinary dnf.

The specs and build scripts live in `omedora/packaging/copr/`. The directory is named for its destination: these specs are bound for a **published COPR** eventually. Until then a **local dnf repo** built from the same specs stands in (see [§5](#5-how-the-omedora-repo-is-injected-at-build-time)). Because we build with the exact same spec + toolchain a COPR uses (a `fedora:44` container), a spec that builds locally builds on COPR.

### Spec conventions

Each `.spec` is a single RPM. Three flavors, by how the upstream ships:

| Flavor | When | Example specs | How it works |
| --- | --- | --- | --- |
| **Binary-repackage** | Upstream ships a prebuilt release binary | `walker.spec`, `elephant.spec`, `omedora-nerd-fonts.spec` | No `%build`; `%install` just drops the prebuilt binary/asset into place. Disable debuginfo + strip (`%global debug_package %{nil}` / `%global __os_install_post %{nil}`) since there's no source to process — important for `elephant`, whose Go plugins fail to load if stripped. The payoff over a raw installer: dnf tracking + `Requires:` pulling deps (e.g. `walker` → `gtk4-layer-shell`, `elephant` → `libqalculate`). |
| **From-source (meson/cargo)** | Upstream ships no binaries; it's a compiled project | `swayosd.spec`, `satty.spec`, `tensaku.spec`, `bluetui.spec` | A real `%build`: e.g. SwayOSD is Rust whose `meson` build wraps `cargo build`. `BuildRequires:` names the full toolchain (cargo/rust + the C `-devel` libs the `-sys` crates link). Hermetic/offline: the build runs against a `cargo vendor` tarball (an extra `Source`) generated at SRPM-gen time from upstream's committed `Cargo.lock` (see [Hermetic vendored build](#hermetic-vendored-build) below), so the build phase never touches crates.io. |
| **From-source (Python pyproject)** | A Python project | `terminaltexteffects.spec` | Uses Fedora's `pyproject-rpm-macros`: `%pyproject_buildrequires` derives build deps, `%pyproject_wheel`/`%pyproject_install`/`%pyproject_save_files` build and capture the wheel + console scripts (`tte`). `BuildArch: noarch`. The only network fetch is the PyPI sdist. The most hermetic of the three. |
| **From-source (qmake/Qt6)** | A plain C++/Qt6 project | `omacut.spec`, `omawrite.spec` | The two quattro-line omarchy-family Qt6/QML apps (omacut = video trimmer + ffmpeg; omawrite = Markdown writer, SUPER+SHIFT+W). `%build` just runs upstream's `./bin/build` (`qmake6` + `make`); no vendoring needed — every dep comes from `BuildRequires:` (`qt6-qtbase-devel`/`qt6-qtdeclarative-devel` [+ `qt6-qtmultimedia-devel` for omacut], `gcc-c++`, `make`), so the offline `%build` phase never needs the network. `%global debug_package %{nil}` (qmake `release` builds carry no debug info). omawrite deliberately drops the proprietary `ttf-ia-writer` font `Requires` (skip-mapped; Qt substitutes a fallback monospace). |
| **From-source (Meson/C++)** | A plain C/C++ Meson project | `gpu-screen-recorder.spec` | The GPU-accelerated screen recorder omarchy's `omarchy screenrecord` flow (`bin/omarchy-capture-screenrecording`) and the Quickshell bar indicator (`ScreenRecording.qml`) are **hardcoded** to — they exec / `pgrep -f "^gpu-screen-recorder"`, so skip-mapping it made recording a silent no-op. From-source (`%meson`/`%meson_build`/`%meson_install`), all deps via `BuildRequires:` so `%build` is offline. **ffmpeg:** builds against Fedora main's stripped **`ffmpeg-free-devel`** — gsr encodes via VAAPI/NVENC/Vulkan, not libx264 — so it needs **no RPM Fusion** at build or runtime (all deps resolve from Fedora main; verified with `dnf install --downloadonly`). NVENC/CUDA are `dlopen`'d at runtime (headers bundled in `external/`) — no CUDA build dep. Ships `/usr/bin/gpu-screen-recorder` + the `gsr-kms-server` KMS-capture helper, granted `CAP_SYS_ADMIN` as a **file capability** (not setuid) via `%post: setcap cap_sys_admin+ep`; built with `-Dcapabilities=false` so meson's own install-time `setcap` doesn't choke rpmbuild's fakeroot. Debuginfo stays enabled (a real `-g` C/C++ build). |

Conventions shared across specs: `Source0:` uses macros (`%{url}`, `%{version}`, `%{pypi_source}`) so URLs stay in sync with `Version:`; `spectool -g` (run by the build script) downloads every `SourceN`; the header comment explains *why* this flavor was chosen. Keep the `%changelog` and `Version:` current when bumping.

### Build scripts

| Script | What it does |
| --- | --- |
| `build-local.sh <name.spec>` | Builds **one** spec via `rpmbuild -ba` inside a throwaway `registry.fedoraproject.org/fedora:44` container (our dev host is Arch and has no `rpmbuild`). Installs `rpm-build`/`rpmdevtools`, runs `dnf builddep` for the spec's `BuildRequires`, `spectool -g`'s the sources, builds. Artifacts (the `.rpm` + `.src.rpm`) land in `omedora/packaging/copr/output/`. |
| `build-repo.sh` | Builds **all** specs (its `SPECS=(...)` array — currently `walker elephant omedora-nerd-fonts swayosd terminaltexteffects`) by looping `build-local.sh`, then runs `createrepo_c` over the binary RPMs to assemble a ready-to-serve dnf repo in `omedora/packaging/copr/repo/`. This `repo/` is the local-repo COPR stand-in. |

`output/` and `repo/` are **gitignored** (`omedora/packaging/copr/.gitignore`) — they're build products, rebuilt on demand. Only the specs and scripts are tracked.

### Hermetic vendored build

The from-source Rust specs (`swayosd.spec`, `satty.spec`, `tensaku.spec`, `bluetui.spec`) build **fully offline**: COPR builds in mock, where the rpmbuild (build) phase has no network — only SRPM generation does. So cargo must never reach crates.io at build time. Each spec ships a `cargo vendor` tarball as an extra `Source` and a `.cargo/config.toml` with `[net] offline = true` (written by `%cargo_prep -v vendor`, or by hand for the meson-driven swayosd), so the build resolves every crate from the vendored tree.

**The vendor tarball is not committed.** It's generated deterministically at SRPM-gen time, not stored in the repo (it used to live in Git LFS at ~64 MB total). `build-local.sh`, after `spectool -g` fetches `Source0`, regenerates any `*-vendor.tar.*` `SourceN` that isn't already present: it extracts the upstream release tarball, runs `cargo vendor` against its committed `Cargo.lock`, and re-tars with normalized metadata (`--sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner`) so re-runs are byte-identical. This is deterministic because `Source0` is a version-pinned GitHub tag tarball, the lock pins every transitive dep, and crates.io `(name,version)` content is immutable. (swayosd's lock pins its own root version below its `Cargo.toml`, so it uses plain `cargo vendor`, not `--locked`.)

When the real COPR lands, its `.copr/Makefile` (#60) must run the same `cargo vendor` in its SRPM step so COPR's offline build phase has the vendor dir. The Python and binary-repackage specs don't need any of this (their only fetch is the declared `SourceN`).

---

## 5. How the omedora repo is injected at build time

The local repo from [`build-repo.sh`](#build-scripts) is the **stand-in for a published COPR**: a directory of RPMs plus `createrepo_c` metadata that dnf can install from. The L4-nested session build wires it into the install container so `install.sh`'s `dnf install` resolves the omedora-repo packages (with their deps) exactly as a real COPR would.

`omedora/test/fedora/build-session.sh` does this in two steps:

1. **Build the repo** (step 0): if `omedora/packaging/copr/repo/repodata/repomd.xml` is missing (or `--rebuild`), it runs `build-repo.sh` first.
2. **Inject it** (step 2.5), after the base image is booted but before `install.sh` runs:
   ```bash
   podman cp "$COPR_DIR/repo" "$BUILD_CTR:/opt/omedora-repo"
   podman exec "$BUILD_CTR" bash -c \
     'printf "[omedora-local]\nname=Omedora local packages\nbaseurl=file:///opt/omedora-repo\nenabled=1\ngpgcheck=0\n" >/etc/yum.repos.d/omedora-local.repo'
   ```
   That drops the RPMs in `/opt/omedora-repo` and a `.repo` pointing dnf at them. From that point `dnf install walker elephant swayosd python3-terminaltexteffects omedora-nerd-fonts` Just Works inside the container.

**Swapping to a published COPR** later is a small, contained change: delete the inject block in `build-session.sh` and flip the affected `fedora.toml` entries from `source = "dnf"` (omedora repo) to `source = "copr"` with the COPR identifier. The specs themselves move to the COPR unchanged.

---

## 6. How to add a new entry

When upstream Omarchy adds a new package to `omarchy-base.packages` or to a feature install script, the patch-stack rebase will pull that change in. If the package is identically named in Fedora main repos, no map entry is needed and the install will succeed automatically. Otherwise:

1. **Search Fedora main repos first.** `dnf search <name>`. If found under a slightly different name, add a `source = "dnf"` entry with the `names` translation.
2. **If not in main, check RPM Fusion.** `dnf --enablerepo=rpmfusion-free,rpmfusion-nonfree search <name>`. Still uses `source = "dnf"` since RPM Fusion is enabled in preflight.
3. **If not in RPM Fusion, check the allowed third-party COPRs.** The allowlist currently holds one deliberate exception, `scottames/ghostty` (for `[ghostty]`); `lionheartp/Hyprland` was retired in task #66. Adding a new COPR is a reviewed decision — prefer vendoring into our own COPR (tier 2) unless a Zig/complex build makes that impractical (the ghostty case). If a package is on an allowlisted COPR, add `source = "copr"` with the COPR identifier.
4. **If not in a vetted COPR, check Flathub.** Browse https://flathub.org/. If a maintained Flatpak exists, add `source = "flathub"` with the app ID.
5. **If none of the above, package it as an omedora RPM.** Write a spec under `omedora/packaging/copr/` (see [§4](#4-the-rpmcopr-tier-omedorapackagingcopr) and the workflow below) and route the entry to `source = "dnf"`. This replaces the old source-installer tier. If you can't get to a spec immediately, park the entry as `source = "skip"` with a TODO `reason` so `install.sh` still completes — but the spec is the destination.
6. **If the package is fundamentally not appropriate on Fedora** (a kernel module, a bootloader component, an Arch-specific repo manager), use `source = "skip"` with a clear `reason`.

Every map entry change goes in a PR with the rationale in the commit body. Agents should record the reasoning in detail — future maintainers will read the commit history to understand why a tier choice was made.

### Adding a new packaged app (the RPM/COPR tier)

To take a package from `source = "skip"` (or a missing entry) to an installed omedora-repo RPM:

1. **Write the spec.** Add `omedora/packaging/copr/<name>.spec`, picking the right [flavor](#spec-conventions) (binary-repackage / from-source meson-cargo / Python pyproject). Lead with a comment explaining the choice. Iterate with `omedora/packaging/copr/build-local.sh <name>.spec` until it builds clean in the `fedora:44` container.
2. **Add it to `build-repo.sh`.** Append the spec filename to the `SPECS=(...)` array so the local repo (and the future COPR) builds it.
3. **Flip the `fedora.toml` entry.** Set `source = "dnf"` and `names = [...]` to the RPM `Name:` field(s). Note in `reason` that the name resolves to an omedora-repo RPM, not a Fedora-shipped one.
4. **Rebuild + test.** `omedora/test/fedora/build-session.sh --rebuild` rebuilds the repo, injects it, and runs `install.sh` — the most faithful end-to-end check that dnf resolves the new package and its deps.

---

## 7. Review checklist

Before merging a new map entry — agents and humans both run through this:

- [ ] **Tier choice justified.** Why this tier and not an earlier one? Note in `reason` or commit body.
- [ ] **For `source = "dnf"` (Fedora main / RPM Fusion):** Verify `dnf info <name>` succeeds on a clean Fedora 44 VM/container. Note the package version.
- [ ] **For `source = "dnf"` (omedora repo):** A spec exists in `omedora/packaging/copr/`, it's listed in `build-repo.sh`'s `SPECS`, the RPM `Name:` matches the entry's `names`, and `build-local.sh <spec>` builds clean. The `reason` notes it's an omedora-repo RPM.
- [ ] **For `source = "copr"`:** The third-party COPR must already be on the allowlist below. Adding a *new* COPR requires:
    - Documented maintainer (single individual or org).
    - Build history of at least 6 months with timely Fedora release support.
    - No history of disappearing or distributing modified upstream binaries.
    - A short note in this doc justifying why we trust it.
- [ ] **For `source = "flathub"`:** App ID matches a maintained Flathub listing. Verify it's not a community-mirror of a proprietary app with stale builds.
- [ ] **For `source = "skip"`:** Reason is clear and durable (won't be obsoleted next Fedora release).
- [ ] **Patch-stack map updated.** If this is the first entry of its kind, the new file may need adding to `architecture.md`'s patch-stack map.
- [ ] **Tested.** Ran `omedora update` (or a fresh install) end-to-end on a Fedora 44 VM after the change.

### COPR allowlist

| COPR | Used for | Rationale |
| --- | --- | --- |
| _(none)_ | — | No third-party COPRs are currently in use. |

**Retired:** `lionheartp/Hyprland` (Hyprland + hypridle/hyprlock/hyprpaper/hyprpicker/hyprsunset/xdg-desktop-portal-hyprland). Retired in task #66: the entire hyprwm stack is now vendored as omedora RPMs under [`omedora/packaging/copr/`](#4-the-rpmcopr-tier-omedorapackagingcopr) (specs adapted from the maintained `solopasha/hyprlandRPM` spec set) and resolved via `source = "dnf"` from the omedora repo. `hyprpaper` was dropped entirely (omedora uses swaybg).

This allowlist is for **third-party** COPRs only. The omedora repo (our own RPMs in [`omedora/packaging/copr/`](#4-the-rpmcopr-tier-omedorapackagingcopr), eventually a published omedora COPR) is not a third-party trust decision — those specs are reviewed as ordinary source in this repo — so it doesn't appear here.

To add a new third-party COPR: open a PR that (a) updates this allowlist with rationale, (b) adds the map entries that use it. Both reviewed together.

---

## 8. Validating the map

A planned helper command, `omarchy dev validate-fedora-packages`, parses `install/packages/fedora.toml` and reports:

- Entries with `source = "copr"` whose COPR isn't on the allowlist.
- Entries with an unknown `source` (only `dnf`/`copr`/`flathub`/`skip` are valid — `source` is retired).
- Entries with `source = "dnf"` whose `names` field is empty.
- Entries with `source = "flathub"` whose `app_id` is empty.
- Entries with `source = "skip"` missing `reason`.
- Entries with `since`/`until` that don't form a valid range.

This validator runs as part of the rebase verification step (see [`rebase-workflow.md`](rebase-workflow.md)) and ideally as a CI check. The base commit doesn't ship the validator — it's a follow-up implementation task — but the contract above is what it must enforce.

---

## 9. What the map deliberately doesn't do

- **It doesn't pin versions for `dnf`/`copr` sources.** Fedora and COPRs handle versioning; we don't reproduce a lockfile. The omedora-repo RPMs *do* pin a `Version:` in their spec (bumped by hand), but the map entry stays version-free.
- **It doesn't model dependencies.** dnf and dnf-copr resolve dependencies themselves; same for Flatpak. omedora-repo RPMs declare their deps via `Requires:` in the spec, which dnf then resolves — the map still doesn't list them.
- **It doesn't try to match Arch's optional-vs-required taxonomy.** Omarchy decides what to install via the install scripts; the map only handles translation, not policy.
- **It doesn't override upstream package selection.** If Omarchy adds a package to `omarchy-base.packages`, the map can route it to a tier, but only `source = "skip"` can prevent the install entirely — and skipping should have a clear, durable reason.

---

## 10. Omarchy 4 dependency triage (P1 spike results, 2026-06-11)

Verified live before committing to the port (spike container: `omedora-test:fedora44-session`
\+ the omarchy-4 tree mounted at `/repo`):

| Dependency | Verdict | Evidence / disposition |
| --- | --- | --- |
| `quickshell` | **VENDORED 0.3.0 — see §11** | The shell runs fine on Fedora's `0.2.1^git20260209.dacfa9d` snapshot today (verified: full v4 desktop + wallpaper, L4 6/6 green). We vendor 0.3.0 anyway as a **forward-looking** decision (§11): Fedora's package is frozen since Feb 2026 across all branches incl. rawhide, while omarchy develops against rolling quickshell and is adopting 0.3.0 APIs (networking/polkit). Keeping pace with what omarchy targets, on the single most UX-critical package, is worth one vendored spec. |
| hyprland 0.55.2 (our RPM) + Lua config | **GO, with a re-check note** | `Hyprland --config .../hyprland.lua` (full omarchy-4 lua tree, `OMARCHY_PATH` set) boots on our existing 0.55.2 spec — 189 binds registered from Lua. One `configerrors` entry: a config-load shell-out in `config/hypr/bindings.lua` hit Hyprland's Lua execution timeout in the slow container; re-verify on a real install (not a Lua-capability gap). |
| `dua-cli` | **dnf tier** | In Fedora proper (source package `rust-dua-cli`). |
| `aether`, `cliamp`, `tobi-try` | **skip (existing entries stand)** | 37signals/AUR-world tools; the 3.8.2-era skip reasons hold for 4.x. `cliamp` is bound to SUPER+SHIFT+ALT+M — degrades gracefully. |
| `tzupdate` | **skip (existing entry stands)** | Fedora has `timedatectl set-timezone`; only referenced by a sudoers `--overwrite` in `omarchy-update-system-pkgs` (pacman path). Optional tiny spec later if wanted. |
| `voxtype` / `voxtype-bin` | **on-demand, subpackaged binary-repackage hosted in `agaspar/omedora-4`** | Not in `omarchy-base.packages` — installed on demand by `omarchy-voxtype-install`. We re-host upstream's MIT-licensed Fedora RPM in our COPR via **one spec → three packages** (`omedora/packaging/copr/voxtype.spec`): base **`voxtype`** (wrapper + config + systemd + whisper avx2/avx512/vulkan + ONNX-CPU, ~42 MB; `Requires: curl pipewire-alsa vulkan-loader`) plus opt-in **`voxtype-cuda`** (NVIDIA CUDA ONNX-GPU, cuda-12/cuda-13 trees, ~233 MB) and **`voxtype-migraphx`** (AMD ROCm/MIGraphX, ~13 MB). The GPU subpackages `Requires: voxtype = %{version}-%{release}` (so a base remove cascades) and carry `AutoReqProv: no` (onnxruntime dlopens the providers; upstream declares no CUDA/ROCm Requires). On Fedora, `bin/fedora/voxtype-install-pkg` installs the base (`omarchy-pkg-add wtype voxtype-bin`, mapped to `voxtype`) then **auto-detects the GPU** and adds the matching flavor — `voxtype-cuda` when `omarchy-hw-nvidia` succeeds, `voxtype-migraphx` on an AMD `lspci` match, base-only otherwise. So the default install is slim, nobody pulls CUDA without an NVIDIA GPU, and the whole thing is **`dnf update`-able**. `voxtype-bin`/`voxtype-cuda`/`voxtype-migraphx` are mapped `source = "dnf"` in `fedora.toml`. The wrapper picks `voxtype-{vulkan,avx512,avx2}` at runtime, so `voxtype setup --download / gpu --enable / systemd` run unchanged. **Bump = edit `Version:` + the `.sources` sha** in the spec (COPR's SRPM step fetches + sha-verifies the new upstream RPM on its infra). |
| `foot`, `wtype`, `udiskie`, `yt-dlp` | **dnf tier** | All in Fedora proper. |
| `moonlight-qt` | **RPM Fusion tier** (Flathub fallback) | Not in Fedora proper. |
| `NetworkManager`, `bluez*` | **dnf tier — simplification** | Omarchy 4 dropped iwd/impala/bluetui for NetworkManager/bluez, which is exactly Fedora's stack: the gazelle-tui divergence disappears on the 4.x line. |

---

## 11. Vendored-because-Fedora-is-too-old (version-driven vendor decisions)

Distinct from §10's "not in Fedora" triage: some packages omarchy-4 adopts ARE in
Fedora but at a version too old to satisfy the new desktop. These get vendored into
`omedora/packaging/copr/` like the Hyprland stack and routed via `source = "dnf"` from
the omedora repo, so the version we ship — not Fedora's — wins (a higher upstream
version resolves over Fedora's automatically).

| Package | omedora version | Fedora 44 version | Decision |
| --- | --- | --- | --- |
| `quickshell` | **0.3.0** (vendored, `quickshell.spec`) | 0.2.1^git20260209.dacfa9d (stalled Feb-2026 snapshot, identical across stable/updates/testing/rawhide) | **Vendor 0.3.0 — forward-looking, not a current-break fix.** The v4 desktop runs correctly on Fedora's 0.2.1 today (the earlier "the `updatesEnabled` property absence breaks the wallpaper" reasoning was a P7 misdiagnosis — the wallpaper failure was a container-only Hyprland config-reload timeout, fixed in the test harness; the shell renders fine on 0.2.1 with the unmodified upstream `Background.qml`). We vendor anyway because Fedora's package has been frozen since Feb 2026 across every branch incl. rawhide, while omarchy develops against rolling quickshell and is adopting 0.3.0 APIs (networking service + polkit integration, released 2026-05-04). On the most UX-critical package, tracking what omarchy targets is worth one spec. The byte-identity + L4 visual tests would also catch a future Fedora-version break loudly, so this is a deliberate get-ahead, not a forced move. Recipe adapted from Fedora's own `quickshell.spec`; built `-DCRASH_HANDLER=OFF` (`cpptrace` not in Fedora 44; the only alternative `-DVENDOR_CPPTRACE=ON` fetches at build time and would fail COPR's offline mock build). See `install/packages/fedora.toml` `[quickshell]`. |
