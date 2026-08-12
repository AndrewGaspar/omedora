# hypxrland-stack.spec — complete Fedora runtime dependency set for Omedora XR.

Name:           hypxrland-stack
Version:        1.0.0
Release:        2%{?dist}
Summary:        Complete HypXRland runtime stack for Fedora

License:        MIT
URL:            https://github.com/omedora/omedora
Source0:        hypxrland-stack.README

BuildArch:      noarch

Requires:       hypxrland
Requires:       hypxrhud
Requires:       hypxrpaper
Requires:       hypxrva
Requires:       hypxrvoice
Requires:       hypxrvoice-model-base-en
Requires:       wivrn-hypxr
Suggests:       monado-xreal

%description
Dependency-only package for the Fedora HypXRland runtime: the parallel
compositor, patched WiVRn server, voice daemon and base English model, shared
HUD, VA-API decode gate, and ambient background client. The specialized XREAL
Air Monado runtime remains an explicit opt-in.

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
* Wed Aug 12 2026 omedora <noreply@omedora> - 1.0.0-2
- Refresh the installed handoff document for Omedora 4 and Quattro.

* Tue Aug 11 2026 omedora <noreply@omedora> - 1.0.0-1
- Initial complete Fedora runtime meta-package.
- Keep the hardware-specific XREAL Monado runtime opt-in.
