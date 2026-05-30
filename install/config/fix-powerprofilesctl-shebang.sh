# The shebang fix only applies to the real power-profiles-daemon CLI (a python
# script at /usr/bin/powerprofilesctl). On Fedora, omedora keeps tuned-ppd and
# ships a bash powerprofilesctl shim instead (install/config/
# powerprofilesctl-shim-fedora.sh), which has no python shebang to patch. Skip
# when the real binary isn't present (Arch + Fedora-with-p-p-d still patch it).
[[ -f /usr/bin/powerprofilesctl ]] || return 0

# Ensure we use system python3 and not mise's python3
sudo sed -i '/env python3/ c\#!/bin/python3' /usr/bin/powerprofilesctl
