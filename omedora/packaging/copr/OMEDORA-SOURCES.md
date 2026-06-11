# Source integrity pins (`<spec>.sources`)

Every spec in this directory that fetches a remote `SourceN` by URL ships a
committed sibling pin file, `<spec>.sources`, holding the **sha256** of each
remote source. `build-local.sh` fetches the sources (`spectool -g -R`) and then
verifies them against these pins **before** building, aborting the build on any
mismatch. This is the integrity anchor that GitHub/CDN URLs otherwise lack:

- For the **binary-repackage** specs (walker, lazygit, mise, elephant, fonts,
  claude-code, …) and the **C/C++ Hyprland** specs, the pin is the *only*
  integrity check on the upstream artifact.
- For the **Rust** specs (bluetui, satty, swayosd), it pins the upstream
  *tarball* — including its `Cargo.lock`. cargo's per-crate checksums already
  anchor every transitive crate; this pin anchors the lock file that drives
  them. (The locally generated `<name>-<version>-vendor.tar.zst` is **not**
  pinned: it is produced by `cargo vendor` at build time from this pinned
  Source0, not fetched.)

## Format

Plain `sha256sum -c` format — one line per remote source:

```
<sha256>  <fetched-basename>
```

`<fetched-basename>` is exactly the filename `spectool -g` writes into
`~/rpmbuild/SOURCES/`: for a `URL#/rename` source it is the part after `#/`;
otherwise it is the basename of the URL. Local (non-URL) sources — e.g.
`macros.hyprland`, or the generated `*-vendor.tar.zst` — are intentionally
**absent** (nothing remote to verify).

Multi-source specs list every remote source, e.g. `elephant.spec.sources` has
all ten release tarballs, `hyprland.spec.sources` has both the Hyprland release
tarball and the bundled Lua tarball, and
`hyprland-preview-share-picker.spec.sources` has the project tarball plus the
pinned hyprland-protocols submodule snapshot.

## How verification is wired

`build-local.sh`, right after `spectool -g -R`, reads `/copr/<spec>.sources` and
checks each fetched file's sha256. A mismatch (or a pinned file that wasn't
fetched) prints `SOURCE PIN MISMATCH` / `SOURCE PIN ERROR` with the filename and
expected-vs-got hashes and exits non-zero — the build never reaches `rpmbuild`.
A spec with no `.sources` file is skipped with a notice (safety net; every
remote-source spec here ships one).

## Re-pinning when a source legitimately changes

When you bump a `Version:` (or a pinned commit), the pin must be regenerated:

1. Fetch the new source(s) and compute their sha256, e.g. in the build image:
   `spectool -g -R <spec>` then
   `sha256sum ~/rpmbuild/SOURCES/<basename>`.
2. Replace the matching line(s) in `<spec>.sources`.
3. Commit the spec bump and the `.sources` change together.

### GitHub auto-generated tag archives — don't panic on a mismatch

The Hyprland-stack specs and several others use GitHub's
`archive/refs/tags/...` (and `archive/<tag>/...`) tarballs. These are
**usually byte-stable**, but GitHub has changed its archive compression once
historically, which would change the sha256 of an *unchanged* tag. If a pin
starts failing **without any version bump on our side**, that is the integrity
check doing its job — do **not** blindly re-pin. First confirm the *content* is
unchanged (extract old vs new and diff, or compare against an independently
recorded hash); only once you've verified it's the same source re-tarred should
you re-pin. The Rust crate set stays safe regardless (cargo's checksums); this
pin protects the tarball itself, including its `Cargo.lock`.
