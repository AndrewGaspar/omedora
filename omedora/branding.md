# Branding

This doc covers omedora's brand surface: where "Omedora" appears, where "Omarchy" stays, and the rules contributors and agents follow when adding new user-facing strings or assets.

The brand split is deliberate and conservative — the goal is to make the omedora identity visible to end-users (so they don't blame Omarchy for omedora-specific behavior) without renaming any of the 318 `omarchy-*` files (which would be a rebase disaster).

For the technical mechanism that makes the rebrand work, see [`architecture.md` §10](architecture.md#10-cli-rebrand-tactical).

---

## 1. Brand-surface map

### Where "Omedora" appears

| Surface | Source | Notes |
| --- | --- | --- |
| **Display manager session entry** | `default/wayland-sessions/omedora.desktop` → installed to `/usr/share/wayland-sessions/` | The `Name=Omedora` field is the entire user touchpoint here. |
| **Dispatcher help text** | `bin/omarchy` `show_main_help`, `show_commands_help`, `show_command_help`, error/suggestion paths — substituted via `${BRAND_NAME}` when brand=omedora | Including the literal "Omedora command center" header. |
| **Command examples in `--help` output** | `bin/omarchy` `examples_as_lines` rendering — `omarchy` literal substituted to `omedora` | Each subcommand metadata stays unchanged on disk. |
| **Suggestion lines** ("Did you mean: omedora …?") | `bin/omarchy` `suggest_command` rendering | Same substitution. |
| **Version banner** | `bin/omarchy-version` | When brand=omedora, prints `Omedora <version> (rebased on Omarchy <upstream>)`. |
| **Screensaver / `omarchy show logo`** | `omedora/branding/logo.txt` (OMEDORA wordmark) | `bin/omarchy-show-logo` and `bin/omarchy-branding-screensaver` swap path to omedora's logo on Fedora. |
| **Install bootstrap banner** | `boot-omedora.sh` (new) or brand-aware `boot.sh` | When invoked as the omedora bootstrap, the ASCII banner is OMEDORA. |
| **Install logs** | Stage banners (e.g., "Update system packages" in `omarchy-update-fedora-pkgs`) | Use "omedora" branding in new Fedora-side install scripts. Existing Arch scripts keep their "Omarchy" wording. |
| **First-run notifications** | `install/first-run/welcome.sh` (Arch) — Fedora needs its own equivalent or a brand-aware version | Use the brand variable if patching, or skip if not needed for v1. |
| **GitHub repo, README, project name** | `omedora/README.md`, repo metadata | Self-evidently "Omedora." |

### Where "Omarchy" stays

| Surface | Reason |
| --- | --- |
| `bin/omarchy-*` filenames | Renaming all 318 files = rebase carnage. |
| The `omarchy` command itself (still on PATH) | Users coming from Omarchy can keep typing `omarchy`; everything works. |
| Code comments, helper headers (`# omarchy:summary=`, etc.) | Internal contract. Not user-facing. |
| `$OMARCHY_PATH`, `$OMARCHY_INSTALL`, `$OMARCHY_BIN_DIR`, `$OMARCHY_BRAND` env vars | Internal API; tons of scripts read these. |
| `$HOME/.local/share/omarchy/`, `$HOME/.config/omarchy/`, `$HOME/.local/state/omarchy/` | Filesystem paths users may scripts against; renaming would break them. |
| The root `AGENTS.md` | Upstream Omarchy's contributor guide. Untouched. |
| The root `logo.txt`, `icon.txt`, `logo.svg`, `icon.png` | Upstream assets. omedora's are siblings under `omedora/branding/`. |
| The root `version` file | Upstream version. Omedora's version is at `omedora/version`. |
| GitHub Actions / CI labels (if any) | Untouched. |

### Borderline: where the brand is the *distro's* and we don't need to surface ours

| Surface | Notes |
| --- | --- |
| Hyprland version, package versions, system info | `fastfetch` / `inxi` / `neofetch` show what they show. We don't try to overlay "Omedora" onto the OS identity — the OS is Fedora. |
| GTK/Qt theme names | Theming is independent of the omedora brand. |
| Browser bookmarks, default apps | User-owned. |

---

## 2. Rules for contributors and agents

When you add a new user-facing string:

1. **Route it through the brand variable.** If you're patching `bin/omarchy` itself, use `${BRAND_NAME}`. If you're writing a Fedora-side install script, hardcode `omedora` (it only runs on Fedora). If you're writing a portable script that runs on both distros, default to `${OMARCHY_BRAND:-$(omarchy-distro | sed 's/arch/omarchy/; s/fedora/omedora/')}` or similar — but this is rare; most install scripts are distro-side.
2. **Don't rename internal identifiers.** Helper command names, env vars, filesystem paths all stay `omarchy-`. There is no `omedora-pkg-add` command, only `omarchy-pkg-add` (reachable also as `omedora pkg add` via the dispatcher).
3. **Keep upstream files unchanged where possible.** Add new files for omedora-specific behavior rather than patching upstream ones with brand strings.
4. **Don't add brand strings to migration files, theme files, or config files.** Those are user data and upstream territory. The brand belongs to the dispatcher and install layer.

When you add a new asset (image, ASCII, .desktop entry):

1. **Put it under `omedora/branding/` or `default/wayland-sessions/`.** Don't shadow upstream's root `logo.txt` / `icon.txt`.
2. **Match upstream's design language.** The ASCII logo uses the same figlet idiom; the .desktop entry uses the same Exec line as Hyprland's standard; the install banners use the same color codes and width as upstream's.
3. **Don't introduce new visual identity without discussion.** If we want a different color, font, or wordmark, that's a deliberate brand decision, not a casual contribution.

---

## 3. The ASCII logo

The omedora logo (`omedora/branding/logo.txt`) is designed to be:

- **Visually continuous with upstream's OMARCHY logo.** Same height (10 lines), same stroke width, same `▄▀█` figlet idiom.
- **Glyph-reusing.** O, M, R, A glyphs are copied byte-for-byte from upstream's `logo.txt`. We only had to design new E and D glyphs to spell OMEDORA.
- **Single-color terminal-safe.** Renders in `\033[32m` (green, same as `omarchy-show-logo` uses).

Design rationale per glyph:

- **O, R, A** — copied from upstream OMARCHY positions 1, 4, 7. Identical placement of strokes.
- **M** — copied from upstream OMARCHY position 2. The ▄▄▄ notch above the wordmark stays (it's the M's apex).
- **E** — new. Follows the same vertical-stroke + crossbar pattern as A, with the crossbar on the same row as A's. Right side is empty (no closing stroke), so the letter reads as E and not B/F/H.
- **D** — new. Follows O's outline (left stroke + top + bottom curves + right stroke) but with the top-left corner squared off and the right side curving down from top-right to bottom-right. Mirrors C's open-right shape but with a closing right stroke instead.

When refining the logo, render it side-by-side with upstream's:

```bash
echo "==== UPSTREAM ===="; cat $OMARCHY_PATH/logo.txt
echo "==== OMEDORA ===="; cat $OMARCHY_PATH/omedora/branding/logo.txt
```

…and tune column alignment until both sit on the same baseline visually.

The `omedora/branding/icon.txt` is **not** introduced in the base commit — the existing `icon.txt` (a generic abstract square mark with no letterforms) is brand-agnostic enough to reuse. If a follow-up commit decides the icon should also carry the Omedora identity, that's a separate, opt-in change.

---

## 4. The `boot.sh` banner

`boot.sh` embeds the OMARCHY ASCII banner inline. For omedora-bootstrapped installs, the banner should read OMEDORA.

Two options for the patch:

**Option A (preferred):** Add a `boot-omedora.sh` shim that:

1. Sets `OMARCHY_BRAND=omedora`.
2. Sets `OMARCHY_REPO=<omedora-fork-org>/omedora` (so the clone pulls our fork, not upstream).
3. Sources `boot.sh`.

And patch `boot.sh` itself to:

1. Read `$OMARCHY_BRAND` at the top.
2. If `omedora`, read the banner from `omedora/branding/logo.txt` (after the repo is cloned, since the banner-print happens before the clone — so the banner for omedora must be inlined into `boot-omedora.sh` itself before the source).

**Option B:** Inline a second `ansi_art_omedora` variable in `boot.sh` and pick which to print based on `$OMARCHY_BRAND`.

Option A is cleaner (omedora's banner lives in `omedora/branding/`, the source of truth) but requires inlining the banner into `boot-omedora.sh` for the pre-clone display. The 12-line ASCII fits comfortably inside a shell script. This is the recommended approach.

---

## 5. The `--version` line

`bin/omarchy-version` currently just `cat $OMARCHY_PATH/version`. Patched behavior:

```bash
if [[ $(omarchy-distro) == "fedora" || $OMARCHY_BRAND == "omedora" ]]; then
  echo "Omedora $(cat "$OMARCHY_PATH/omedora/version")"
  echo "  (rebased on Omarchy $(cat "$OMARCHY_PATH/version"))"
else
  cat "$OMARCHY_PATH/version"
fi
```

The two-line output is intentional. It makes it explicit which upstream version omedora is currently rebased onto, which is exactly the information a user needs when reporting bugs or asking "is my install up to date with upstream?"

---

## 6. Brand-discipline checklist

When reviewing a patch, ask:

- [ ] Are all new user-facing strings routed through `${BRAND_NAME}` (or hardcoded `omedora` if Fedora-only)?
- [ ] Did the patch avoid renaming any `omarchy-*` file?
- [ ] Did the patch avoid touching `$OMARCHY_PATH`, `$OMARCHY_INSTALL`, or any internal env var?
- [ ] Did the patch avoid adding `omedora` to a code comment or helper header?
- [ ] Did the patch leave the upstream root assets (`logo.txt`, `icon.txt`, `version`, `LICENSE`) byte-for-byte unchanged?
- [ ] Did the patch update [`architecture.md`'s patch-stack map](architecture.md#15-patch-stack-map) if any new file was added?

If any answer is "no," consider whether the patch can be reshaped to a "yes." If it genuinely can't, document the deviation in the commit body and update this doc.
