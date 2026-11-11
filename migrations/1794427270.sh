echo "Install titlebars for floating workspaces on Fedora"

# omedora: the upstream titlebars migration (1791403310) ran on Fedora while
# omarchy-hyprland-titlebars was mapped to "skip", so it installed nothing.
# The plugin is now packaged in the omedora COPR; Arch installs already have it.
[[ "$(omarchy-distro)" == "fedora" ]] || exit 0

omarchy-pkg-add omarchy-hyprland-titlebars
