# voxtype.spec — voice dictation for Linux (peteonrails' Rust/whisper.cpp tool).
#
# BINARY-REPACKAGE + SUBPACKAGE SPLIT (mirrors lazygit.spec for the repackage
# shape). Upstream ships ONE official Fedora RPM that bundles every backend
# variant under /usr/lib/voxtype/ (~327 MB): whisper CPU (avx2/avx512) + Vulkan,
# ONNX CPU (avx2/avx512), and the heavyweight ONNX-GPU runtimes — NVIDIA CUDA
# (~390 MB, libonnxruntime_providers_cuda.so alone is 205 MB) and AMD MIGraphX.
#
# We re-emit that payload as THREE packages from the one source so a desktop
# install stays slim and nobody pulls CUDA without an NVIDIA GPU:
#   voxtype           — wrapper + config + systemd + whisper(avx2/avx512/vulkan)
#                       + ONNX-CPU(avx2/avx512). ~165 MB. Vulkan gives GPU accel
#                       for the Whisper engine on ANY vendor.
#   voxtype-cuda      — NVIDIA ONNX-CUDA backend (cuda-12 + cuda-13 trees). Opt-in.
#   voxtype-migraphx  — AMD ROCm/MIGraphX ONNX backend. Opt-in.
# The Fedora installer (bin/fedora/voxtype-install-pkg) auto-detects the GPU and
# adds the matching add-on; everyone else gets the base only.
#
# There is NO %build — upstream shipped the binaries. %install extracts the
# upstream RPM and the %files stanzas carve it into the three packages. The
# /usr/bin/voxtype wrapper picks voxtype-{vulkan,avx512,avx2} at runtime with
# `[ -x ... ]` guards, so the GPU trees living in subpackages can't break base.
#
# Verified (readelf): the ONNX-CPU binaries statically bundle onnxruntime (no
# libonnxruntime.so NEEDED), so the shared libonnxruntime.so under cuda-13/ is a
# CUDA-only dependency and travels with voxtype-cuda. Upstream declares no CUDA
# Requires (onnxruntime dlopens the providers), so we set AutoReqProv:no on the
# GPU subpackages to avoid generating unsatisfiable libcuda*/librocm* deps; the
# base keeps auto-deps on (its NEEDED — libstdc++/libasound/libgcc/libvulkan —
# all resolve in Fedora 44).

Name:           voxtype
Version:        0.7.5
Release:        1%{?dist}
Summary:        Voice dictation for Linux (whisper.cpp; CPU + Vulkan)

License:        MIT
URL:            https://github.com/peteonrails/voxtype

# Source0 is upstream's official Fedora RPM release asset. `spectool -g` (run by
# our build scripts) downloads it into SOURCES/; voxtype.spec.sources pins its
# sha256 (the supply-chain gate).
Source0:        %{url}/releases/download/v%{version}/voxtype-%{version}-1.x86_64.rpm

# Prebuilt x86_64 binaries.
ExclusiveArch:  x86_64

# systemd-rpm-macros supplies %%{_userunitdir} (the upstream RPM ships
# voxtype.service under /usr/lib/systemd/user). No other BuildRequires: there's no
# compile step, and rpm-build provides rpm2cpio/cpio for the %install extraction.
BuildRequires:  systemd-rpm-macros

# Prebuilt binaries: no debuginfo to generate, and we must NOT strip them (keep
# upstream's released binaries byte-for-byte). Leave the dependency generator ON
# for the base so its ELF sonames auto-resolve; build-id link processing off.
%global debug_package %{nil}
%global __strip /bin/true
%global _build_id_links none
# The vendored CUDA/MIGraphX provider .so files carry upstream's build-machine
# runpaths (/home/runner/..., /opt/rocm-*); onnxruntime dlopens them and resolves
# the real runtime at use time (exactly as upstream's RPM ships them), so we must
# NOT fail the build on them or mangle binaries we keep byte-for-byte.
#
# On Fedora 44 rpm the rpath QA check is emitted into the %%install scriptlet as an
# unconditional `QA_CHECK_RPATHS=1 ; check-rpaths` wrapper that ignores
# `%%{?__brp_check_rpaths}` (nilling that macro only drops the os_install_post copy,
# not this arch-install-post one). check-rpaths itself honours the QA_RPATHS env
# bitmask, so we export it from %%install (same shell as the wrapper) to ALLOW the
# two classes these upstream libs trigger: 0x0002 (invalid runpath, the absolute
# build-machine paths) + 0x0010 (empty runpath element from the trailing ':').
# We still nil __brp_check_rpaths to document intent + cover the os_install_post path.
%global __brp_check_rpaths %{nil}

