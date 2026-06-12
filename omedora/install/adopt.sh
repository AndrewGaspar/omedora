# Adopt this (existing) user into omedora's shipped defaults. /etc/skel only
# fires at useradd time on Fedora, so omedora-adopt-user replays the
# omedora-settings skel payload over $HOME with the backup-then-write contract
# the plan gate disclosed: missing files are created, identical files are
# untouched, differing files are backed up to <path>.pre-omedora-<ts> first,
# and protected files (.config/git/config) are never written.

echo -e "\n\e[32mOmedora: adopting your \$HOME into the shipped defaults (backup-then-write)\e[0m"

omedora-adopt-user
