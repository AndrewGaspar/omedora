# syntax=docker/dockerfile:1
# Test image for omedora L2 (container integration) and L3 (smoke) tests.
#
# See omedora/testing.md §5 for design rationale.
#
# Build:  docker build -t omedora-test:fedora44 -f test/fedora/Dockerfile test/fedora/
# Run L2: docker run --rm -v "$PWD:/repo" omedora-test:fedora44 \
#           bash /repo/test/fedora/integration.sh
#
# dnf downloads are cached in a BuildKit cache mount so iterative rebuilds
# don't re-fetch packages from mirrors. Cache survives across `docker build`
# invocations but is NOT baked into the image. `keepcache=True` is dropped
# into dnf.conf before each cache-mounted dnf call so the cache actually
# persists rpms (default is keepcache=False, which deletes after install).
# NOTE: Fedora 44 ships dnf5, which caches packages under /var/cache/libdnf5
# (not the dnf4 /var/cache/dnf) — the cache mount MUST target the dnf5 path or
# it stays empty and every rebuild re-downloads.

FROM registry.fedoraproject.org/fedora:44

# Install prereqs in one layer. dnf-plugins-core gives us `dnf copr enable`;
# everything else is what omedora's helpers + tests need.
RUN --mount=type=cache,target=/var/cache/libdnf5,sharing=locked \
    printf 'keepcache=True\n' >>/etc/dnf/dnf.conf && \
    dnf install -y --setopt=install_weak_deps=False \
        dnf-plugins-core \
        git \
        gum \
        jq \
        python3 \
        flatpak \
        shellcheck \
        findutils \
        which \
        procps-ng \
        diffutils \
        sudo

# Warm the dnf metadata cache so the first `dnf install` inside a test isn't
# a cold network fetch. Saves 5-30s per test run.
RUN --mount=type=cache,target=/var/cache/libdnf5,sharing=locked \
    dnf makecache --refresh

# Create a non-root user for L3 smoke tests that need real sudo. L2 tests
# run as root for speed (sudo is a no-op there).
RUN useradd --create-home --uid 1000 --shell /bin/bash --groups wheel omedora \
    && printf '%%wheel ALL=(ALL) NOPASSWD: ALL\n' >/etc/sudoers.d/wheel-nopasswd \
    && chmod 0440 /etc/sudoers.d/wheel-nopasswd

# Default: drop into a shell at /repo (tests bind-mount the repo there).
WORKDIR /repo
CMD ["/bin/bash"]
