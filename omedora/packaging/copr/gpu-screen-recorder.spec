# gpu-screen-recorder.spec — GPU-accelerated screen recorder (omedora).
#
# gpu-screen-recorder (git.dec05eba.com/gpu-screen-recorder, GPL-3.0-only, by
# dec05eba) is a C/C++ Wayland/X11 GPU-accelerated screen/replay recorder that
# encodes on the GPU via VAAPI / NVENC / Vulkan Video. omarchy's screen-record
# flow is hardcoded to this exact binary: bin/omarchy-capture-screenrecording
# launches `gpu-screen-recorder ...` and pkills `^gpu-screen-recorder`, and the
# Quickshell bar indicator (shell/plugins/bar/indicators/ScreenRecording.qml)
# `pgrep -f "^gpu-screen-recorder"`. Upstream omarchy pulls it from Arch; on the
# omedora (Fedora) port it was previously skip-mapped, so screen recording
# silently no-op'd. This spec builds it FROM SOURCE so the real binary exists and
# the upstream capture script/QML work byte-identically (nothing is patched).
#
# COPR-safe / offline %build: a plain C/C++ Meson build — every dependency comes
# from BuildRequires and %build touches no network (nothing to vendor, unlike our
# Rust specs). NVENC/CUDA are dlopen'd at RUNTIME (the NvEnc/NvFBC headers are
# bundled in external/), so there is NO CUDA build dep.
#
# ffmpeg: gsr encodes through VAAPI/NVENC/Vulkan, NOT libx264/libx265, so it
# builds against Fedora main's stripped **ffmpeg-free-devel** — it does NOT need
# RPM Fusion's full ffmpeg. That keeps this spec buildable on a stock Fedora COPR
# (no external repos required). Confirmed locally via build-local.sh on
# fedora:44 with only Fedora-main BuildRequires.
#
# PRIVILEGE / KMS capture: gsr ships a small helper binary `gsr-kms-server` that
# needs CAP_SYS_ADMIN to read the KMS framebuffer for monitor capture on
# amd/intel + nvidia-wayland (the main binary stays unprivileged and talks to the
# helper). It is a FILE CAPABILITY, not setuid. Upstream's meson would setcap at
# install time (-Dcapabilities=true), which fails under rpmbuild's fakeroot — so
# we build with -Dcapabilities=false and apply the capability in %post instead
# (mirrors the brycensranch/gpu-screen-recorder-git COPR spec). Without the cap,
# gsr falls back to a polkit prompt; NVIDIA / window / portal capture never need
# it.

Name:           gpu-screen-recorder
Version:        5.14.1
Release:        1%{?dist}
Summary:        GPU-accelerated screen/replay recorder (NVENC/VAAPI/Vulkan)

License:        GPL-3.0-only
URL:            https://git.dec05eba.com/gpu-screen-recorder/about

# Source0: upstream's cgit snapshot tarball for the version tag. build-local.sh
# (spectool -g) fetches it into SOURCES/ and verifies it against
# gpu-screen-recorder.spec.sources. The archive has NO top-level directory (files
# at the root), so %prep runs autosetup with -c to create one. The "#/" fragment
# renames the download to the conventional name-version tarball.
Source0:        https://dec05eba.com/snapshot/%{name}.git.%{version}.tar.gz#/%{name}-%{version}.tar.gz

# Compiled for x86_64 (the only arch omedora targets right now).
ExclusiveArch:  x86_64

# --- Build toolchain -------------------------------------------------------
# C + C++ compilers drive the Meson build.
BuildRequires:  gcc
BuildRequires:  gcc-c++
BuildRequires:  meson
BuildRequires:  pkgconfig
# ffmpeg dev headers (libavcodec/libavformat/libavutil/libswresample/libavfilter).
# Fedora main's stripped ffmpeg-free-devel suffices — gsr encodes via
# VAAPI/NVENC/Vulkan, not libx264 — so NO RPM Fusion is needed at build time.
BuildRequires:  ffmpeg-free-devel
# VAAPI (HW encode) + libva-drm.pc; DRM/KMS framebuffer access (gsr-kms-server).
BuildRequires:  pkgconfig(libva)
BuildRequires:  pkgconfig(libva-drm)
BuildRequires:  pkgconfig(libdrm)
# Vulkan Video encode path.
BuildRequires:  vulkan-headers
# CAP_SYS_ADMIN capability plumbing for gsr-kms-server (built against libcap).
BuildRequires:  pkgconfig(libcap)
# Wayland capture (wayland-client) + EGL on Wayland (wayland-egl -> libglvnd).
BuildRequires:  pkgconfig(wayland-client)
BuildRequires:  pkgconfig(wayland-egl)
BuildRequires:  pkgconfig(libglvnd)
# PulseAudio/PipeWire audio capture (-a).
BuildRequires:  pkgconfig(libpulse)
# X11 capture backend (X11 + the Composite/RandR/Fixes/Damage extensions).
BuildRequires:  pkgconfig(x11)
BuildRequires:  pkgconfig(xcomposite)
BuildRequires:  pkgconfig(xrandr)
BuildRequires:  pkgconfig(xfixes)
BuildRequires:  pkgconfig(xdamage)
# xdg-desktop-portal ScreenCast capture (-w portal) + single-app audio (-a app:),
# both default-on in upstream meson_options.txt: needs PipeWire + D-Bus.
BuildRequires:  pkgconfig(libpipewire-0.3)
BuildRequires:  pkgconfig(libspa-0.2)
BuildRequires:  pkgconfig(dbus-1)

