# Package mapping

This doc covers how omedora translates Omarchy's Arch-named package surface onto Fedora install sources. It defines:

- The **tiered fallback** rule that picks an install source for any given package.
- The **TOML schema** for `install/packages/fedora.toml`, the data file that overrides defaults.
- The **resolution algorithm** the helper commands follow when called with package names.
- **Worked examples** for each source tier.
- A **review checklist** for proposing new entries.

For the higher-level architecture, see [`architecture.md` §3–§4](architecture.md#3-package-helper-dispatch).

---

## 1. The five-tier strategy

When omedora installs a package on Fedora, it picks an install source in this order. Earlier tiers always win.

| # | Tier | Notes |
| --- | --- | --- |
| 1 | **Fedora main repos** (`dnf install <name>`) | Default. If the package name is unchanged from Arch, no map entry needed. If the name differs, the map provides the Fedora name. |
| 2 | **RPM Fusion** (`dnf install <name>` after RPM Fusion repos enabled in preflight) | For multimedia codecs and the handful of nonfree libs. Enable preflight already turns these on; from there it's just `dnf`. |
| 3 | **Vetted COPR** (`dnf copr enable <copr>` then `dnf install <name>`) | Allowed COPRs are an explicit allowlist. Right now: `lionheartp/Hyprland`. New COPRs require review (see [§6](#6-review-checklist)). |
| 4 | **Flathub** (`flatpak install -y flathub <app_id>`) | For proprietary or otherwise unpackaged GUI apps. Flathub remote is enabled in preflight. |
| 5 | **Source installer** (`bash install/packages/installers/<name>.sh`) | Last resort. A per-package shell script under `install/packages/installers/` that handles fetch, build, install, and (importantly) update on subsequent `omedora update` runs. |

**Why preference for earlier tiers:**

- Closer-to-distro tiers benefit from Fedora's update flow, signing, dependency resolution, SELinux contexts, and security patches.
- Each tier we descend introduces more failure modes (COPR maintainer disappearing, Flathub manifest drift, source installer rotting when upstream tag layout changes).
- The map is also a **trust boundary** — every COPR or Flathub manifest used must be reviewed.

**When to break the order:** rarely. Reasons that justify it:

- The Fedora main repo package is severely lagging (multiple major versions behind) and a COPR is current.
- The Flatpak version is functionally broken in the omedora desktop session (e.g., portal mismatch).
- The source installer is the *only* way to get a working build for a particular Fedora version.

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
| `source` | string | always | One of `dnf`, `copr`, `flathub`, `source`, `skip`. |
| `names` | array of string | `source ∈ {dnf, copr}` | The Fedora package name(s) to install. Multiple allowed when one Arch package fans out into several Fedora packages (e.g., a metapackage). |
| `copr` | string | `source = "copr"` | The COPR identifier (`owner/repo`) to enable before install. Must be on the allowlist (see [§6](#6-review-checklist)). |
| `app_id` | string | `source = "flathub"` | The Flathub app ID, e.g., `md.obsidian.Obsidian`. |
| `installer` | string | `source = "source"` | The filename (no path) of the installer under `install/packages/installers/`, e.g., `install-walker.sh`. |
| `reason` | string | `source = "skip"`; recommended elsewhere when the choice isn't obvious | One-line explanation. Lives in the file so reviewers and agents understand intent. |
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

# --- renamed packages ----------------------------------------------------

[ttf-jetbrains-mono-nerd]
source = "dnf"
names = ["jetbrains-mono-fonts-all"]

[ttf-ia-writer]
source = "flathub"
app_id = "io.github.ia-writer.fonts"   # placeholder; verify before shipping
reason = "iA Writer fonts not packaged on Fedora; Flathub is closest stable source."

# --- COPR-required packages ---------------------------------------------

[hyprland]
source = "copr"
copr = "lionheartp/Hyprland"
names = ["hyprland"]
reason = "Hyprland not in Fedora main repos as of F44. Check each release; promote to source='dnf' when absorbed."

[hyprlock]
source = "copr"
copr = "lionheartp/Hyprland"
names = ["hyprlock"]

# --- Flathub packages ---------------------------------------------------

[obsidian]
source = "flathub"
app_id = "md.obsidian.Obsidian"

[spotify]
source = "flathub"
app_id = "com.spotify.Client"

[typora]
source = "flathub"
app_id = "io.typora.Typora"
reason = "Proprietary; Flathub is the canonical install path on Fedora."

# --- Source-installed packages ------------------------------------------

[walker]
source = "source"
installer = "install-walker.sh"
reason = "Walker not in Fedora repos or trusted COPR; upstream provides static binaries."

# --- Explicitly skipped packages ----------------------------------------

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

# --- Version-conditional entries ----------------------------------------

[swayosd]
source = "dnf"
names = ["swayosd"]
until = "45"        # before F45, fall through to default which is also "dnf install swayosd"
reason = "Documented here so future agents see we've checked; same on F44 and F45+."
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
      dnf_install entry.names
    copr:
      ensure_copr_enabled entry.copr
      dnf_install entry.names
    flathub:
      flatpak_install --user flathub entry.app_id
    source:
      bash $OMARCHY_INSTALL/packages/installers/$entry.installer
    skip:
      log "Skipping <package_name> on Fedora: <entry.reason>"
      continue
```

Notes:

- Failures from `dnf install` are surfaced; the helper exits non-zero like upstream.
- Failures from `flatpak install` and source installers are also surfaced; we don't silently swallow them. The skip-with-log behavior is **only** for `source = "skip"` entries.
- Source installers are responsible for making themselves idempotent (re-running the installer should be a no-op when the version is current) and for advertising their installed version to the update flow (see [`update-and-upgrade.md`](update-and-upgrade.md)).

---

## 4. Source installer convention

Source installers live in `install/packages/installers/install-<name>.sh`. Each one:

1. Has no shebang (it's sourced via `bash <file>`).
2. Starts with a one-line `echo` describing what it's doing.
3. Reads `$OMARCHY_PATH` to find files relative to the omedora install.
4. Uses `omarchy-cmd-present` / `omarchy-cmd-missing` to decide whether to re-run.
5. Writes binaries into `~/.local/bin/` (user-level) or `/usr/local/bin/` (system-level, with sudo) — chosen per-package, not globally.
6. Writes its installed version into `~/.local/state/omedora/installed-versions/<name>` so the update flow can detect drift.
7. Cleans up any temp directories it creates.

Example skeleton:

```bash
# install-walker.sh — install Walker launcher from upstream releases

echo "Install Walker launcher"

VERSION_TAG="v0.10.3"   # update when bumping
INSTALL_DIR="$HOME/.local/bin"
STATE_FILE="$HOME/.local/state/omedora/installed-versions/walker"

mkdir -p "$INSTALL_DIR" "$(dirname "$STATE_FILE")"

if [[ -f $STATE_FILE && $(cat "$STATE_FILE") == "$VERSION_TAG" ]] && [[ -x "$INSTALL_DIR/walker" ]]; then
  echo "  Walker $VERSION_TAG already installed."
  return 0 2>/dev/null || exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' RETURN EXIT
# ... fetch, extract, install ...

echo "$VERSION_TAG" >"$STATE_FILE"
echo "  Installed walker $VERSION_TAG."
```

---

## 5. How to add a new entry

When upstream Omarchy adds a new package to `omarchy-base.packages` or to a feature install script, the patch-stack rebase will pull that change in. If the package is identically named in Fedora main repos, no map entry is needed and the install will succeed automatically. Otherwise:

1. **Search Fedora main repos first.** `dnf search <name>`. If found under a slightly different name, add a `source = "dnf"` entry with the `names` translation.
2. **If not in main, check RPM Fusion.** `dnf --enablerepo=rpmfusion-free,rpmfusion-nonfree search <name>`. Still uses `source = "dnf"` since RPM Fusion is enabled in preflight.
3. **If not in RPM Fusion, check the allowed COPRs.** Currently just `lionheartp/Hyprland`. If the package is there, add `source = "copr"` with the COPR identifier.
4. **If not in a vetted COPR, check Flathub.** Browse https://flathub.org/. If a maintained Flatpak exists, add `source = "flathub"` with the app ID.
5. **If none of the above, propose a source installer.** Flag the entry for human review in the commit body — this tier is for cases where there is no maintained packaging anywhere, and we accept the risk of vendoring an installer.
6. **If the package is fundamentally not appropriate on Fedora** (a kernel module, a bootloader component, an Arch-specific repo manager), use `source = "skip"` with a clear `reason`.

Every map entry change goes in a PR with the rationale in the commit body. Agents should record the reasoning in detail — future maintainers will read the commit history to understand why a tier choice was made.

---

## 6. Review checklist

Before merging a new map entry — agents and humans both run through this:

- [ ] **Tier choice justified.** Why this tier and not an earlier one? Note in `reason` or commit body.
- [ ] **For `source = "dnf"`:** Verify `dnf info <name>` succeeds on a clean Fedora 44 VM/container. Note the package version.
- [ ] **For `source = "copr"`:** The COPR must already be on the allowlist below. Adding a *new* COPR requires:
    - Documented maintainer (single individual or org).
    - Build history of at least 6 months with timely Fedora release support.
    - No history of disappearing or distributing modified upstream binaries.
    - A short note in this doc justifying why we trust it.
- [ ] **For `source = "flathub"`:** App ID matches a maintained Flathub listing. Verify it's not a community-mirror of a proprietary app with stale builds.
- [ ] **For `source = "source"`:** Installer follows the convention in [§4](#4-source-installer-convention). Specifically: idempotent, advertises version, cleans up.
- [ ] **For `source = "skip"`:** Reason is clear and durable (won't be obsoleted next Fedora release).
- [ ] **Patch-stack map updated.** If this is the first entry of its kind, the new file may need adding to `architecture.md`'s patch-stack map.
- [ ] **Tested.** Ran `omedora update` (or a fresh install) end-to-end on a Fedora 44 VM after the change.

### COPR allowlist

| COPR | Used for | Rationale |
| --- | --- | --- |
| `lionheartp/Hyprland` | Hyprland and its ecosystem (hypridle, hyprlock, hyprpaper, hyprpicker, xdg-desktop-portal-hyprland) when not present in Fedora main repos | Maintained Hyprland COPR with current Fedora 44 builds. Chosen over `solopasha/hyprland` (the historical default) because solopasha's builds were broken on Fedora 44 at the time omedora launched. Revisit each Fedora release. |

To add a new COPR: open a PR that (a) updates this allowlist with rationale, (b) adds the map entries that use it. Both reviewed together.

---

## 7. Validating the map

A planned helper command, `omarchy dev validate-fedora-packages`, parses `install/packages/fedora.toml` and reports:

- Entries with `source = "copr"` whose COPR isn't on the allowlist.
- Entries with `source = "source"` whose installer file doesn't exist.
- Entries with `source = "dnf"` whose `names` field is empty.
- Entries with `source = "flathub"` whose `app_id` is empty.
- Entries with `source = "skip"` missing `reason`.
- Entries with `since`/`until` that don't form a valid range.

This validator runs as part of the rebase verification step (see [`rebase-workflow.md`](rebase-workflow.md)) and ideally as a CI check. The base commit doesn't ship the validator — it's a follow-up implementation task — but the contract above is what it must enforce.

---

## 8. What the map deliberately doesn't do

- **It doesn't pin versions for `dnf`/`copr` sources.** Fedora and COPRs handle versioning; we don't reproduce a lockfile.
- **It doesn't model dependencies.** dnf and dnf-copr resolve dependencies themselves; same for Flatpak. Source installers handle their own deps.
- **It doesn't try to match Arch's optional-vs-required taxonomy.** Omarchy decides what to install via the install scripts; the map only handles translation, not policy.
- **It doesn't override upstream package selection.** If Omarchy adds a package to `omarchy-base.packages`, the map can route it to a tier, but only `source = "skip"` can prevent the install entirely — and skipping should have a clear, durable reason.
