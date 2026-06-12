# omedora: on Fedora, back up an existing ~/.XCompose (the user's own Compose
# customizations on a lived-in machine) before overwriting — same
# .pre-omedora-<ts> convention as omedora-seed-config, only when it exists AND
# differs. Disclosed at the install plan gate. The Arch path below is
# byte-identical to upstream (unconditional tee, no backup). Ported from the
# 3.8.2 install/config/xcompose.sh gate.
if [[ "${OMARCHY_DISTRO:-$(omarchy-distro 2>/dev/null || echo arch)}" == "fedora" ]]; then
  xcompose_payload="$(
    cat <<EOF
# Run omarchy-restart-xcompose to apply changes

# Include fast emoji access
include "/usr/share/omarchy/default/xcompose"

# Identification
<Multi_key> <space> <n> : "$OMARCHY_USER_NAME"
<Multi_key> <space> <e> : "$OMARCHY_USER_EMAIL"
EOF
  )"
  if [[ -f ~/.XCompose ]] && ! printf '%s\n' "$xcompose_payload" | cmp -s - ~/.XCompose; then
    ts="$(date +%s)"
    cp -f ~/.XCompose ~/.XCompose.pre-omedora-"$ts"
    echo -e "\033[33momedora: backed up your existing ~/.XCompose to ~/.XCompose.pre-omedora-$ts before overwriting\033[0m"
  fi
  printf '%s\n' "$xcompose_payload" >~/.XCompose
  return 0 2>/dev/null || exit 0
fi

# Set default XCompose that is triggered with CapsLock
tee ~/.XCompose >/dev/null <<EOF
# Run omarchy-restart-xcompose to apply changes

# Include fast emoji access
include "/usr/share/omarchy/default/xcompose"

# Identification
<Multi_key> <space> <n> : "$OMARCHY_USER_NAME"
<Multi_key> <space> <e> : "$OMARCHY_USER_EMAIL"
EOF
