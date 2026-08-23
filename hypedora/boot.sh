#!/bin/bash
# hypedora bootstrap — comanda unică pe un Fedora 44 proaspăt:
#   curl -fsSL https://raw.githubusercontent.com/bsorescu/hypedora/hypedora/hypedora/boot.sh | bash
# Face: preflight (grupul Workstation) → installer-ul omedora-4 NEMODIFICAT (din
# fork-ul nostru, același cod + PR-urile în curs) → post-install (overlay, tweaks VM).
set -eEo pipefail

HYPEDORA_REPO="${HYPEDORA_REPO:-bsorescu/hypedora}"
HYPEDORA_REF="${HYPEDORA_REF:-hypedora}"
OS_RELEASE="${HYPEDORA_OS_RELEASE:-/etc/os-release}"
ARCH="${HYPEDORA_ARCH:-$(uname -m)}"
UID_NUM="${HYPEDORA_UID:-$EUID}"

die() { echo -e "\e[31mhypedora: $*\e[0m" >&2; exit 1; }
echo -e "\nhypedora bootstrap (repo: $HYPEDORA_REPO, ref: $HYPEDORA_REF)\n"

# --- preflight: ce omedora presupune tacit, noi verificăm explicit ------------
(( UID_NUM != 0 )) || die "rulează ca user obișnuit, nu root"
grep -q '^ID=fedora' "$OS_RELEASE" 2>/dev/null || die "doar Fedora"
grep -q '^VERSION_ID=44' "$OS_RELEASE" 2>/dev/null || die "doar Fedora 44 (COPR-ul omedora-4 are doar f44)"
[[ "$ARCH" == x86_64 ]] || die "doar x86_64 (găsit $ARCH)"
command -v flatpak >/dev/null 2>&1 || die "lipsește flatpak → instalarea cere grupul Workstation: sudo dnf group install workstation-product-environment"
command -v gdm >/dev/null 2>&1 || systemctl list-unit-files gdm.service >/dev/null 2>&1 || die "lipsește GDM → sudo dnf group install workstation-product-environment"
echo "preflight hypedora: OK"

# sudo: sub `curl | bash` stdin nu e terminal, iar omedora/boot.sh probează cu
# `sudo -n true` (fără prompt) și moare. Cerem parola noi, o dată, de la /dev/tty,
# ca timestamp-ul sudo să fie cald când intră installer-ul.
TTY="${HYPEDORA_TTY:-/dev/tty}"
if ! sudo -n true 2>/dev/null; then
  if ( exec <"$TTY" ) 2>/dev/null; then
    # shellcheck disable=SC2024 # intenționat: sudo citește parola de pe terminal
    sudo -v <"$TTY" || die "sudo necesar (userul trebuie să fie în grupul wheel)"
  else
    die "sudo necesar: rulează întâi 'sudo -v', apoi comanda din nou"
  fi
fi

# --- checkout: existent (HYPEDORA_BOOT_DIR) sau clone shallow -----------------
if [[ -n "${HYPEDORA_BOOT_DIR:-}" && -f "$HYPEDORA_BOOT_DIR/omedora/boot.sh" ]]; then
  CO="$HYPEDORA_BOOT_DIR"
else
  command -v git >/dev/null 2>&1 || sudo dnf install -y git
  CO="${XDG_CACHE_HOME:-$HOME/.cache}/hypedora/bootstrap"
  rm -rf "$CO"; mkdir -p "$(dirname "$CO")"
  git clone --depth 1 --branch "$HYPEDORA_REF" "https://github.com/${HYPEDORA_REPO}.git" "$CO"
fi

# --- installer-ul omedora-4, nemodificat (rulat din checkout → install-4.sh) --
# OMEDORA_SETUP_FROM_REPO=1: setup-ul de sistem rulează din checkout-ul clonat
# (fork-ul nostru poartă fix-uri pe care build-ul COPR încă nu le are:
# apply-system redenumit, gate-ul snapper). Se scoate la un COPR rebuild.
if [[ "${HYPEDORA_SKIP_INSTALL:-0}" != "1" ]]; then
  OMEDORA_REPO="$HYPEDORA_REPO" OMEDORA_REF="$HYPEDORA_REF" \
    OMEDORA_SETUP_FROM_REPO="${OMEDORA_SETUP_FROM_REPO:-1}" bash "$CO/omedora/boot.sh"
fi

# --- stratul nostru -----------------------------------------------------------
bash "$CO/hypedora/post-install.sh"
# shellcheck disable=SC1111 # ghilimele românești intenționate în mesaj
echo -e "\nhypedora: gata. Reboot și alege sesiunea „Omedora” în GDM.\n"
