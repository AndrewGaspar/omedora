# Omedora install plan gate — the ONE up-front "here is everything this install
# will do — proceed?" prompt. Runs BEFORE any change is made to the system:
# before any repo is enabled, before any package lands, before any config is
# written. Ported from omedora-3's install/preflight/fedora-plan.sh and
# reworked for the Omarchy 4 package-backed flow (no install.sh upstream; the
# omedora/omedora-settings RPMs own the payload).
#
# WHAT IT AGGREGATES (writing NOTHING — pure dry run):
#   1. repos that will be enabled (omedora COPR, RPM Fusion free+nonfree,
#      Flathub user remote)
#   2. the dnf/flatpak package transaction (omedora + omedora-settings, plus
#      install/omarchy-base.packages resolved through bin/fedora/pkg.py in
#      dry-run mode)
#   3. the per-file config classification omedora-adopt-user will apply over
#      $HOME (via omedora-seed-config --plan against the CLONED repo's config/
#      tree — at gate time omedora-settings isn't installed yet, so /etc/skel
#      has no omedora payload; the repo tree is the same content)
#   4. default-app & preference changes (browser/mailto only-if-unset, MIME
#      defaults, ~/.XCompose backup-then-write, ~/.bashrc never touched — the
#      v4 RPM ships bash config via /etc/profile.d, not skel .bashrc)
#   5. the omarchy-namespaced /etc drop-ins the omedora-settings RPM ships
#   6. only-if-absent system files the setup scripts may create
#      (/etc/docker/daemon.json, /etc/pam.d/omarchy-lock-*)
#   7. foreign-repo Hyprland packages already installed (omarchy-doctor) with
#      a Replace / Keep / Abort choice
#   8. an opt-in pre-install btrfs snapshot offer
#
# GATE BEHAVIOR:
#   - Interactive          -> show the plan, require an explicit Proceed/Abort
#                             (or Replace/Keep/Abort when foreign packages are
#                             present). Abort -> exit 1, nothing touched.
#   - OMEDORA_PLAN_AUTOCONFIRM=1 -> print the plan and proceed without
#                             prompting (CI / scripted installs). Foreign-repo
#                             conflicts still abort unless OMEDORA_REPLACE_FOREIGN
#                             or OMEDORA_KEEP_FOREIGN is pre-set, because
#                             installing over a foreign Hyprland is a guaranteed
#                             dnf file conflict.
#   - Non-interactive, no autoconfirm -> warn + proceed (backup-then-write is
#                             non-destructive), except foreign conflicts abort.
#
# Test seams (mirroring 3.8.2): OMEDORA_PLAN_FORCE_INTERACTIVE /
# OMEDORA_PLAN_FORCE_NONINTERACTIVE force the branch; OMEDORA_PLAN_SOURCE /
# OMEDORA_PLAN_DEST override the config trees; OMEDORA_PLAN_SKIP_PKGS=1 skips
# the package dry-run (hermetic L1 runs); OMEDORA_REPOQUERY_CMD mocks the
# doctor; gum/findmnt are shimmable on PATH.
#
# NOTE: deliberately no `set -e` here — this is sourced into install-4.sh's
# `set -eEo pipefail` shell, so every command below is written to not abort
# that shell. Do not add set -e/+e (it leaks).

OMEDORA_REPO_ROOT="${OMEDORA_REPO_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)}"

plan_src="${OMEDORA_PLAN_SOURCE:-$OMEDORA_REPO_ROOT/config}"
plan_dest="${OMEDORA_PLAN_DEST:-$HOME/.config}"

# --- 1. repos ---------------------------------------------------------------
copr_project="$("$OMEDORA_REPO_ROOT/bin/omedora-copr" 2>/dev/null || echo 'agaspar/omedora-?')"
repo_lines=()
if [[ -f /etc/yum.repos.d/omedora-local.repo ]]; then
  repo_lines+=("omedora local test repo already present (COPR enable will be skipped)")
else
  repo_lines+=("enable the omedora COPR: $copr_project")
fi
rpm -q rpmfusion-free-release >/dev/null 2>&1 ||
  repo_lines+=("install RPM Fusion free release RPM")
rpm -q rpmfusion-nonfree-release >/dev/null 2>&1 ||
  repo_lines+=("install RPM Fusion nonfree release RPM")
if ! flatpak remotes --user 2>/dev/null | grep -q '^flathub'; then
  repo_lines+=("add the Flathub flatpak remote (--user scope)")
