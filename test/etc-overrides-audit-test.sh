#!/bin/bash
#
# L1 audit: the omedora/omedora-settings specs must never package or scriptlet
# files at the forbidden /etc paths.
#
# Upstream's omarchy-settings "etc-overrides" model cp -f's package copies over
# /etc files owned by other packages (os-release, nsswitch, skel .bashrc,
# faillock, cups, plymouth) on every upgrade. Omedora rejects that on Fedora —
# those files belong to the distro and the user; we ship reference copies under
# /usr/share/omarchy/etc-overrides/ and change behavior only through additive,
# omarchy-namespaced drop-ins (plus generic-path configs like docker's
# daemon.json being applied only-if-absent by plan-gated install scripts).
#
# This test statically audits the two core specs so a future rebase can't
# silently re-grow the upstream behavior: no %files entry, no install line
# targeting %{buildroot}/etc/<forbidden>, and no scriptlet writing to /etc.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"

SPECS=(
  "$ROOT/omedora/packaging/copr/omedora.spec"
  "$ROOT/omedora/packaging/copr/omedora-settings.spec"
)

# Forbidden /etc destinations (anchored under /etc or %{_sysconfdir}).
# Generic user-editable paths (docker, gnupg) are included: they ship as
# reference copies and get applied only-if-absent at install time instead.
FORBIDDEN=(
  'os-release'
  'nsswitch.conf'
  'skel/.bashrc'
  'security/faillock.conf'
  'pam.d'
  'cups'
  'plymouth'
  'docker/daemon.json'
  'gnupg'
  'sddm'
)

for spec in "${SPECS[@]}"; do
  [[ -f $spec ]] || fail "spec exists: $spec"
  name=$(basename "$spec")

  for path in "${FORBIDDEN[@]}"; do
    # Any line that targets the path under an /etc root — %files entries
    # (%{_sysconfdir}/..., /etc/...) or %install lines
    # (%{buildroot}%{_sysconfdir}/...). Reference-copy installs under
    # etc-overrides/ and comments are fine.
    if grep -E "(%\{_sysconfdir\}|%\{buildroot\}/etc|^/etc| /etc)/${path//./\\.}" "$spec" \
        | grep -vE '^\s*#' | grep -vq 'etc-overrides'; then
      grep -nE "(%\{_sysconfdir\}|/etc)/${path//./\\.}" "$spec" | head -3 >&2
      fail "$name does not touch /etc/$path"
    fi
    pass "$name does not touch /etc/$path"
  done

  # Scriptlets must not write into /etc at all (no cp/install/sed/tee/> into
  # /etc). Extract %post/%posttrans/%pre/%preun/%postun bodies and scan them.
  scriptlets=$(awk '/^%(post|posttrans|pre|preun|postun|pretrans)([[:space:]]|$)/{f=1;next} /^%/{f=0} f' "$spec" | grep -vE '^\s*#' || true)
  if printf '%s\n' "$scriptlets" | grep -qE '(cp|install|tee|sed|>|>>)[^#]*( |=)/etc/'; then
    printf '%s\n' "$scriptlets" | grep -E '/etc/' >&2
    fail "$name scriptlets do not write to /etc"
  fi
  pass "$name scriptlets do not write to /etc"
done

echo "# all etc-overrides audit checks passed"
