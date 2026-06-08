# Set default XCompose that is triggered with CapsLock
#
# The XCompose payload omedora writes (built below). Captured into a variable so
# the Fedora path can compare it against an existing ~/.XCompose before clobbering.
xcompose_payload="$(
  cat <<EOF
# Run omarchy-restart-xcompose to apply changes

# Include fast emoji access
include "%H/.local/share/omarchy/default/xcompose"

# Identification
<Multi_key> <space> <n> : "$OMARCHY_USER_NAME"
<Multi_key> <space> <e> : "$OMARCHY_USER_EMAIL"
EOF
)"

# On Fedora, omedora installs onto a lived-in machine, so back up an existing
# ~/.XCompose (with the user's own Compose customizations) before overwriting it.
# Only back up when it exists AND differs from what we're about to write, using
# the same .pre-omedora-<ts> convention as omedora-seed-config. On Arch this is
# byte-identical to upstream omarchy (unconditional tee, no backup).
if [[ "$(omarchy-distro 2>/dev/null || echo arch)" == "fedora" ]]; then
  if [[ -f ~/.XCompose ]] && ! printf '%s\n' "$xcompose_payload" | cmp -s - ~/.XCompose; then
    ts="$(date +%s)"
    cp -f ~/.XCompose ~/.XCompose.pre-omedora-"$ts"
    echo -e "\033[33momedora: backed up your existing ~/.XCompose to ~/.XCompose.pre-omedora-$ts before overwriting\033[0m"
  fi
  printf '%s\n' "$xcompose_payload" | tee ~/.XCompose >/dev/null
else
  tee ~/.XCompose >/dev/null <<EOF
# Run omarchy-restart-xcompose to apply changes

# Include fast emoji access
include "%H/.local/share/omarchy/default/xcompose"

# Identification
<Multi_key> <space> <n> : "$OMARCHY_USER_NAME"
<Multi_key> <space> <e> : "$OMARCHY_USER_EMAIL"
EOF
fi
