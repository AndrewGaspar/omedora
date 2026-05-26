# Setup sudo-less controls for controlling brightness on Apple Displays.
# Skip if asdcontrol isn't installed — the sudoers entry would just point
# at a non-existent binary.
if command -v asdcontrol >/dev/null 2>&1 || [[ -x /usr/bin/asdcontrol ]]; then
  echo "$USER ALL=(ALL) NOPASSWD: /usr/bin/asdcontrol" | sudo tee /etc/sudoers.d/asdcontrol
  sudo chmod 440 /etc/sudoers.d/asdcontrol
fi