# --- Runtime ---------------------------------------------------------------
# RPM auto-detects the binaries' link-time .so deps (ffmpeg-free-libs, libva,
# libdrm, pipewire, libglvnd, X libs, libpulse, libcap ...). setcap in %post
# comes from libcap; require it explicitly so the scriptlet's /usr/sbin/setcap
# is present.
Requires(post): libcap

%description
GPU Screen Recorder is a lightweight, GPU-accelerated screen recorder and
instant-replay tool for Wayland and X11. It encodes on the GPU (VAAPI on
AMD/Intel, NVENC on NVIDIA, or Vulkan Video), so CPU overhead is minimal even at
high resolutions and frame rates. It can capture a monitor, a region, a single
window, or an xdg-desktop-portal ScreenCast source, with optional
desktop/microphone audio and a webcam overlay. omedora uses it as the recording
engine behind `omarchy screenrecord` and the desktop bar's recording indicator.

%prep
# The snapshot tarball has no top-level directory, so -c creates
# gpu-screen-recorder-%{version}/ and extracts into it.
%autosetup -c -n %{name}-%{version}

%build
# -Dcapabilities=false: upstream's default would run setcap during `meson
# install`, which fails under rpmbuild's fakeroot. We disable that and apply the
# CAP_SYS_ADMIN file capability in %post instead. All other options stay at their
# defaults (systemd unit, nvidia suspend-fix modprobe drop-in, portal + app-audio
# capture all ON).
%meson -Dcapabilities=false
%meson_build

%install
%meson_install

%check
# Upstream defines no meson tests, so this is a trivial no-op; kept to mirror
# upstream and to catch a future test suite regressing the build.
%meson_test

# Grant gsr-kms-server the CAP_SYS_ADMIN file capability so KMS monitor capture
# on amd/intel + nvidia-wayland works without a polkit/password prompt. `|| :`
# keeps the scriptlet non-fatal on filesystems without capability support (the
# tool still works via its polkit fallback).
%post
setcap cap_sys_admin+ep %{_bindir}/gsr-kms-server || :

%files
%license LICENSE
%doc README.md
%{_bindir}/gpu-screen-recorder
%{_bindir}/gsr-kms-server
# Plugin dev header + capture helper scripts installed by upstream meson.
%{_includedir}/gsr/plugin.h
%{_datadir}/gpu-screen-recorder
# systemd user service (instant-replay/record daemon) + nvidia suspend-fix drop-in.
%{_userunitdir}/gpu-screen-recorder.service
%{_prefix}/lib/modprobe.d/gsr-nvidia.conf
%{_mandir}/man1/gpu-screen-recorder.1*
%{_mandir}/man1/gsr-kms-server.1*

%changelog
* Fri Jul 03 2026 omedora <noreply@omedora> - 5.14.1-1
- Initial from-source (Meson) build of gpu-screen-recorder
  (git.dec05eba.com/gpu-screen-recorder, GPL-3.0-only), the GPU-accelerated
  screen recorder omarchy's screenrecord flow + bar indicator are hardcoded to.
- Builds against Fedora main's ffmpeg-free-devel (VAAPI/NVENC/Vulkan encode, not
  libx264) — no RPM Fusion needed at build time.
- Ships /usr/bin/gpu-screen-recorder + the gsr-kms-server helper (granted
  CAP_SYS_ADMIN via %%post setcap; built with -Dcapabilities=false so rpmbuild's
  fakeroot install doesn't choke on meson's own setcap), the systemd user
  service, the nvidia suspend-fix modprobe drop-in, capture scripts, plugin
  header, and man pages.
