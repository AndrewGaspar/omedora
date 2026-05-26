# syntax=docker/dockerfile:1
# Omedora-in-Docker session image — L4-nested per omedora/testing.md §6.
#
# Two-stage:
#   Stage 1: install Omedora end-to-end (runs install.sh as the omedora user).
#   Stage 2 (the default CMD): boot Hyprland via Wayland-on-Wayland nesting.
#
# Status: work-in-progress. The install.sh end-to-end run is the iteration
# loop right now — each failure produces a fix (map entry, gate, Fedora
# sibling script) and we re-build.
#
# Build (depends on omedora-test:fedora44 being built first):
#   docker build -t omedora-test:fedora44 -f test/fedora/Dockerfile test/fedora/
#   docker build -t omedora-test:fedora44-session \
#     -f test/fedora/omedora-session/Dockerfile .
#
# (Note: the build context is the repo root because install.sh expects
# the full omedora tree.)
#
# Iteration cycle time: dnf downloads are cached in a BuildKit cache mount
# (target=/var/cache/dnf) so subsequent rebuilds reuse the ~5 GB of package
# RPMs instead of re-fetching. The dnf install step inside install.sh sees
# the cache because it's mounted across the whole RUN.

FROM omedora-test:fedora44

USER root

# install.sh expects the omedora tree at ~/.local/share/omarchy and uses
# OMARCHY_PATH to find itself. Bake the tree into the image so the install
# is reproducible (no bind-mount required at build time).
RUN mkdir -p /home/omedora/.local/share && \
    chown -R omedora:omedora /home/omedora/.local

COPY --chown=omedora:omedora . /home/omedora/.local/share/omarchy

# install.sh's presentation.sh helper sources stty on /dev/tty under `set -e`.
# In a non-interactive docker RUN there's no controlling terminal, so stty
# exits non-zero and kills the install before any work happens. Workaround:
# wrap install.sh with `script`, which allocates a pseudo-TTY. (This mirrors
# what omarchy-update does internally for the same reason.) `util-linux`
# provides `script`; pre-install if not already present.
RUN --mount=type=cache,target=/var/cache/dnf,sharing=locked \
    printf 'keepcache=True\n' >>/etc/dnf/dnf.conf && \
    dnf install -y --setopt=install_weak_deps=False util-linux-script

# Drop in a systemctl shim that no-ops the enable/disable/start/restart
# calls install.sh sprinkles around. (The container doesn't run systemd as
# PID 1; the real systemctl would fail on these.) Real session boot uses a
# different image with --systemd=true or equivalent.
COPY test/fedora/omedora-session/systemctl-shim.sh /usr/local/bin/systemctl
RUN chmod 0755 /usr/local/bin/systemctl

# install.sh's logger writes to /var/log/omarchy-install.log. Pre-create
# with omedora ownership so the install can append without sudo.
RUN install -d -o omedora -g omedora /var/log && \
    install -m 0664 -o omedora -g omedora /dev/null /var/log/omarchy-install.log

# install.sh expects passwordless sudo for many config steps. The base
# image already provisioned omedora into the wheel group with NOPASSWD;
# verify here.
RUN getent group wheel | grep -q omedora && \
    grep -q 'NOPASSWD' /etc/sudoers.d/wheel-nopasswd

# Run the install as the unprivileged omedora user. The install pipeline
# enters preflight (Fedora arm), packaging (dnf installs from the map),
# config (most steps; hardware/* gated off), then stops — login/ and
# post-install/ are also gated off on Fedora.
USER omedora
WORKDIR /home/omedora

ENV HOME=/home/omedora \
    USER=omedora \
    LOGNAME=omedora \
    OMARCHY_PATH=/home/omedora/.local/share/omarchy \
    OMARCHY_INSTALL=/home/omedora/.local/share/omarchy/install \
    OMARCHY_CHROOT_INSTALL=1 \
    OMARCHY_NONINTERACTIVE=1 \
    PATH=/home/omedora/.local/share/omarchy/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin

# Run install.sh under a pseudo-TTY (via `script`) so the stty-on-/dev/tty
# checks in install/helpers/presentation.sh don't fail under set -e.
#
# /var/cache/dnf is cache-mounted so re-builds reuse package downloads. Inside
# install.sh, omarchy-pkg-add → bin/fedora/pkg.py → sudo dnf install lands in
# the same /var/cache/dnf, so the cache works across the whole install.
#
# Two-RUN pattern: this RUN ALWAYS succeeds (recording exit code to a file).
# The next RUN reads that file and fails-with-tail. BuildKit caps each step's
# log stream at ~2MB; the "fail and tail" step gets a fresh budget, so the
# last ~1.5MB of install.log shows up on failure even if the install RUN's
# stream was clipped.
RUN --mount=type=cache,target=/var/cache/dnf,sharing=locked \
    script -qefc "bash $OMARCHY_INSTALL/../install.sh" /tmp/install.log >/dev/null; \
    echo $? > /tmp/install.exit; \
    exit 0

# Inspect the install result. Two log files exist:
#   /tmp/install.log              — full PTY capture (dominated by gum's
#                                    live-redraw spam; mostly useless)
#   /var/log/omarchy-install.log  — clean per-script stdout/stderr that
#                                    run_logged appends to (the GOOD log)
# We inspect the clean log: print all lifecycle events, then ~400 lines of
# context around the LAST per-script log section to surface the actual
# command output that triggered the failure.
RUN install_exit=$(cat /tmp/install.exit); \
    if (( install_exit != 0 )); then \
      echo ""; \
      echo "================================================================"; \
      echo "=== install.sh failed (exit $install_exit)"; \
      echo "================================================================"; \
      echo ""; \
      clean=/var/log/omarchy-install.log; \
      if [[ ! -s "$clean" ]]; then \
        echo "(no $clean — falling back to /tmp/install.log)"; \
        clean=/tmp/install.log; \
      fi; \
      echo "--- Last 60 lifecycle events (Starting/Completed/Failed) ---"; \
      grep -aE '^\[20[0-9]{2}-[0-9]{2}-[0-9]{2} [0-9:]+\] (Starting|Completed|Failed):' "$clean" | tail -60 || true; \
      echo ""; \
      echo "--- Last 400 lines of clean per-script log ---"; \
      tail -400 "$clean" | sed -E 's/\x1b\[[0-9;?]*[mGKsuHJh]//g; s/\x1b\][^\x07]*(\x07|\x1b\\)//g; s/\r/\n/g'; \
      exit "$install_exit"; \
    fi; \
    echo "install.sh succeeded"

# Default CMD: boot a nested Omedora session.
#
# Nesting trick (per omedora/testing.md §6): Hyprland's wayland backend
# (AQ_BACKENDS=wayland) makes Hyprland a Wayland *client* of the host's
# compositor instead of talking to DRM/KMS directly. The host's Wayland
# socket is bind-mounted in by run-session.sh; the script below points
# Hyprland at it.
#
# Run via test/fedora/run-session.sh from the host (handles the socket
# bind, /dev/dri share, and render/video group propagation).
CMD ["bash", "/home/omedora/.local/share/omarchy/test/fedora/omedora-session/boot-session.sh"]
