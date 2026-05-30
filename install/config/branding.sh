# Allow the user to change the branding for fastfetch and screensaver
mkdir -p ~/.config/omarchy/branding
cp ~/.local/share/omarchy/icon.txt ~/.config/omarchy/branding/about.txt

# Omedora: seed screensaver with the omedora wordmark on Fedora
_omedora_logo="$HOME/.local/share/omarchy/omedora/branding/logo.txt"
if [[ -f $_omedora_logo ]] && [[ $(omarchy-distro 2>/dev/null || echo arch) == "fedora" ]]; then
  cp "$_omedora_logo" ~/.config/omarchy/branding/screensaver.txt
else
  cp ~/.local/share/omarchy/logo.txt ~/.config/omarchy/branding/screensaver.txt
fi
unset _omedora_logo
