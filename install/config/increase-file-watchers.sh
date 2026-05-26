# Increase inotify file watchers for VS Code, webpack, and other dev tools (default 8192 is too low)
echo "fs.inotify.max_user_watches=524288" | sudo tee /etc/sysctl.d/90-omarchy-file-watchers.conf >/dev/null
# `sysctl --system` fails inside unprivileged containers (the kernel parameter
# is read-only in the container's namespace). Tolerate the failure — the
# .conf file is what counts; settings apply on next boot.
sudo sysctl --system >/dev/null 2>&1 || true
