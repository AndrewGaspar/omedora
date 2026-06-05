# Fedora coexistence: the ONE up-front "here's everything I'll back up / replace
# — proceed?" gate. Shown BEFORE any change is made.
#
# WHY IT LIVES HERE (before begin.sh): this is the only zone in the install that
# can talk to the user. Everything after begin.sh runs through run_logged(),
# which executes each script with `bash -c ... </dev/null >>logfile 2>&1` — so
# its stdin is /dev/null (a prompt can't read a reply) AND its stdout/stderr go
# to the install log (the user never sees the question). A confirm there is dead
# code. guard.sh..begin.sh is the live-TTY zone, so the gate is sourced from
# preflight/all.sh right after guard.sh and before begin.sh.
#
# WHAT IT AGGREGATES (writing NOTHING — pure dry run):
#   - config files that would be backed up to <path>.pre-omedora-<ts> and then
#     replaced              (omedora-seed-config --plan)
#   - foreign-repo Hyprland packages already installed from a repo omedora does
#     not control           (omarchy-doctor)
#   - whether ~/.bashrc would get the omedora sourcing block appended
# It then asks the user to Proceed or Abort.
#
#   - Abort (interactive)        -> exit 1. Nothing has been touched.
#   - Proceed (interactive)      -> fall through; the install continues and the
#                                   config phase does the backup-then-write.
#   - Non-interactive            -> print the same summary as a warning and
#     (OMARCHY_NONINTERACTIVE,      proceed. Backup-then-write is non-destructive
#      no TTY; e.g. the L4 CI)      anyway (originals are saved, never deleted).
#   - Nothing to back up AND no  -> print a one-line note and proceed WITHOUT
#     foreign-repo conflicts        prompting. The confirm specifically guards
#                                    backup/replace actions; there's nothing to
#                                    confirm when there's nothing destructive.
#
# Test seams: OMEDORA_PLAN_FORCE_INTERACTIVE / OMEDORA_PLAN_FORCE_NONINTERACTIVE
# force the branch (tests have no TTY); OMEDORA_PLAN_SOURCE / OMEDORA_PLAN_DEST
# override the config trees; the confirm uses `gum` if present (else `read`),
# both shimmable on PATH. omarchy-doctor is mockable via OMEDORA_REPOQUERY_CMD.
#
# Sourced only from install/preflight/all.sh on Fedora hosts. The Arch path is
# unchanged. Documented in omedora/architecture.md §5 and §7.
#
# NOTE: deliberately no `set -e` here — this is sourced into install.sh's
# `set -eEo pipefail` shell, so every command below is written to not abort that
# shell (grep/doctor/awk failures are guarded). Do not add set -e/+e (it leaks).

src_config="${OMEDORA_PLAN_SOURCE:-$HOME/.local/share/omarchy/config}"
dest_config="${OMEDORA_PLAN_DEST:-$HOME/.config}"

# --- 1. config plan: what would be backed up / created (writes nothing) ------
plan_out=""
if command -v omedora-seed-config >/dev/null 2>&1 && [[ -d $src_config ]]; then
  plan_out="$(OMEDORA_SEED_SKIP="${OMEDORA_SEED_SKIP-git/config}" \
    omedora-seed-config --plan --source "$src_config" --dest "$dest_config" 2>/dev/null || true)"
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

# --- 2. foreign-repo Hyprland packages already installed (writes nothing) ----
doctor_out=""
doctor_rc=0
if command -v omarchy-doctor >/dev/null 2>&1; then
  doctor_out="$(omarchy-doctor 2>&1)" || doctor_rc=$?
fi

# --- 3. ~/.bashrc block status ----------------------------------------------
bashrc="$HOME/.bashrc"
if [[ -f $bashrc ]] && grep -qF "# >>> omedora >>>" "$bashrc"; then
  bashrc_action="already present (no change)"
elif [[ -f $bashrc ]]; then
  bashrc_action="append omedora sourcing block (your existing ~/.bashrc is preserved)"
else
  bashrc_action="create a minimal ~/.bashrc with the omedora sourcing block"
fi

