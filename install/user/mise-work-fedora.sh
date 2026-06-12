# Fedora sibling of install/user/mise-work.sh (dispatched from its top gate;
# runs as the user under omarchy-provision-user).
#
# Same Work-directory setup as upstream, but Node always installs over the
# network (mise use -g node@latest) — there is no ISO /opt/packages bundle on
# Fedora, regardless of OMARCHY_SETUP_CONTEXT. Best-effort: a failed Node
# download (offline install, registry hiccup) must not abort the whole user
# finalization; mise picks it up later via `mise use -g node@latest`.

mkdir -p "$HOME/Work"
mkdir -p "$HOME/Work/tries"

cat >"$HOME/Work/.mise.toml" <<'EOF'
[env]
_.path = "{{ cwd }}/bin"
EOF

mise trust ~/Work/.mise.toml

mise use -g node@latest ||
  echo -e "\033[33momedora: 'mise use -g node@latest' failed; install Node later with the same command.\033[0m" >&2
