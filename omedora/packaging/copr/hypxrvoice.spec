# hypxrvoice.spec — local voice-control daemon for HypXRland.

%global snapshot 20260812.1
%global commit 7ce7d33b20a3ddc37e9f758b57a60a2d0849fbdd
%global shortcommit %(c=%{commit}; echo ${c:0:9})
%global whisper_commit 080bbbe85230f624f0b52127f1ae1218247989f9
%global llama_commit 961e4b26a7dd0e01e20599b27d709a74788ecb55

Name:           hypxrvoice
Version:        0^%{snapshot}.git%{shortcommit}
Release:        1%{?dist}
Summary:        Local-first voice control daemon for HypXRland

# Project code, whisper.cpp and llama.cpp are BSD-3-Clause/MIT as noted.
License:        BSD-3-Clause AND MIT
URL:            https://github.com/AndrewGaspar/hypxrvoice
Source0:        %{url}/archive/%{commit}/%{name}-%{commit}.tar.gz
Source1:        https://github.com/ggml-org/whisper.cpp/archive/%{whisper_commit}/whisper.cpp-%{whisper_commit}.tar.gz
Source2:        https://github.com/ggml-org/llama.cpp/archive/%{llama_commit}/llama.cpp-%{llama_commit}.tar.gz
Source3:        hypxrvoiced-session
Source4:        hypxrvoiced.service

ExclusiveArch:  x86_64

BuildRequires:  cmake
BuildRequires:  dbus-daemon
BuildRequires:  gcc
BuildRequires:  gcc-c++
BuildRequires:  ninja-build
BuildRequires:  systemd-rpm-macros
BuildRequires:  pkgconfig(jansson)
BuildRequires:  pkgconfig(libpipewire-0.3)
BuildRequires:  pkgconfig(libspa-0.2)
BuildRequires:  pkgconfig(sndfile)
BuildRequires:  pkgconfig(libsystemd)

Requires:       hypxrhud%{?_isa} >= 0^20260817.1.gitf96d0e794-1
Requires:       hypxrvoice-model-base-en >= 1.0.0-1
Recommends:     espeak-ng

Provides:       bundled(llama.cpp)
Provides:       bundled(whisper.cpp)

%description
HypXRVoice captures a local PipeWire source, transcribes speech with
whisper.cpp, resolves allowlisted HypXRland actions, and presents feedback
through HypXRHUD. The deterministic rule intent backend is the safe default;
the optional llama.cpp backend is compiled in but requires a separately
configured GGUF model.

The packaged service uses a per-user config when present and otherwise falls
back to the packaged example configured for the base.en model. The example
keeps command execution in dry-run mode.

%prep
%autosetup -n hypxrvoice-%{commit} -p1
tar -xf %{SOURCE1}
tar -xf %{SOURCE2}
rmdir subprojects/whisper.cpp subprojects/llama.cpp
mv whisper.cpp-%{whisper_commit} subprojects/whisper.cpp
mv llama.cpp-%{llama_commit} subprojects/llama.cpp
cp subprojects/whisper.cpp/LICENSE LICENSE.whisper.cpp
cp subprojects/llama.cpp/LICENSE LICENSE.llama.cpp

%build
%cmake \
  -GNinja \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF \
  -DHYPXRVOICE_LLAMA=ON \
  -DHYPXRHUD_BIN=%{_bindir}/hypxrhud
%cmake_build

%install
%cmake_install
install -Dpm0755 %{SOURCE3} %{buildroot}%{_bindir}/hypxrvoiced-session
install -Dpm0644 %{SOURCE4} %{buildroot}%{_userunitdir}/hypxrvoiced.service
install -d %{buildroot}%{_datadir}/hypxrvoice
sed '0,/^model = ""/{s|^model = "".*|model = "%{_datadir}/hypxrvoice/models/ggml-base.en.bin"|}' \
  examples/config.toml > %{buildroot}%{_datadir}/hypxrvoice/config.toml

%check
bash -n %{SOURCE3}
%ctest --exclude-regex hypxrvoice_hud_dbus_tests
awk '
  /^\[asr\]$/ { section = "asr"; next }
  /^\[intent\]$/ { section = "intent"; next }
  section == "asr" && /^model = / {
    asr = ($0 == "model = \"%{_datadir}/hypxrvoice/models/ggml-base.en.bin\"")
  }
  section == "intent" && /^model = / { intent = ($0 ~ /^model = ""/) }
  END { exit !(asr && intent) }
' %{buildroot}%{_datadir}/hypxrvoice/config.toml
! ldd %{buildroot}%{_bindir}/hypxrvoiced | \
  grep -E 'lib(ggml|llama|whisper).*not found'

%post
%systemd_user_post hypxrvoiced.service

%preun
%systemd_user_preun hypxrvoiced.service

%postun
%systemd_user_postun hypxrvoiced.service

%files
%license LICENSE LICENSE.whisper.cpp LICENSE.llama.cpp
%doc README.md examples/config.toml
%{_bindir}/hypxrvoiced
%{_bindir}/hypxrvoicectl
%{_bindir}/hypxrvoiced-session
%{_userunitdir}/hypxrvoiced.service
%dir %{_datadir}/hypxrvoice
%{_datadir}/hypxrvoice/config.toml

%changelog
* Wed Aug 12 2026 omedora <noreply@omedora> - 0^20260812.1.git7ce7d33b2-1
- Refresh to the current public master tip with natural monitor visibility
  phrases in both rule and local-LLM intent paths.
- Populate only the ASR model, leave the optional intent model empty, and
  assert both values by section during the package check.

* Wed Aug 12 2026 omedora <noreply@omedora> - 0^20260802.1.git9e899bbff-2
- Configure only the ASR model in the packaged example; leave the optional
  intent LLM unset and assert both sections during the build.

* Sun Aug 02 2026 omedora <noreply@omedora> - 0^20260802.1.git9e899bbff-1
- Initial public-tip snapshot with pinned whisper.cpp and llama.cpp sources.
- Add a packaged user service and a safe dry-run fallback configuration.
- Link the vendored inference libraries statically into the daemon.
