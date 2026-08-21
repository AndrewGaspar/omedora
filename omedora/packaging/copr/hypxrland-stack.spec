# hypxrland-stack.spec — complete Fedora runtime dependency set for Omedora XR.

Name:           hypxrland-stack
Version:        1.1.0
Release:        1%{?dist}
Summary:        Complete HypXRland runtime stack for Fedora

License:        MIT
URL:            https://github.com/omedora/omedora
Source0:        hypxrland-stack.README

BuildArch:      noarch

Requires:       hypxrland >= 0.56.2^20260821.2.git67200a838-1
Requires:       hypxrcompose >= 0^20260820.1.gitf75ccd4ec-1
Requires:       hypxrhud >= 0^20260817.1.gitf96d0e794-1
Requires:       hypxrpaper >= 0^20260704.1.git5cae848cd-1
Requires:       hypxrva >= 0^20260803.1.gitbba2c5f8b-1
Requires:       hypxrvoice >= 0^20260812.1.git7ce7d33b2-1
Requires:       hypxrvoice-model-base-en >= 1.0.0-1
Requires:       wivrn-hypxr >= 26.6.2^20260820.1.git3729c7b31-1
Suggests:       monado-xreal >= 25.1.0^20260719.1.git3752d437c-2

%description
Dependency-only package for the Fedora HypXRland runtime: the parallel
compositor, patched WiVRn server, voice daemon and base English model, shared
HUD, VA-API decode gate, ambient background client, and offline .hypxrtake
compositor. The specialized XREAL Air Monado runtime remains an explicit
opt-in.

%prep
# Nothing to unpack; Source0 is the installed stack handoff document.

%build
# Dependency-only noarch package.

%install
install -Dpm0644 %{SOURCE0} \
  %{buildroot}%{_pkgdocdir}/README

%files
%doc %{_pkgdocdir}/README

%changelog
* Fri Aug 21 2026 omedora <noreply@omedora> - 1.1.0-1
- Add hypxrcompose to the mandatory Fedora runtime stack.
- Pin minimum EVRs for every component so stale COPR packages cannot satisfy
  the refreshed stack metadata.

* Wed Aug 12 2026 omedora <noreply@omedora> - 1.0.0-2
- Refresh the installed handoff document for Omedora 4 and Quattro.

* Tue Aug 11 2026 omedora <noreply@omedora> - 1.0.0-1
- Initial complete Fedora runtime meta-package.
- Keep the hardware-specific XREAL Monado runtime opt-in.