fi
[[ ${#repo_lines[@]} -eq 0 ]] && repo_lines+=("all repos already enabled (nothing to do)")

# --- 2. package transaction (dry run) ----------------------------------------
plan_dnf_names=""
plan_flatpak_ids=""
plan_skips=""
if [[ -z ${OMEDORA_PLAN_SKIP_PKGS:-} ]]; then
  base_pkgs=()
  while IFS= read -r line; do
    line="${line%%#*}"; line="${line//[[:space:]]/}"
    [[ -n $line ]] && base_pkgs+=("$line")
  done < <(cat "$OMEDORA_REPO_ROOT/install/omarchy-base.packages" \
               "$OMEDORA_REPO_ROOT/omedora/install/fedora-baseline.packages")

  pkg_out="$(OMARCHY_PKG_DRY_RUN=1 \
    python3 "$OMEDORA_REPO_ROOT/bin/fedora/pkg.py" add "${base_pkgs[@]}" 2>&1 |
    sed 's/\x1b\[[0-9;]*m//g' || true)"
  plan_dnf_names="$(printf '%s\n' "$pkg_out" |
    grep -m1 '\[dry-run\] sudo dnf install' |
    sed 's/.*install_weak_deps=False //' || true)"
  plan_flatpak_ids="$(printf '%s\n' "$pkg_out" |
    sed -n 's/^Installing via flatpak: //p' | tr '\n' ' ' || true)"
  plan_skips="$(printf '%s\n' "$pkg_out" | grep "skipping '" |
    sed "s/omedora-pkg: skipping '\([^']*\)'.*/\1/" | tr '\n' ' ' || true)"
fi

# --- 3. config plan: what adopt would back up / create (writes nothing) ------
plan_out=""
if [[ -d $plan_src ]]; then
  plan_out="$(OMEDORA_SEED_SKIP="${OMEDORA_SEED_SKIP-git/config}" \
    "$OMEDORA_REPO_ROOT/bin/omedora-seed-config" --plan \
    --source "$plan_src" --dest "$plan_dest" 2>/dev/null || true)"
fi

backup_paths=()
create_count=0
while IFS=$'\t' read -r tag rel; do
  case "$tag" in
    backup) backup_paths+=("$rel") ;;
    create) create_count=$((create_count + 1)) ;;
  esac
