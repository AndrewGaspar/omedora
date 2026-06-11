# terminaltexteffects.spec — the `tte` terminal visual-effects engine.
#
# Unlike walker/elephant (binary-repackage of prebuilt Go releases), this is a
# proper FROM-SOURCE Python build using Fedora's pyproject-rpm-macros. That is
# the idiomatic way to package a Python project on Fedora, and it is more
# hermetic than the Go specs: build deps come from dnf (via %%pyproject_buildrequires),
# and the only network fetch is the PyPI sdist (downloaded by `spectool -g`).
#
# Upstream is pure Python with ZERO runtime dependencies (the only declared
# extras are docs tooling, which we ignore). It ships two identical console
# scripts, `tte` and `terminaltexteffects`; omarchy/omedora invoke it as `tte`.
# %%pyproject_save_files captures both /usr/bin entry points automatically.

%global pypi_name terminaltexteffects

Name:           python3-%{pypi_name}
Version:        0.15.0
Release:        1%{?dist}
Summary:        Terminal visual effects engine (the `tte` command)

License:        MIT
URL:            https://github.com/ChrisBuilds/terminaltexteffects

# %%{pypi_source} expands to the files.pythonhosted.org sdist URL for
# %%{pypi_name}-%%{version}.tar.gz. `spectool -g` downloads it into SOURCES/.
Source0:        %{pypi_source}

# Pure-Python: no compiled extensions, so the package is architecture-independent.
BuildArch:      noarch

# python3-devel pulls the Python stack; pyproject-rpm-macros provides the
# %%pyproject_* macros used below.
BuildRequires:  python3-devel
BuildRequires:  pyproject-rpm-macros
# Upstream builds with the hatchling backend. %%pyproject_buildrequires below
# derives this dynamically at rpmbuild time, but our local build-local.sh does a
# single static `dnf builddep` pass (dnf5 doesn't execute %%generate_buildrequires
# from a spec), so we also name it statically. Harmless on a real COPR/mock,
# which runs the dynamic pass anyway. Keep in sync with pyproject.toml
# build-system.requires.
BuildRequires:  python3dist(hatchling)

%description
TerminalTextEffects (TTE) is a terminal visual effects engine. It applies
animated visual effects (slides, scrambles, rain, fireworks, and many more) to
text in the terminal, and is used by omarchy/omedora for animated terminal
output. The engine is exposed as the `tte` command.

%prep
%autosetup -n %{pypi_name}-%{version}

%generate_buildrequires
# Inspects the sdist's build-system (hatchling here) and emits its build deps
# as BuildRequires for dnf to install. With no runtime deps there is nothing
# else to pull in.
%pyproject_buildrequires

%build
%pyproject_wheel

%install
%pyproject_install
# Record the installed files (the importable package + both console scripts)
# into %%{pyproject_files} for the %%files section below.
%pyproject_save_files %{pypi_name}

%check
# Sanity-check that the module imports under the packaged interpreter.
%pyproject_check_import

%files -f %{pyproject_files}
%doc README.md
# Console scripts. %%pyproject_save_files already lists these, but naming them
# explicitly documents the package's user-facing entry points and guarantees
# `tte` lands on PATH.
%{_bindir}/tte
%{_bindir}/%{pypi_name}

%changelog
* Sat May 30 2026 omedora <noreply@omedora> - 0.15.0-1
- Initial from-source RPM of TerminalTextEffects (provides the `tte` command).