# Is there anything that warrants a confirmation? Only backups (replacing the
# user's files) and foreign-repo package conflicts are gating; brand-new files
# and the additive bashrc block are non-destructive.
have_conflicts=0
[[ $n_backup -gt 0 ]] && have_conflicts=1
[[ $doctor_rc -ne 0 ]] && have_conflicts=1

omedora_plan_summary() {
  echo
  echo -e "\033[1mOmedora install plan\033[0m  (nothing has been changed yet)"
  if [[ $n_backup -gt 0 ]]; then
    echo -e "\033[33m  ${n_backup} existing config file(s) will be backed up to <file>.pre-omedora-<timestamp> and then replaced:\033[0m"
    local p
    for p in "${backup_paths[@]}"; do echo "      ~/.config/$p"; done
  else
    echo "  No existing config files conflict; nothing will be backed up."
  fi
  echo "  ${create_count} new config file(s) will be added (no existing file at those paths)."
  echo "  ~/.bashrc: ${bashrc_action}."
  echo "  ~/.config/git/config: never touched (your git identity is protected)."
  if [[ $doctor_rc -ne 0 ]]; then
    echo
    echo -e "\033[33m  Foreign-repo Hyprland packages detected — installing omedora's pinned stack over them may leave a mismatched session:\033[0m"
    printf '%s\n' "$doctor_out" | sed 's/^/      /'
  fi
  echo
}

# --- decide interactivity ----------------------------------------------------
# Prompt from the CONTROLLING TERMINAL (/dev/tty), not stdin — so the prompt
# works under `curl ... | bash` (the recommended install one-liner), where the
# script's stdin is the curl pipe rather than a TTY. Fall back to stdin only
# when there is no usable terminal at all.
PROMPT_TTY=/dev/stdin
if { true >/dev/tty; } 2>/dev/null; then PROMPT_TTY=/dev/tty; fi

interactive=1
if [[ -n ${OMARCHY_NONINTERACTIVE:-} ]] || [[ $PROMPT_TTY != /dev/tty ]]; then
  interactive=0
fi
[[ -n ${OMEDORA_PLAN_FORCE_INTERACTIVE:-} ]] && interactive=1
[[ -n ${OMEDORA_PLAN_FORCE_NONINTERACTIVE:-} ]] && interactive=0

# --- offer a pre-install btrfs snapshot (opt-in) -----------------------------
# Independent of the config/foreign gate below: a fresh install changes a lot
# of packages, so on a btrfs root we offer a read-only snapshot of / that the
# whole install can be rolled back to. Interactive only (a snapshot needs a
# yes); records consent in OMEDORA_SNAPSHOT, which install/preflight/
# fedora-snapshot.sh acts on before any change. /home is never touched.
if [[ $interactive -eq 1 && -z ${OMEDORA_SNAPSHOT:-} ]] \
   && [[ "$(findmnt -no FSTYPE / 2>/dev/null || true)" == "btrfs" ]]; then
  echo
  echo -e "\033[1mPre-install snapshot\033[0m  (your root is btrfs)"
  echo "  Omedora can snapshot / now so the whole install is reversible later with"
  echo "  'omedora snapshot rollback <name>' (your /home is a separate subvolume and"
  echo "  is never touched)."
  if command -v gum >/dev/null 2>&1; then
    gum confirm "Take a pre-install snapshot first?" <"$PROMPT_TTY" && export OMEDORA_SNAPSHOT=1
  else
    read -r -p "  Take a pre-install snapshot first? [Y/n] " reply <"$PROMPT_TTY"
    [[ $reply =~ ^[Nn] ]] || export OMEDORA_SNAPSHOT=1
  fi
  if [[ -n ${OMEDORA_SNAPSHOT:-} ]]; then
    echo -e "\033[32m  A snapshot will be taken before any changes.\033[0m"
  else
    echo "  Skipping the snapshot."
  fi
fi

# --- gate --------------------------------------------------------------------
if [[ $have_conflicts -eq 0 ]]; then
  # Nothing destructive to confirm. Note it (if there's anything to add) and go.
  echo -e "\033[32mOmedora: no existing config files conflict and no foreign-repo packages detected; nothing will be backed up. Proceeding.\033[0m"
  # fall through -> proceed
