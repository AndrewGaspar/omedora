# voxtype.spec — push-to-talk voice dictation, FROM-SOURCE build of the
# AndrewGaspar/voxtype fork branch feat/muse-stack-v1.0.1 (v1.0.1 + Muse
# streaming-transcribe engine + OSD waiting/processing states).
#
# HISTORY: this spec used to binary-repackage upstream peteonrails/voxtype
# 0.7.5's official Fedora RPM (base + voxtype-cuda + voxtype-migraphx
# subpackages). The fork ships no release binaries, so we now compile from
# source, following the fork's own packaging/rpm/voxtype.spec build matrix.
#
# HERMETIC / VENDORED build (COPR-ready), same shape as satty.spec: COPR
# builds in mock where the rpmbuild phase has NO network, so we build fully
# offline against a `cargo vendor` tarball (Source1) of the fork's pinned
# Cargo.lock. `%%cargo_prep -v vendor` writes .cargo/config.toml with
# `[net] offline = true` + `[source.vendored-sources]`, so cargo never
# touches crates.io; a successful build proves every needed crate was
# vendored. build-local.sh generates Source1 deterministically at SRPM-gen
# time from the pinned Source0 below; it is NOT committed and NOT pinned in
# voxtype.spec.sources.
#
# Source0 is a COMMIT-PINNED GitHub archive of the fork branch (immutable for
# a given sha; same pattern as hyprland-preview-share-picker.spec's Source1).
# Bump %%fork_commit + the .sources pin together to move to a newer snapshot.
# NOTE: the fork tree ships a .cargo/config.toml containing only a cargo
# alias (xtask); %%cargo_prep's hermetic config takes precedence at build time.
#
# CPU-ONLY dep set (CUDA/ROCm dropped — offline-vendor risk, see below). The
# default cargo feature set builds the whisper.cpp engine (CPU tiers below)
# plus the always-built helpers (voxtype-osd launcher, voxtype-audio-bridge,
# voxtype-osd-quickshell launcher). The ort/parakeet/tokenizers crates ARE
# vendored as source but never COMPILED, so nothing needs the NVIDIA CUDA
# toolkit, ROCm, or onnxruntime's network-fetched prebuilt binaries.
# Consequences vs the old 0.7.5 binary package:
#   - voxtype-cuda / voxtype-migraphx subpackages are GONE. Those shipped
#     upstream's prebuilt ONNX-GPU provider .so trees; the fork builds those
#     engines only via network-fetched ort prebuilts + CUDA/ROCm toolchains,
#     neither available in COPR mock. GPU users keep Vulkan (whisper tier).
#   - ONNX-CPU engine variants (voxtype-onnx-avx2/avx512) are gone too: the
#     fork gates every ONNX engine (moonshine/sensevoice/paraformer/dolphin/
#     omnilingual/cohere/parakeet) behind optional cargo features whose ort
#     dependency resolves to network-fetched prebuilts, which cannot be
#     vendored offline. Revisit if ort gains a full-source vendor path or a
#     system-RPM provider. (MIGraphX was additionally broken upstream per
#     engine: Moonshine/SenseVoice/Paraformer/Dolphin/Omnilingual/Cohere all
#     document MIGraphX exclusions in Cargo.toml.)
#
# Tiered whisper binaries (same matrix as the fork's own RPM spec):
#   voxtype-avx2    — haswell baseline, AVX-512/GFNI disabled (no SIGILL)
#   voxtype-avx512  — native build for newer CPUs
#   voxtype-vulkan  — GPU accel via Vulkan (%%bcond_without vulkan to drop;
#                     needs vulkan-headers + glslc at build time for the
#                     whisper.cpp Vulkan shaders)
# %post symlinks /usr/bin/voxtype to the best tier (fork's own fragment).
# Unlike the fork's spec (which `cp`s tiers inside target/ then `cargo clean`s
# them away), each tier builds under its own CARGO_TARGET_DIR, so no tier
# clobbers another and no `cargo clean` is needed.
#
# OSD frontends shipped: quickshell launcher + QML tree (omedora's OSD path,
# resolved at /usr/share/voxtype/quickshell per voxtype_osd_quickshell.rs),
# audio-bridge sidecar, and voxtype-osd-gtk4 (%%bcond_without osd_gtk4 to drop
# if gtk4-layer-shell-devel is ever missing from the COPR chroot).
# voxtype-osd-native (wgpu) is NOT built (quickshell covers omedora);
# voxtype-mirror-registry is a build-tree-only R2 helper, never shipped.

