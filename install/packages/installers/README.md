# Source installers — RETIRED

This directory once held per-package shell "source installers" for packages with
no Fedora repo, RPM Fusion, COPR, or Flathub presence. **That approach is
retired.** No source installers ship here, and new ones should not be added.

Packages that aren't anywhere in Fedora's ecosystem are now built as **RPMs**
under [`omedora/packaging/copr/`](../../../omedora/packaging/copr/) and served from the omedora
dnf repo (a local repo today, a published COPR later). Their
[`install/packages/fedora.toml`](../fedora.toml) entries use `source = "dnf"`
with the RPM package `names` — the same install path as a Fedora-shipped
package.

See [`omedora/packages.md` §4](../../../omedora/packages.md#4-the-rpmcopr-tier-omedorapackagingcopr)
for the RPM/COPR tier: spec conventions, the `build-local.sh` / `build-repo.sh`
scripts, and how to add a new packaged app.

This directory is kept only as a pointer; it has no other contents.