# Base runtime deps. libstdc++/libasound(alsa-lib)/libgcc/libvulkan(vulkan-loader)
# are auto-detected from the binaries' NEEDED; curl (model download, exec'd not
# linked) and pipewire-alsa (ALSA->PipeWire routing for capture) are not, so list
# them explicitly. vulkan-loader is listed for clarity (also auto via libvulkan).
Requires:       curl
Requires:       pipewire-alsa
Requires:       vulkan-loader

%description
Voxtype is a fast, local, push-to-talk voice dictation tool for Linux built on
whisper.cpp. This package ships the CPU (AVX2/AVX-512) and Vulkan GPU whisper
variants plus the ONNX CPU variants; the /usr/bin/voxtype wrapper auto-selects
the best one for the host. Vulkan provides GPU acceleration on any vendor.

Install voxtype-cuda (NVIDIA) or voxtype-migraphx (AMD) for the optional
ONNX-GPU backends.

%package cuda
Summary:        NVIDIA CUDA ONNX-GPU backend for voxtype
Requires:       voxtype = %{version}-%{release}
# onnxruntime dlopens these providers and falls back if the CUDA runtime is
# absent, exactly as upstream's RPM does; don't hard-require the CUDA stack.
AutoReqProv:    no
%description cuda
Adds the NVIDIA CUDA execution-provider binaries (~390 MB) so the voxtype ONNX
engine can run on NVIDIA GPUs. Requires the NVIDIA driver + CUDA runtime at use
time; without them voxtype falls back to the CPU/Vulkan backends in the base
package.

%package migraphx
Summary:        AMD ROCm/MIGraphX ONNX-GPU backend for voxtype
Requires:       voxtype = %{version}-%{release}
AutoReqProv:    no
%description migraphx
Adds the AMD ROCm/MIGraphX execution-provider binaries so the voxtype ONNX
engine can run on AMD GPUs. Requires the ROCm runtime at use time; without it
voxtype falls back to the CPU/Vulkan backends in the base package.

%prep
# Nothing to unpack here — Source0 is an RPM; we extract it in %install.

%build
# Nothing to compile — upstream shipped the binaries.

%install
# Allow the upstream GPU provider libs' build-machine runpaths past rpm's
# arch-install-post check-rpaths wrapper (see the QA_RPATHS note in the preamble).
# Exported here so it's in scope when that wrapper runs after this %install body.
export QA_RPATHS=$(( 0x0002 | 0x0010 ))
# Extract the upstream RPM payload into the buildroot, then split via %files.
rpm2cpio %{SOURCE0} | (cd %{buildroot} && cpio -idm --quiet)
# Drop build-id links (we disable build-id processing; these would dangle).
rm -rf %{buildroot}/usr/lib/.build-id

%post
# Mirror upstream's only functional scriptlet: relabel for SELinux-enforcing
# hosts so the wrapper + variants are executable. Best-effort.
if command -v restorecon >/dev/null 2>&1; then
    restorecon -R %{_bindir}/voxtype %{_prefix}/lib/voxtype 2>/dev/null || true
fi

%files
%license %{_docdir}/voxtype/LICENSE
%doc %{_docdir}/voxtype/README.md
%{_bindir}/voxtype
%config(noreplace) %{_sysconfdir}/voxtype/config.toml
%{_userunitdir}/voxtype.service
%dir %{_prefix}/lib/voxtype
%{_prefix}/lib/voxtype/voxtype-avx2
%{_prefix}/lib/voxtype/voxtype-avx512
%{_prefix}/lib/voxtype/voxtype-vulkan
%{_prefix}/lib/voxtype/voxtype-onnx-avx2
%{_prefix}/lib/voxtype/voxtype-onnx-avx512
%{_datadir}/bash-completion/completions/voxtype
%{_datadir}/fish/vendor_completions.d/voxtype.fish
%{_datadir}/zsh/site-functions/_voxtype
%{_datadir}/voxtype/quickshell

%files cuda
%{_prefix}/lib/voxtype/cuda-12
%{_prefix}/lib/voxtype/cuda-13
%{_prefix}/lib/voxtype/voxtype-onnx-cuda-12
%{_prefix}/lib/voxtype/voxtype-onnx-cuda-13

%files migraphx
%{_prefix}/lib/voxtype/migraphx
%{_prefix}/lib/voxtype/voxtype-onnx-migraphx
%{_prefix}/lib/voxtype/voxtype-onnx-rocm

%changelog
* Tue Jun 16 2026 omedora <noreply@omedora> - 0.7.5-1
- Initial subpackaged binary-repackage of upstream voxtype 0.7.5: base
  (CPU + Vulkan + ONNX-CPU) plus opt-in voxtype-cuda / voxtype-migraphx.