%bcond_without osd_gtk4
%bcond_without vulkan

Name:           voxtype
Version:        1.0.1
Release:        1%{?dist}
Summary:        Voice dictation for Linux (whisper.cpp; CPU + Vulkan)

License:        MIT
URL:            https://github.com/peteonrails/voxtype
# Fork source: AndrewGaspar/voxtype branch feat/muse-stack-v1.0.1, pinned to
# the verified commit below (see .sources pin).
%global         fork_commit a51308e849c9ab224457d7e512ecd1b3cb2caf65
Source0:        https://github.com/AndrewGaspar/voxtype/archive/%{fork_commit}/%{name}-%{fork_commit}.tar.gz
# Source1: `cargo vendor` tarball of the fork's pinned Cargo.lock. NOT
# committed: build-local.sh generates it deterministically into SOURCES/ at
# SRPM-gen time. Unpacks to vendor/.
Source1:        %{name}-%{version}-vendor.tar.zst

# Compiled for x86_64 (tiered AVX2/AVX-512/Vulkan binaries are x86_64-only).
ExclusiveArch:  x86_64

# --- Build toolchain -------------------------------------------------------
BuildRequires:  cargo
BuildRequires:  rust
# cargo-rpm-macros provides %%cargo_prep / the license macros and the hermetic
# offline .cargo/config.toml seal. >= 24 has the -v vendor flag.
BuildRequires:  cargo-rpm-macros >= 24
# C/C++ toolchain for the vendored whisper.cpp build (whisper-rs) + linking.
BuildRequires:  gcc
BuildRequires:  gcc-c++
BuildRequires:  cmake
BuildRequires:  clang-devel
# cpal links ALSA for audio capture.
BuildRequires:  alsa-lib-devel
# pkg-config drives the -sys crates' library discovery.
BuildRequires:  pkgconf-pkg-config
# systemd-rpm-macros supplies %%{_userunitdir} + the %%systemd_user_* scriptlets.
BuildRequires:  systemd-rpm-macros
%if %{with vulkan}
# whisper.cpp Vulkan backend: headers + shader compiler + loader for linking.
BuildRequires:  vulkan-headers
BuildRequires:  vulkan-loader-devel
BuildRequires:  glslc
%endif
%if %{with osd_gtk4}
# C libraries the gtk4 / gtk4-layer-shell crates link against.
BuildRequires:  gtk4-devel
BuildRequires:  gtk4-layer-shell-devel
%endif

# --- Runtime ---------------------------------------------------------------
# libstdc++/libasound(alsa-lib)/libgcc are auto-detected from the binaries'
# NEEDED. curl is exec'd (not linked) by src/setup for model downloads and
# pipewire-alsa routes ALSA capture into PipeWire, so both stay explicit.
# vulkan-loader is listed for clarity (also auto via libvulkan); conditional
# on the vulkan tier.
Requires:       curl
Requires:       pipewire-alsa
%if %{with vulkan}
Requires:       vulkan-loader
%endif
# Text-output chain (same as the fork's own spec): wtype primary on Wayland,
# wl-clipboard fallback; ydotool/notify optional.
Recommends:     wtype
Recommends:     wl-clipboard
Suggests:       ydotool
Suggests:       libnotify
# OSD quickshell frontend needs the system quickshell runner at use time.
Recommends:     quickshell

%description
Voxtype is a fast, local, push-to-talk voice dictation tool for Linux built on
whisper.cpp. This package ships tiered CPU (AVX2/AVX-512) and Vulkan GPU
whisper binaries; the install-time symlink auto-selects the best one for the
host. It also ships the OSD helpers (quickshell launcher + QML, GTK4 OSD,
audio bridge) from the muse-stack fork, which adds a streaming-transcribe
engine and OSD waiting/processing states.

