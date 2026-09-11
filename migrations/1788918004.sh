echo "Restore the lock screen PAM service when a Fedora install has lost it"

[[ "$(omarchy-distro)" == "fedora" ]] || exit 0

# The Quickshell lock screen authenticates against this PAM service and refuses
# to lock while it is missing (shell/plugins/lock answers missing-pam), so
# System > Lock and the idle lock silently do nothing. On Fedora the file is
# written only by the fresh install (install/config/lockscreen-pam.sh), and no
# update path re-created it afterwards. Re-apply it once when it is missing.
#
# The presence check is the state check: migration state is per-user, so every
# account runs this, and the second one finds the file already there and exits
# without reaching a sudo prompt. Anything already at the path -- an
# administrator's own service, even a dangling symlink -- is left alone.
pam_service="/etc/pam.d/omarchy-lock-password"

if [[ -e $pam_service || -L $pam_service ]]; then
  exit 0
fi

# Dispatches to bin/fedora/setup-lock, which writes only the omarchy-namespaced
# services (password, and fingerprint when one is enrolled) on Fedora's
# system-auth stack; no Fedora-owned PAM file is touched.
omarchy-apply-lock
