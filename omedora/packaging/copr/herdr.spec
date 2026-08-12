# herdr.spec — Omarchy's pinned terminal workspace manager fork.
#
# COPR-only toolchain exception: upstream requires exact Zig 0.15.2, while
# Fedora 44 has moved on. The checksum-pinned official binary is used only as
# a build tool and is not shipped; a future zig015 compatibility RPM can
# replace it.

%global commit 0766aa57ee0ceb4410ae064e94c0f0557853eee7
%global shortcommit %(c=%{commit}; echo ${c:0:7})
%global zig_version 0.15.2

Name:           herdr
Version:        0.8.0^13.git%{shortcommit}
Release:        1%{?dist}
Summary:        Terminal workspace manager for coding agents

License:        Apache-2.0 AND MIT AND BSD-3-Clause AND Unicode-3.0 AND 0BSD AND (0BSD OR Apache-2.0) AND (0BSD OR MIT OR Apache-2.0) AND (Apache-2.0 OR BSL-1.0) AND (Apache-2.0 OR MIT) AND (Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT) AND (BSD-2-Clause OR Apache-2.0) AND (MIT OR Apache-2.0) AND (MIT OR Zlib OR Apache-2.0) AND (Unlicense OR MIT) AND Zlib AND (Zlib OR Apache-2.0 OR MIT)
URL:            https://github.com/omacom-io/herdr
Source0:        https://codeload.github.com/omacom-io/herdr/tar.gz/%{commit}#/%{name}-%{version}.tar.gz
Source1:        %{name}-%{version}-vendor.tar.zst
Source2:        https://ziglang.org/download/%{zig_version}/zig-x86_64-linux-%{zig_version}.tar.xz
Source3:        %{name}-%{version}-zig-cache.tar.zst
# uucode's Zig package manifest omits the third-party notice directory even
# though its compiled sources and Unicode data refer to it. Pin the notices to
# the exact uucode 0.2.0 commit used by the generated Zig cache.
Source4:        https://raw.githubusercontent.com/jacobsandlund/uucode/54d650cf37948552f0c3d8168903e5e8a16901b8/licenses/LICENSE_Bjoern_Hoehrmann#/LICENSE.uucode-Bjoern-Hoehrmann
Source5:        https://raw.githubusercontent.com/jacobsandlund/uucode/54d650cf37948552f0c3d8168903e5e8a16901b8/licenses/LICENSE_unicode#/LICENSE.uucode-Unicode
Patch0:         herdr-libvt-only.patch
Source6:        https://raw.githubusercontent.com/simdutf/simdutf/ca7acbcea967b5dcbab490066e99e3a6e6925539/LICENSE-MIT#/LICENSE.simdutf-MIT
Source7:        https://raw.githubusercontent.com/simdutf/simdutf/ca7acbcea967b5dcbab490066e99e3a6e6925539/LICENSE-APACHE#/LICENSE.simdutf-Apache-2.0
Source8:        https://raw.githubusercontent.com/simdutf/simdutf/ca7acbcea967b5dcbab490066e99e3a6e6925539/include/simdutf/internal/isadetection.h#/LICENSE.simdutf-BSD-3-Clause

ExclusiveArch:  x86_64

BuildRequires:  cargo
BuildRequires:  rust
BuildRequires:  cargo-rpm-macros >= 24
BuildRequires:  gcc
Obsoletes:      omarchy-herdr < %{version}-%{release}
Conflicts:      omarchy-herdr

%description
Herdr is a persistent terminal workspace manager for supervising multiple
coding-agent sessions. This package follows Omarchy's pinned fork and embeds
its vendored terminal engine using the exact Zig toolchain required upstream.

%prep
%autosetup -n %{name}-%{commit} -p1
%setup -q -T -D -a 1 -n %{name}-%{commit}
%setup -q -T -D -a 2 -n %{name}-%{commit}
%setup -q -T -D -a 3 -n %{name}-%{commit}
rm -f rust-toolchain.toml
%cargo_prep -v cargo-vendor

%build
export ZIG="$PWD/zig-x86_64-linux-%{zig_version}/zig"
export ZIG_GLOBAL_CACHE_DIR="$PWD/zig-cache"
export LIBGHOSTTY_VT_OPTIMIZE=ReleaseFast
%cargo_build
%{cargo_license_summary}
%{cargo_license} > LICENSE.dependencies
%{cargo_vendor_manifest}

%install
install -D -m 0755 target/release/herdr %{buildroot}%{_bindir}/herdr
install -D -m 0644 vendor/libghostty-vt/LICENSE \
  %{buildroot}%{_licensedir}/%{name}/LICENSE.libghostty-vt
install -D -m 0644 vendor/portable-pty/LICENSE.md \
  %{buildroot}%{_licensedir}/%{name}/LICENSE.portable-pty
install -m 0644 \
  zig-cache/p/uucode-0.2.0-*/LICENSE.md \
  %{buildroot}%{_licensedir}/%{name}/LICENSE.uucode-0.2.0
install -m 0644 \
  zig-cache/p/N-V-__8AAGmZh*/LICENSE \
  %{buildroot}%{_licensedir}/%{name}/LICENSE.highway-Apache-2.0
install -m 0644 \
  zig-cache/p/N-V-__8AAGmZh*/LICENSE-BSD3 \
  %{buildroot}%{_licensedir}/%{name}/LICENSE.highway-BSD-3-Clause
install -m 0644 %{SOURCE4} %{SOURCE5} %{buildroot}%{_licensedir}/%{name}/
install -m 0644 %{SOURCE6} %{SOURCE7} %{SOURCE8} %{buildroot}%{_licensedir}/%{name}/

%check
export ZIG="$PWD/zig-x86_64-linux-%{zig_version}/zig"
export ZIG_GLOBAL_CACHE_DIR="$PWD/zig-cache"
%{buildroot}%{_bindir}/herdr --help >/dev/null

%files
%license LICENSE
%license LICENSE.dependencies
%license cargo-vendor.txt
%license %{_licensedir}/%{name}/LICENSE.libghostty-vt
%license %{_licensedir}/%{name}/LICENSE.portable-pty
%license %{_licensedir}/%{name}/LICENSE.uucode-0.2.0
%license %{_licensedir}/%{name}/LICENSE.highway-Apache-2.0
%license %{_licensedir}/%{name}/LICENSE.highway-BSD-3-Clause
%license %{_licensedir}/%{name}/LICENSE.uucode-Bjoern-Hoehrmann
%license %{_licensedir}/%{name}/LICENSE.uucode-Unicode
%license %{_licensedir}/%{name}/LICENSE.simdutf-MIT
%license %{_licensedir}/%{name}/LICENSE.simdutf-Apache-2.0
%license %{_licensedir}/%{name}/LICENSE.simdutf-BSD-3-Clause
%doc README.md CHANGELOG.md
%{_bindir}/herdr

%changelog
* Wed Aug 12 2026 omedora <noreply@omedora> - 0.8.0^13.git0766aa5-1
- Package the exact Omarchy beta fork and commit from source.
- Build offline with vendored Cargo dependencies, Ghostty terminal sources,
  Zig 0.15.2, and a prefilled immutable Zig package cache.