%prep
# Commit archive unpacks to voxtype-<sha>/.
%autosetup -n %{name}-%{fork_commit}
# Unpack the (build-time-generated) vendor tarball (creates ./vendor/), then
# have %%cargo_prep wire .cargo/config.toml to it with offline mode on.
%setup -q -T -D -a 1 -n %{name}-%{fork_commit}
%cargo_prep -v vendor

%build
# Offline builds against the vendored sources (no crates.io); each whisper
# tier gets its own target dir so no `cargo clean` can clobber a finished tier.
#
# AVX2 baseline (compatible with most CPUs from 2013+): disable AVX-512 and
# GFNI in both Rust code and whisper.cpp to prevent SIGILL on older CPUs.
# NOTE: -fPIC on the whisper.cpp objects is load-bearing, not cosmetic. The
# tier RUSTFLAGS pin target-cpu/haswell (not the distro default), so the cmake
# C/C++ flags here are the ONLY hardening the vendored ggml/whisper static
# libs get; without -fPIC their R_X86_64_32S relocations fail the PIE link
# (ld: "recompile with -fPIE"). -fPIC links cleanly into PIE and non-PIE alike.
RUSTFLAGS="-C target-cpu=haswell -C target-feature=-avx512f,-avx512bw,-avx512cd,-avx512dq,-avx512vl,-gfni" \
GGML_NATIVE=OFF GGML_AVX512=OFF \
CMAKE_C_FLAGS="-mno-avx512f -mno-gfni -fPIC" CMAKE_CXX_FLAGS="-mno-avx512f -mno-gfni -fPIC" \
CARGO_TARGET_DIR=%{_builddir}/target-avx2 \
cargo build --release --offline --locked --bin voxtype
cp %{_builddir}/target-avx2/release/voxtype %{_builddir}/voxtype-avx2

# AVX-512 optimized binary (for Zen 4+, some Intel).
CMAKE_C_FLAGS="-fPIC" CMAKE_CXX_FLAGS="-fPIC" \
CARGO_TARGET_DIR=%{_builddir}/target-avx512 \
cargo build --release --offline --locked --bin voxtype
cp %{_builddir}/target-avx512/release/voxtype %{_builddir}/voxtype-avx512

%if %{with vulkan}
# Vulkan GPU binary (GPU acceleration on any vendor).
RUSTFLAGS="-C target-cpu=haswell -C target-feature=-avx512f,-avx512bw,-avx512cd,-avx512dq,-avx512vl,-gfni" \
GGML_NATIVE=OFF GGML_AVX512=OFF \
CMAKE_C_FLAGS="-mno-avx512f -mno-gfni -fPIC" CMAKE_CXX_FLAGS="-mno-avx512f -mno-gfni -fPIC" \
CARGO_TARGET_DIR=%{_builddir}/target-vulkan \
cargo build --release --offline --locked --features gpu-vulkan --bin voxtype
cp %{_builddir}/target-vulkan/release/voxtype %{_builddir}/voxtype-vulkan
%endif

# Always-built helper binaries (no whisper tiers needed): OSD launcher,
# audio bridge, quickshell launcher, and the GTK4 OSD frontend.
cargo build --release --offline --locked \
%if %{with osd_gtk4}
  --features osd-gtk4 --bin voxtype-osd-gtk4 \
%endif
  --bin voxtype-osd --bin voxtype-audio-bridge --bin voxtype-osd-quickshell
# Record the bundled crates' licenses + manifest for the %license payload.
%{cargo_license_summary}
%{cargo_license} > LICENSE.dependencies
%{cargo_vendor_manifest}

%install
# Tiered whisper binaries to /usr/lib/voxtype/.
install -D -m 755 %{_builddir}/voxtype-avx2 %{buildroot}%{_libdir}/voxtype/voxtype-avx2
install -D -m 755 %{_builddir}/voxtype-avx512 %{buildroot}%{_libdir}/voxtype/voxtype-avx512
%if %{with vulkan}
install -D -m 755 %{_builddir}/voxtype-vulkan %{buildroot}%{_libdir}/voxtype/voxtype-vulkan
%endif

