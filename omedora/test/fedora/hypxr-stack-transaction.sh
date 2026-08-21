#!/bin/bash

# Install the freshly built Quattro XR stack on Fedora 44 with a full-ffmpeg
# package identity that conflicts with ffmpeg-free but owns both capabilities.

set -euo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)
COPR_DIR="$REPO/omedora/packaging/copr"
RPM_REPO="$COPR_DIR/repo"
WORK="$COPR_DIR/output/hypxr-transaction-test"
IMAGE="${OMEDORA_RPMBUILD_IMAGE:-registry.fedoraproject.org/fedora:44}"

[[ -f $RPM_REPO/repodata/repomd.xml ]] || {
  echo "missing local repository metadata: $RPM_REPO/repodata/repomd.xml" >&2
  exit 1
}

rm -rf "$WORK"
mkdir -p "$WORK"

TMPDIR=/var/tmp podman run --rm \
  -v "$RPM_REPO:/repo:ro,z" \
  -v "$WORK:/work:z" \
  "$IMAGE" bash -euo pipefail -c '
    dnf install -y --setopt=install_weak_deps=False rpm-build >/dev/null
    mkdir -p /work/rpmbuild/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
    cat > /work/ffmpeg.spec <<"SPEC"
Name: ffmpeg
Version: 8.0
Release: 1%{?dist}
Summary: Full ffmpeg transaction-test fixture
License: GPL-3.0-or-later
BuildArch: noarch
Conflicts: ffmpeg-free

%description
Faithful package-identity fixture for an RPM Fusion-style full ffmpeg provider.

%prep

%build

%install
install -d %{buildroot}%{_bindir}
printf "#!/bin/bash\nexit 0\n" > %{buildroot}%{_bindir}/ffmpeg
printf "#!/bin/bash\nexit 0\n" > %{buildroot}%{_bindir}/ffprobe
chmod 0755 %{buildroot}%{_bindir}/ffmpeg %{buildroot}%{_bindir}/ffprobe

%files
%{_bindir}/ffmpeg
%{_bindir}/ffprobe
SPEC
    rpmbuild \
      --define "_topdir /work/rpmbuild" \
      --define "_tmppath /var/tmp/rpm-tmp" \
      -bb /work/ffmpeg.spec >/dev/null
    fixture=$(find /work/rpmbuild/RPMS -name "ffmpeg-*.rpm" -print -quit)
    dnf install -y "$fixture" >/dev/null
    cat > /etc/yum.repos.d/omedora-local.repo <<"REPO"
[omedora-local]
name=Omedora local XR test
baseurl=file:///repo
enabled=1
gpgcheck=0
REPO
    dnf install -y --setopt=install_weak_deps=False --setopt=tsflags= \
      hypxrland-omedora >/dev/null

    rpm -q ffmpeg
    ! rpm -q ffmpeg-free
    test "$(rpm -qf /usr/bin/ffmpeg)" = "ffmpeg-8.0-1.fc44.noarch"
    test "$(rpm -qf /usr/bin/ffprobe)" = "ffmpeg-8.0-1.fc44.noarch"
    rpm -q hyprland-no-session hypxrland-omedora hypxrland-stack hypxrland \
      hypxrland-legacy-config hypxrcompose hypxrhud hypxrpaper hypxrva \
      hypxrvoice hypxrvoice-model-base-en wivrn-hypxr omedora-settings

    test -x /usr/libexec/hypxrland/Hyprland
    test -x /usr/libexec/hypxrland/hyprctl
    test -x /usr/bin/hypxrland-session
    grep -F "export PATH=\"/usr/libexec/hypxrland:\$PATH\"" /usr/bin/hypxrland-session
    test -f /usr/share/wayland-sessions/omedora-xr.desktop

    stack_rpm=$(find /repo -name "hypxrland-stack-*.rpm" -print -quit)
    rpm -qp --requires "$stack_rpm" | grep -F \
      "hypxrland >= 0.56.2^20260821.2.git67200a838-1"
    rpm -qp --requires "$stack_rpm" | grep -F \
      "wivrn-hypxr >= 26.6.2^20260820.1.git3729c7b31-1"
    rpm -q --requires hypxrcompose | grep -Fx /usr/bin/ffmpeg
    rpm -q --requires hypxrcompose | grep -Fx /usr/bin/ffprobe
    rpm -q --requires wivrn-hypxr | grep -Fx /usr/bin/ffmpeg

    config=/usr/share/hypxrvoice/config.toml
    awk '\''
      /^\[asr\]$/ { section = "asr"; next }
      /^\[intent\]$/ { section = "intent"; next }
      section == "asr" && /^model = / { asr = ($0 ~ /ggml-base[.]en[.]bin/) }
      section == "intent" && /^model = / { intent = ($0 ~ /^model = ""/) }
      END { exit !(asr && intent) }
    '\'' "$config"
    echo "Packaged voice configuration: passed"

    test -f /usr/share/doc/hypxrhud/hypxrhud-fedora.md
    test -f /usr/share/doc/hypxrcompose/hypxrcompose-fedora.md
    test -f /usr/share/doc/wivrn-hypxr/wivrn-hypxr-fedora.md
    echo "Fedora XR documentation manifests: passed"
    ! rpm -qa | grep -E "omedora-3|hyprland-omedora"
    echo "Fedora 44 Quattro XR transaction with full-ffmpeg fixture: passed"
  '