done <<<"$plan_out"
n_backup=${#backup_paths[@]}

# --- 7 (detection part). foreign-repo Hyprland packages ----------------------
doctor_out=""
doctor_rc=0
if command -v dnf >/dev/null 2>&1 || [[ -n ${OMEDORA_REPOQUERY_CMD:-} ]]; then
  doctor_out="$("$OMEDORA_REPO_ROOT/bin/omarchy-doctor" 2>&1)" || doctor_rc=$?
fi

# --- the printed plan ---------------------------------------------------------
omedora_plan_summary() {
  echo
  echo -e "\033[1mOmedora install plan\033[0m  (nothing has been changed yet)"
  echo
  echo -e "\033[1m  Repos:\033[0m"
  local l
  for l in "${repo_lines[@]}"; do echo "      • $l"; done
  echo
  echo -e "\033[1m  Packages:\033[0m"
  echo "      • dnf install omedora + omedora-settings (the Omedora session payload:"
  echo "        /usr/bin/omarchy-*, /usr/share/omarchy/**, /etc/skel seeds, the"
  echo "        'Omedora' GDM session entry — GDM itself is left alone)"
  if [[ -n ${OMEDORA_PLAN_SKIP_PKGS:-} ]]; then
    echo "      • (package dry-run skipped: OMEDORA_PLAN_SKIP_PKGS is set)"
  else
    if [[ -n $plan_dnf_names ]]; then
      local n_dnf
      n_dnf=$(wc -w <<<"$plan_dnf_names")
      echo "      • dnf install $n_dnf packages (omarchy-base resolved for Fedora):"
      printf '%s\n' "$plan_dnf_names" | fold -s -w 72 | sed 's/^/          /'
    else
      echo "      • dnf base set: nothing missing (already installed)"
    fi
    [[ -n ${plan_flatpak_ids// /} ]] &&
      echo "      • flatpak install (--user): $plan_flatpak_ids"
    [[ -n ${plan_skips// /} ]] &&
      echo "      • skipped on Fedora (see install/packages/fedora.toml): $plan_skips"
  fi
  echo
  echo -e "\033[1m  Your configs (omedora-adopt-user, backup-then-write):\033[0m"
  echo "      Paths below are classified against the cloned repo's config payload —"
  echo "      the same tree the omedora-settings RPM ships to /etc/skel."
  if [[ $n_backup -gt 0 ]]; then
    echo -e "\033[33m      ${n_backup} existing file(s) will be backed up to <file>.pre-omedora-<timestamp> and then replaced:\033[0m"
    local p
    for p in "${backup_paths[@]}"; do echo "          ~/.config/$p"; done
  else
    echo "      No existing config files conflict; nothing will be backed up."
  fi
  echo "      ${create_count} new config file(s) will be added (no existing file at those paths)."
  echo "      ~/.config/git/config: never touched (your git identity is protected)."
  echo "      ~/.bashrc: never touched (shell setup ships as /etc/profile.d/omarchy.sh)."
  echo
  echo -e "\033[1m  Default-app & preference changes:\033[0m"
  echo "      • set Chromium as the default browser + http(s) handlers — only if you have none set"
  echo "      • set HEY as the mailto handler — only if you have none set"
  echo "      • back up an existing ~/.XCompose before writing omedora's"
  echo "      • GTK bookmarks, xdg user dirs, default keyring (only created if absent)"
  echo "      • a ~/.local/bin/chromium wrapper + chromium.desktop, so omarchy's"
  echo "        Wayland flags apply to Fedora's chromium-browser binary"
  echo
  echo -e "\033[1m  System files (root):\033[0m"
  echo "      • omarchy-namespaced /etc drop-ins shipped by the omedora-settings RPM:"
  echo "          logind: ignore power button · sysctl: file-watcher limits ·"
  echo "          modprobe: USB autosuspend · udev: wifi powersave + power-profile ·"
  echo "          systemd: faster shutdown, nofile limits, docker no-block-boot,"
  echo "          plocate on AC only · resolved: disable multicast, docker DNS ·"
  echo "          sudoers.d: asdcontrol/passwd-tries/tzupdate · profile.d/omarchy.sh ·"
  echo "          fastfetch default config"
  echo "      • /etc/docker/daemon.json: applied from omedora's reference copy ONLY"
  echo "        IF ABSENT (an existing file is never modified)"
  echo "      • /etc/pam.d/omarchy-lock-password (new, omarchy-namespaced PAM service"
  echo "        for the lock screen; no Fedora-owned PAM file is modified)"
  echo "      • firewalld: allow LocalSend (53317/tcp+udp) + Docker-container DNS"
  echo "      • enable services for installed components (cups, avahi, docker.socket);"
  echo "        services Fedora already runs (NetworkManager, bluetooth) are untouched"
  echo "      • NEVER touched: /etc/os-release, nsswitch.conf, skel .bashrc, faillock,"
  echo "        existing pam.d files, GDM config, bootloader, initramfs"
  if [[ $doctor_rc -ne 0 ]]; then
    echo
    echo -e "\033[33m  Foreign-repo Hyprland packages detected — installing omedora's pinned stack over them may leave a mismatched session:\033[0m"
    printf '%s\n' "$doctor_out" | sed 's/^/      /'
  fi
  echo
}

# --- decide interactivity ------------------------------------------------------
# Prompt from the CONTROLLING TERMINAL (/dev/tty), not stdin — so the prompt
# works under `curl ... | bash`, where stdin is the curl pipe.
# Prompt source: the controlling terminal when there is one; otherwise leave
# stdin ALONE (empty PROMPT_TTY -> prompt_stdin adds no redirection). An
# explicit </dev/stdin is never safe as a fallback: when the inherited stdin
# is a consumed/closed pipe (test sweeps, nested scripts), opening /dev/stdin
# fails with "No such device or address" and the prompt path aborts — the
# intermittent coexistence-plan-test failure this comment memorializes.
PROMPT_TTY=""
if { true >/dev/tty; } 2>/dev/null; then PROMPT_TTY=/dev/tty; fi

# Run a prompting command, fed from the tty when we have one.
prompt_stdin() {
  if [[ -n $PROMPT_TTY ]]; then "$@" <"$PROMPT_TTY"; else "$@"; fi
}

interactive=1
if [[ -n ${OMEDORA_PLAN_AUTOCONFIRM:-} || -n ${OMARCHY_NONINTERACTIVE:-} ]] || [[ -z $PROMPT_TTY ]]; then
  interactive=0
fi
[[ -n ${OMEDORA_PLAN_FORCE_INTERACTIVE:-} ]] && interactive=1
[[ -n ${OMEDORA_PLAN_FORCE_NONINTERACTIVE:-} ]] && interactive=0

# --- 8. offer a pre-install btrfs snapshot (opt-in, interactive only) ---------
if [[ $interactive -eq 1 && -z ${OMEDORA_SNAPSHOT:-} ]] \
   && [[ "$(findmnt -no FSTYPE / 2>/dev/null || true)" == "btrfs" ]]; then
  echo
  echo -e "\033[1mPre-install snapshot\033[0m  (your root is btrfs)"
  echo "  Omedora can snapshot / now so the whole install is reversible later with"
  echo "  'omedora snapshot rollback <name>' (your /home is a separate subvolume and"
  echo "  is never touched)."
  if command -v gum >/dev/null 2>&1; then
    prompt_stdin gum confirm "Take a pre-install snapshot first?" && export OMEDORA_SNAPSHOT=1
  else
    prompt_stdin read -r -p "  Take a pre-install snapshot first? [Y/n] " reply
    [[ $reply =~ ^[Nn] ]] || export OMEDORA_SNAPSHOT=1
  fi
  if [[ -n ${OMEDORA_SNAPSHOT:-} ]]; then
    echo -e "\033[32m  A snapshot will be taken before any changes.\033[0m"
  else
    echo "  Skipping the snapshot."
  fi
fi

# --- gate ----------------------------------------------------------------------
if [[ $interactive -eq 0 ]]; then
  omedora_plan_summary >&2
  # A foreign-repo Hyprland WILL file-conflict with omedora's hyprland package
  # during the dnf transaction. Without a terminal we can't ask whether to
  # replace it, so abort with a clear path unless the answer was pre-supplied.
  if [[ $doctor_rc -ne 0 && -z ${OMEDORA_REPLACE_FOREIGN:-} && -z ${OMEDORA_KEEP_FOREIGN:-} ]]; then
    echo -e "\033[31mOmedora: foreign-repo Hyprland packages are installed (see above) and this is a non-interactive install, so omedora can't ask whether to replace them. Installing over them would fail with a file conflict.\033[0m" >&2
    echo -e "\033[31m  Fix it, then re-run the install, by either:\033[0m" >&2
    echo -e "\033[31m    • running the installer from a real terminal to get the Replace prompt, or\033[0m" >&2
    echo -e "\033[31m    • pre-setting OMEDORA_REPLACE_FOREIGN=1 (swap them for omedora's builds) or OMEDORA_KEEP_FOREIGN=1.\033[0m" >&2
    echo -e "\033[31mAborting; nothing was changed.\033[0m" >&2
    exit 1
  fi
  if [[ -n ${OMEDORA_PLAN_AUTOCONFIRM:-} ]]; then
    echo -e "\033[32mOmedora: OMEDORA_PLAN_AUTOCONFIRM set; proceeding with the plan above.\033[0m" >&2
  else
    echo -e "\033[33mOmedora: proceeding non-interactively. Existing files are backed up (never deleted) before being replaced.\033[0m" >&2
  fi
  # fall through -> proceed
else
  omedora_plan_summary

  if [[ $doctor_rc -ne 0 ]]; then
    # Foreign-repo packages present: the 3-way choice IS the gate.
    echo "  If you replace them, this is the package transaction that will run:"
    "$OMEDORA_REPO_ROOT/bin/omedora-replace-foreign" --dry-run 2>/dev/null | sed 's/^/    /'
    echo
    choice=""
    if command -v gum >/dev/null 2>&1; then
      choice="$(prompt_stdin gum choose --header \
        "Foreign-repo Hyprland packages detected. What would you like to do?" \
        "Replace" "Keep" "Abort")"
    else
      prompt_stdin read -r -p "  [R]eplace foreign packages, [K]eep them, or [A]bort? [R/k/a] " reply
      case "$reply" in [kK]*) choice="Keep" ;; [aA]*) choice="Abort" ;; *) choice="Replace" ;; esac
    fi

    case "$choice" in
      Replace)
        # The swap needs the omedora COPR enabled, which happens after this
        # gate (repos.sh). Record consent; repos.sh applies it.
        export OMEDORA_REPLACE_FOREIGN=1
        echo -e "\033[32mOmedora: will replace the foreign-repo packages after enabling the omedora repos, then continue.\033[0m"
        ;;
      Keep)
        export OMEDORA_KEEP_FOREIGN=1
        echo -e "\033[33mOmedora: keeping your foreign-repo packages. If the session misbehaves, run 'omedora doctor --fix' later to swap them for omedora's builds.\033[0m"
        ;;
      *)  # Abort, or empty (gum Esc)
        echo -e "\033[31mOmedora: install aborted at your request. Nothing was changed.\033[0m" >&2
        exit 1
        ;;
    esac
  else
    proceed=0
    if command -v gum >/dev/null 2>&1; then
      prompt_stdin gum confirm "Proceed with the omedora install (apply everything listed above)?" && proceed=1
    else
      prompt_stdin read -r -p "Proceed with the omedora install (apply everything listed above)? [y/N] " reply
      case "$reply" in [yY] | [yY][eE][sS]) proceed=1 ;; esac
    fi

    if [[ $proceed -eq 1 ]]; then
      echo -e "\033[32mOmedora: proceeding. Existing files will be backed up before they are replaced.\033[0m"
    else
      echo -e "\033[31mOmedora: install aborted at your request. Nothing was changed.\033[0m" >&2
      exit 1
    fi
  fi
fi

# Reaching here means PROCEED: when sourced (the install-4.sh path) control
# returns to the orchestrator; when executed directly (a test run via
# `bash plan.sh`) the script ends with status 0.