# Helper binaries to /usr/bin/.
install -D -m 755 target/release/voxtype-osd %{buildroot}%{_bindir}/voxtype-osd
install -D -m 755 target/release/voxtype-audio-bridge %{buildroot}%{_bindir}/voxtype-audio-bridge
install -D -m 755 target/release/voxtype-osd-quickshell %{buildroot}%{_bindir}/voxtype-osd-quickshell
%if %{with osd_gtk4}
install -D -m 755 target/release/voxtype-osd-gtk4 %{buildroot}%{_bindir}/voxtype-osd-gtk4
%endif

# Quickshell OSD tree (resolved at /usr/share/voxtype/quickshell).
mkdir -p %{buildroot}%{_datadir}/voxtype/quickshell
cp -a quickshell/*.qml %{buildroot}%{_datadir}/voxtype/quickshell/
cp -a quickshell/voxtype-shared %{buildroot}%{_datadir}/voxtype/quickshell/

# Default configuration.
install -D -m 644 config/default.toml %{buildroot}%{_sysconfdir}/voxtype/config.toml

# systemd user service.
install -D -m 644 packaging/systemd/voxtype.service \
  %{buildroot}%{_userunitdir}/voxtype.service

# Documentation + license.
install -D -m 644 README.md %{buildroot}%{_docdir}/%{name}/README.md
install -D -m 644 docs/INSTALL.md %{buildroot}%{_docdir}/%{name}/INSTALL.md
install -D -m 644 LICENSE %{buildroot}%{_licensedir}/%{name}/LICENSE

# Shell completions.
install -D -m 644 packaging/completions/voxtype.bash \
  %{buildroot}%{_datadir}/bash-completion/completions/voxtype
install -D -m 644 packaging/completions/voxtype.zsh \
  %{buildroot}%{_datadir}/zsh/site-functions/_voxtype
install -D -m 644 packaging/completions/voxtype.fish \
  %{buildroot}%{_datadir}/fish/vendor_completions.d/voxtype.fish

# Man pages generated by build.rs into each tier's OUT_DIR/man.
for m in %{_builddir}/target-*/release/build/voxtype-*/out/man/*.1 target/release/build/voxtype-*/out/man/*.1; do
  [ -f "$$m" ] || continue
  install -D -m 644 "$$m" "%{buildroot}%{_mandir}/man1/$$(basename $$m)"
done

# Configuration TUI launcher (.desktop entry + terminal-picker script).
install -D -m 644 packaging/voxtype-configure.desktop \
  %{buildroot}%{_datadir}/applications/voxtype-configure.desktop
install -D -m 755 packaging/scripts/voxtype-configure-launcher \
  %{buildroot}%{_bindir}/voxtype-configure-launcher

%check
# Smoke-test the offline-built binaries (arg-parse only; no audio/models).
%{_builddir}/voxtype-avx2 --version
%{_builddir}/target-avx512/release/voxtype --version
%if %{with vulkan}
%{_builddir}/target-vulkan/release/voxtype --version
%endif
target/release/voxtype-osd --help > /dev/null
target/release/voxtype-audio-bridge --help > /dev/null
target/release/voxtype-osd-quickshell --help > /dev/null
%if %{with osd_gtk4}
target/release/voxtype-osd-gtk4 --help > /dev/null
%endif

%post
%systemd_user_post voxtype.service

# Detect CPU capabilities and symlink the appropriate binary (fork's fragment).
rm -f %{_bindir}/voxtype

# Check for AVX-512 support (Linux-specific, falls back to AVX2)
if [ -f /proc/cpuinfo ] && grep -q avx512f /proc/cpuinfo 2>/dev/null; then
    VARIANT="avx512"
    ln -sf %{_libdir}/voxtype/voxtype-avx512 %{_bindir}/voxtype
else
    VARIANT="avx2"
    ln -sf %{_libdir}/voxtype/voxtype-avx2 %{_bindir}/voxtype
fi

# Restore SELinux context if available
if command -v restorecon >/dev/null 2>&1; then
    restorecon %{_bindir}/voxtype 2>/dev/null || true
fi

# Detect GPU for Vulkan acceleration recommendation
GPU_DETECTED=""
if [ -d /dev/dri ]; then
    if ls /dev/dri/renderD* >/dev/null 2>&1; then
        if command -v lspci >/dev/null 2>&1; then
            GPU_INFO=$(lspci 2>/dev/null | grep -i 'vga\|3d\|display' | head -1 | sed 's/.*: //')
            if [ -n "$GPU_INFO" ]; then
                GPU_DETECTED="$GPU_INFO"
            fi
        fi
        if [ -z "$GPU_DETECTED" ]; then
            GPU_DETECTED="GPU detected (install pciutils for details)"
        fi
    fi
fi

echo ""
echo "=== Voxtype Post-Installation ==="
echo ""
echo "CPU backend: $VARIANT (using voxtype-$VARIANT)"

if [ -n "$GPU_DETECTED" ]; then
    echo ""
    echo "GPU detected: $GPU_DETECTED"
    echo ""
    echo "  For GPU acceleration (faster inference), run:"
    echo "    sudo voxtype setup gpu --enable"
    echo ""
    echo "  Requires: vulkan-loader package"
fi

echo ""
echo "To complete setup:"
echo ""
echo "  1. Add your user to the 'input' group:"
echo "     sudo usermod -aG input \$USER"
echo ""
echo "  2. Log out and back in for group changes to take effect"
echo ""
echo "  3. Download a whisper model:"
echo "     voxtype setup --download"
echo ""
echo "  4. Start voxtype:"
echo "     systemctl --user enable --now voxtype"
echo ""

%preun
%systemd_user_preun voxtype.service

%postun
%systemd_user_postun_with_restart voxtype.service
# Remove symlink on package removal
rm -f %{_bindir}/voxtype

%files
%license %{_licensedir}/%{name}/LICENSE
# Aggregated dependency license info from the vendored crate tree.
%license LICENSE.dependencies
%license cargo-vendor.txt
%doc %{_docdir}/%{name}/README.md
%doc %{_docdir}/%{name}/INSTALL.md
%dir %{_prefix}/lib/voxtype
%{_prefix}/lib/voxtype/voxtype-avx2
%{_prefix}/lib/voxtype/voxtype-avx512
%if %{with vulkan}
%{_prefix}/lib/voxtype/voxtype-vulkan
%endif
# The /usr/bin/voxtype symlink is created by %post, mark as ghost.
%ghost %{_bindir}/voxtype
%{_bindir}/voxtype-osd
%{_bindir}/voxtype-audio-bridge
%{_bindir}/voxtype-osd-quickshell
%if %{with osd_gtk4}
%{_bindir}/voxtype-osd-gtk4
%endif
%dir %{_sysconfdir}/voxtype
%config(noreplace) %{_sysconfdir}/voxtype/config.toml
%{_userunitdir}/voxtype.service
%{_datadir}/bash-completion/completions/voxtype
%{_datadir}/zsh/site-functions/_voxtype
%{_datadir}/fish/vendor_completions.d/voxtype.fish
%{_mandir}/man1/voxtype*.1*
%dir %{_datadir}/voxtype
%{_datadir}/voxtype/quickshell
%{_datadir}/applications/voxtype-configure.desktop
%{_bindir}/voxtype-configure-launcher

%changelog
* Tue Sep 08 2026 omedora <noreply@omedora> - 1.0.1-1
- Switch from binary-repackage of upstream 0.7.5 to a from-source build of
  the AndrewGaspar/voxtype fork branch feat/muse-stack-v1.0.1 (pinned commit
  a51308e: v1.0.1 + Muse streaming-transcribe engine + OSD states), built
  fully offline against a cargo-vendor tarball of the fork's Cargo.lock.
- CPU-only dep set: voxtype-cuda / voxtype-migraphx subpackages and the
  ONNX-CPU engine variants are dropped (ort prebuilts + CUDA/ROCm toolchains
  are not available to offline COPR builds); GPU users keep the Vulkan tier.
- New in this build: OSD helpers (voxtype-osd launcher, audio bridge,
  quickshell launcher + QML tree, GTK4 OSD), man pages, configure-launcher
  desktop entry, and per-tier CARGO_TARGET_DIR builds (the fork spec's
  cp-then-cargo-clean matrix deleted finished tiers).
