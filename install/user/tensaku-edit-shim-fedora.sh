#!/bin/bash

# Fedora-only: provide tensaku-edit (Omarchy's screenshot / clipboard annotation
# editor) as a satty wrapper in ~/.local/bin.
#
# The quattro line replaced satty with the `tensaku` package, whose
# `tensaku-edit` binary omarchy-capture-screenshot, omarchy-clipboard-open and
# config/imv/config now invoke. omedora now packages tensaku natively (COPR;
# omedora/packaging/copr/tensaku.spec) which provides the real
# /usr/bin/tensaku-edit — but keeps satty and this thin satty wrapper
# (omedora/bin/tensaku-edit) as a FALLBACK. Install it into ~/.local/bin (on PATH
# via the Hyprland session env), only when a genuine tensaku-edit is absent (so
# the native tensaku build wins). Idempotent. See install/packages/fedora.toml
# [tensaku].

# Don't shadow a genuine tensaku-edit if one is ever installed. $OMEDORA_REAL_TENSAKU
# is a test seam.
[[ -f "${OMEDORA_REAL_TENSAKU:-/usr/bin/tensaku-edit}" ]] && return 0

shim="$OMARCHY_PATH/omedora/bin/tensaku-edit"
[[ -f $shim ]] || return 0

mkdir -p ~/.local/bin
install -m 0755 "$shim" ~/.local/bin/tensaku-edit
