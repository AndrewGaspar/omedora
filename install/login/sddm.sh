# omedora: Arch-only. Fedora stays on GDM (no SDDM, and /etc/pam.d edits are
# on omedora's never-touch list). The body below is byte-identical to
# upstream. See omedora/architecture.md §"Omarchy 4 setup-system gating map".
if [[ "${OMARCHY_DISTRO:-$(omarchy-distro 2>/dev/null || echo arch)}" != "arch" ]]; then
  return 0 2>/dev/null || exit 0
fi

# Prevent password-based SDDM logins from creating an encrypted login keyring
# that conflicts with Omarchy's passwordless default keyring behavior. The ISO
# owns autologin/session state because it knows whether the target is encrypted.
if [[ -f /etc/pam.d/sddm ]]; then
  sed -i '/-auth.*pam_gnome_keyring\.so/d' /etc/pam.d/sddm
  sed -i '/-password.*pam_gnome_keyring\.so/d' /etc/pam.d/sddm
fi
