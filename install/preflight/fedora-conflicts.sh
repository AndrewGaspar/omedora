# Fedora-only conflict DETECTION + WARNING preflight (coexistence MVP).
#
# omedora pins and expects to own a Hyprland desktop stack. On a lived-in Fedora
# machine the user may already have some of those packages installed from a
# FOREIGN repo (e.g. solopasha/hyprland or another COPR). Installing omedora's
# pinned waybar/hyprlock/portal stack against a foreign-repo compositor can leave
# a mismatched, broken session.
#
# This preflight runs the same scan as `omedora doctor` (bin/omarchy-doctor) and:
#   - prints a specific warning for each owned package from a foreign repo, then
#   - lets the user proceed or abort (interactive), or
#   - warns loudly and continues (non-interactive: OMARCHY_NONINTERACTIVE set,
#     or no TTY).
#
# Detection + warning ONLY. No swap / distro-sync — the omedora COPR is not
# install-enabled yet, so an automated swap isn't possible.
#
# Sourced only from install/preflight/all.sh on Fedora hosts. The Arch path is
# unchanged.

# Run the shared scan. omarchy-doctor returns non-zero iff foreign-repo
# conflicts were found; its warnings go to stderr.
if omarchy-doctor; then
  # Clean — nothing to warn about.
  return 0 2>/dev/null || exit 0
fi

echo >&2

# Conflicts found. Decide whether to prompt.
if [[ -n ${OMARCHY_NONINTERACTIVE:-} ]] || [[ ! -t 0 ]] || [[ ! -t 1 ]]; then
  echo -e "\033[33momedora: foreign-repo Hyprland packages detected (see above). \
Continuing because this is a non-interactive install — but the resulting session \
may be mismatched. Run 'omedora doctor' after install and consider swapping the \
foreign packages for omedora's pinned builds.\033[0m" >&2
  return 0 2>/dev/null || exit 0
fi

# Interactive: let the user abort.
if command -v gum >/dev/null 2>&1; then
  if gum confirm "Foreign-repo Hyprland packages detected. Continue installing omedora anyway?"; then
    return 0 2>/dev/null || exit 0
  fi
else
  read -r -p "Foreign-repo Hyprland packages detected. Continue installing omedora anyway? [y/N] " reply
  case "$reply" in
    [yY] | [yY][eE][sS])
      return 0 2>/dev/null || exit 0
      ;;
  esac
fi

echo -e "\033[31momedora: aborting install at user request. Resolve the foreign-repo \
packages (see 'omedora doctor') and re-run.\033[0m" >&2
exit 1
