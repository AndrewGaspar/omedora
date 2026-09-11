# ttfx.spec — Quattro's terminal text-effects engine for Fedora.

Name:           ttfx
Version:        0.3.2
Release:        1%{?dist}
Summary:        Terminal text effects as a native Rust binary

License:        MIT AND (Apache-2.0 OR MIT) AND (Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT)
URL:            https://github.com/omacom-io/ttfx
Source0:        https://codeload.github.com/omacom-io/ttfx/tar.gz/refs/tags/v%{version}#/%{name}-%{version}.tar.gz
Source1:        %{name}-%{version}-vendor.tar.zst

ExclusiveArch:  x86_64

BuildRequires:  cargo
BuildRequires:  rust
BuildRequires:  cargo-rpm-macros >= 24
Obsoletes:      python3-terminaltexteffects < 0.15.1

%description
ttfx is a fast native Rust port of TerminalTextEffects. Quattro uses it for
the animated screensaver and first-run console presentation.

%prep
%autosetup -n %{name}-%{version}
%setup -q -T -D -a 1 -n %{name}-%{version}
%cargo_prep -v vendor

%build
%cargo_build
%{cargo_license_summary}
%{cargo_license} > LICENSE.dependencies
%{cargo_vendor_manifest}

%install
install -D -m 0755 target/release/ttfx %{buildroot}%{_bindir}/ttfx
install -d %{buildroot}%{_datadir}/bash-completion/completions
target/release/ttfx --print-completion bash \
  > %{buildroot}%{_datadir}/bash-completion/completions/ttfx
install -d %{buildroot}%{_datadir}/zsh/site-functions
target/release/ttfx --print-completion zsh \
  > %{buildroot}%{_datadir}/zsh/site-functions/_ttfx

%check
%cargo_test
%{buildroot}%{_bindir}/ttfx --help >/dev/null

%files
%license LICENSE
%license NOTICE
%license LICENSE.dependencies
%license cargo-vendor.txt
%doc README.md
%{_bindir}/ttfx
%{_datadir}/bash-completion/completions/ttfx
%{_datadir}/zsh/site-functions/_ttfx

%changelog
* Fri Sep 11 2026 omedora <noreply@omedora> - 0.3.2-1
- Update to 0.3.2: stop dumping core when the terminal goes away (upstream
  omacom-io/ttfx#18), fixing the SIGABRT on the idle-lock screensaver path.

* Wed Aug 12 2026 omedora <noreply@omedora> - 0.3.1-1
- Package Quattro's native terminal-effects engine from source.
- Build hermetically from the release Cargo.lock and ship shell completions.