elif [[ $interactive -eq 0 ]]; then
  omedora_plan_summary >&2
  # A foreign-repo Hyprland on the machine WILL file-conflict with omedora's
  # hyprland-no-session during packaging (both own /usr/bin/Hyprland). Without a
  # terminal we can't offer to replace it, and proceeding is a guaranteed dnf
  # failure — so abort with a clear path instead of marching into it.
  if [[ $doctor_rc -ne 0 ]]; then
    echo -e "\033[31mOmedora: foreign-repo Hyprland packages are installed (see above) and this is a non-interactive install, so omedora can't ask whether to replace them. Installing over them would fail with a /usr/bin/Hyprland file conflict.\033[0m" >&2
    echo -e "\033[31m  Fix it, then re-run the install, by either:\033[0m" >&2
    echo -e "\033[31m    • running the installer from a real terminal (not piped through curl) to get the Replace prompt, or\033[0m" >&2
    echo -e "\033[31m    • running 'omedora doctor --fix' now to swap them for omedora's builds.\033[0m" >&2
    echo -e "\033[31mAborting; nothing was changed.\033[0m" >&2
    exit 1
  fi
  echo -e "\033[33mOmedora: proceeding non-interactively. Existing files are backed up (never deleted) before being replaced.\033[0m" >&2
  # fall through -> proceed
else
  # Interactive: show the plan and require an explicit choice.
  omedora_plan_summary

  if [[ $doctor_rc -ne 0 ]]; then
    # Foreign-repo packages present: offer to replace them with omedora's
    # builds. Show the concrete package transaction (the engine's dry run),
    # then a 3-way choice. "Replace" is the single yes — the swap itself is
    # deferred to fedora-swap.sh, which runs once the omedora repos are
    # enabled (the COPR isn't enabled yet at this point).
    echo "  If you replace them, this is the package transaction that will run:"
    omedora-replace-foreign --dry-run 2>/dev/null | sed 's/^/    /'
    echo
    choice=""
    if command -v gum >/dev/null 2>&1; then
      choice="$(gum choose --header \
        "Foreign-repo Hyprland packages detected. What would you like to do?" \
        "Replace" "Keep" "Abort" <"$PROMPT_TTY")"
    else
      read -r -p "  [R]eplace foreign packages, [K]eep them, or [A]bort? [R/k/a] " reply <"$PROMPT_TTY"
      case "$reply" in [kK]*) choice="Keep" ;; [aA]*) choice="Abort" ;; *) choice="Replace" ;; esac
    fi

    case "$choice" in
      Replace)
        # The swap needs the omedora repos enabled, which happens after this
        # gate (fedora-repos.sh). Record consent; fedora-swap.sh applies it.
        export OMEDORA_REPLACE_FOREIGN=1
        echo -e "\033[32mOmedora: will replace the foreign-repo packages after enabling the omedora repos, then continue.\033[0m"
        # fall through -> proceed
        ;;
      Keep)
        echo -e "\033[33mOmedora: keeping your foreign-repo packages. If the session misbehaves, run 'omedora doctor --fix' later to swap them for omedora's builds.\033[0m"
        # fall through -> proceed
        ;;
      *)  # Abort, or empty (gum Esc)
        echo -e "\033[31mOmedora: install aborted at your request. Nothing was changed.\033[0m" >&2
        exit 1
        ;;
    esac
  else
    # Only config backups to confirm: a simple proceed / abort.
    proceed=0
    if command -v gum >/dev/null 2>&1; then
      gum confirm "Proceed with the omedora install (back up & replace the files listed above)?" <"$PROMPT_TTY" && proceed=1
    else
      read -r -p "Proceed with the omedora install (back up & replace the files listed above)? [y/N] " reply <"$PROMPT_TTY"
      case "$reply" in [yY] | [yY][eE][sS]) proceed=1 ;; esac
    fi

    if [[ $proceed -eq 1 ]]; then
      echo -e "\033[32mOmedora: proceeding. Existing files will be backed up before they are replaced.\033[0m"
      # fall through -> proceed
    else
      echo -e "\033[31mOmedora: install aborted at your request. Nothing was changed.\033[0m" >&2
      exit 1
    fi
  fi
fi

# Reaching here means PROCEED: when sourced (the install.sh path) control simply
# returns to preflight/all.sh and the install continues; when executed directly
# (a test run via `bash fedora-plan.sh`) the script ends with status 0.
