# Test image for omedora L2 (container integration) and L3 (smoke) tests.
#
# See omedora/testing.md §5 for design rationale.
#
# Build:  docker build -t omedora-test:fedora44 -f test/fedora/Dockerfile test/fedora/
# Run L2: docker run --rm -v "$PWD:/repo" omedora-test:fedora44 \
#           bash /repo/test/fedora/integration.sh

FROM registry.fedoraproject.org/fedora:44

# Install prereqs in one layer. dnf-plugins-core gives us `dnf copr enable`;
# everything else is what omedora's helpers + tests need.
RUN dnf install -y --setopt=install_weak_deps=False \
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
        sudo \
    && dnf clean all

# Warm the dnf metadata cache so the first `dnf install` inside a test isn't
# a cold network fetch. Saves 5-30s per test run.
RUN dnf makecache --refresh

# Create a non-root user for L3 smoke tests that need real sudo. L2 tests
# run as root for speed (sudo is a no-op there).
RUN useradd --create-home --uid 1000 --shell /bin/bash --groups wheel omedora \
    && printf '%%wheel ALL=(ALL) NOPASSWD: ALL\n' >/etc/sudoers.d/wheel-nopasswd \
    && chmod 0440 /etc/sudoers.d/wheel-nopasswd

# Default: drop into a shell at /repo (tests bind-mount the repo there).
WORKDIR /repo
CMD ["/bin/bash"]
