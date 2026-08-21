# Branding

Omedora identifies the Fedora port to users without renaming Omarchy's internal
interfaces. This keeps bug reports clear while preserving a mechanically
rebasable tree.

## Omedora surfaces

| Surface | Source |
| --- | --- |
| Display-manager session | `omedora/packaging/copr/omedora.desktop`, packaged by `omedora-settings` |
| Version banner | `bin/omarchy-version` plus `omedora/{version,base-version}` |
| Wordmark/screensaver | `omedora/branding/logo.txt` |
| Bootstrap and install plan | `omedora/boot.sh` and `omedora/install-4.sh` |
| Fedora project documentation | root `README.md` and `omedora/*.md` |

The package-backed settings RPM installs the Omedora wordmark at the normal
runtime source path and seeds it for new users. Upstream's root assets remain
unchanged in git.

## Omarchy surfaces that remain

- `omarchy-*` command filenames and command metadata.
- `$OMARCHY_*` environment variables.
- `/usr/share/omarchy`, `~/.config/omarchy`, and Omarchy state paths.
- Dispatcher help and shared command descriptions, including through the
  `omedora` symlink. The dispatcher remains byte-identical to upstream.
- The `omarchy` command, which remains available beside the alias.
- Root `logo.txt`, `logo.svg`, `icon.txt`, `icon.png`, and `version`.
- Upstream manual content and links.

These are compatibility interfaces, not incomplete rebranding.

## Contributor rules

- Do not patch the shared dispatcher solely to replace Omarchy strings.
- Fedora-only scripts may say Omedora directly.
- Never rename an `omarchy-*` command, environment variable, or runtime path.
- Do not add branding to migrations, themes, or generic user configuration.
- Put Omedora-specific assets under `omedora/branding/` or the packaging source
  that owns their installed destination.
- Preserve the upstream root assets byte-for-byte; the byte-identity audit
  enforces this.

## Version wording

The Fedora version line is one line so it works in diagnostics and screenshots:

```text
Omedora 0.2.0-beta.2 (rebased on Omarchy 4.0.0)
```

The Omedora number identifies this port's release. The Omarchy number identifies
the official upstream compatibility base. The immutable commit and pin label
belong in maintainer diagnostics and release notes rather than the normal banner.

## Visual changes

Brand asset changes require the same visual verification as other desktop
changes. Capture and inspect an L4 screenshot before accepting a changed logo,
session presentation, or shell surface. A source rebase that merely changes
upstream wallpaper ordering must not silently replace the visual golden.
