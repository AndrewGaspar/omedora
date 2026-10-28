#!/bin/bash
#
# L2: Fedora's libxkbcommon compiles Omarchy's Shift+Caps compose option.
#
# Omarchy 4.5 dropped compose:caps from default/hypr/input.lua and sets
# kb_options = "omarchy:shift_caps_compose", an option defined only in the
# /etc/xkb rules and symbols omedora-settings ships. If Fedora's libxkbcommon
# didn't search /etc/xkb, Hyprland would reject the option and Compose would be
# silently lost. Build the keymap through libxkbcommon itself (ctypes, the
# same xkb_keymap_new_from_names call Hyprland makes) and require Caps_Lock on
# level 1 and Multi_key on level 2 of <CAPS>. Without the /etc/xkb files
# libxkbcommon ignores the unknown option and <CAPS> has no Multi_key, which
# proves the files are what makes it work.
#
# Runs as root inside omedora-test:fedora<N> (called from integration.sh).

set -uo pipefail

REPO=${REPO:-/repo}
. "$REPO/test/helpers.sh"
. "$REPO/omedora/test/fedora/lib/container.sh"
ensure_running_as_root

if dnf install -y -q --setopt=install_weak_deps=False libxkbcommon xkeyboard-config python3 >/tmp/xkb-install.out 2>&1; then
  pass "libxkbcommon and xkeyboard-config install ($(rpm -q libxkbcommon xkeyboard-config | tr '\n' ' '))"
else
  cat /tmp/xkb-install.out >&2
  fail "libxkbcommon and xkeyboard-config install"
fi

option=$(sed -nE 's/^local kb_options = "([^"]+)"/\1/p' "$REPO/default/hypr/input.lua")
assert_equals "default/hypr/input.lua sets the Omarchy compose option" "$option" "omarchy:shift_caps_compose"

# Lay the files out exactly where the spec installs them; remove only what was
# added here.
added=()
for file in rules/evdev symbols/omarchy; do
  grep -qF "%{_sysconfdir}/xkb/$file" "$REPO/omedora/packaging/copr/omedora-settings.spec" \
    || fail "omedora-settings packages /etc/xkb/$file"
  [[ -e /etc/xkb/$file ]] && fail "/etc/xkb/$file is absent before the test"
  added+=("/etc/xkb/$file")
done
pass "omedora-settings packages /etc/xkb/rules/evdev and /etc/xkb/symbols/omarchy"
created_xkb_dir=false
[[ -e /etc/xkb ]] || created_xkb_dir=true
cleanup() {
  rm -f "${added[@]}"
  if $created_xkb_dir; then
    rm -rf /etc/xkb
  fi
}
trap cleanup EXIT

probe() {
  python3 - "$option" <<'PY'
import ctypes
import sys

xkb = ctypes.CDLL("libxkbcommon.so.0")

class RuleNames(ctypes.Structure):
  _fields_ = [(field, ctypes.c_char_p) for field in ("rules", "model", "layout", "variant", "options")]

xkb.xkb_context_new.restype = ctypes.c_void_p
xkb.xkb_context_new.argtypes = [ctypes.c_int]
xkb.xkb_context_num_include_paths.argtypes = [ctypes.c_void_p]
xkb.xkb_context_include_path_get.restype = ctypes.c_char_p
xkb.xkb_context_include_path_get.argtypes = [ctypes.c_void_p, ctypes.c_uint]
xkb.xkb_keymap_new_from_names.restype = ctypes.c_void_p
xkb.xkb_keymap_new_from_names.argtypes = [ctypes.c_void_p, ctypes.POINTER(RuleNames), ctypes.c_int]
xkb.xkb_keymap_key_by_name.restype = ctypes.c_uint32
xkb.xkb_keymap_key_by_name.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
xkb.xkb_keymap_key_get_syms_by_level.argtypes = [
  ctypes.c_void_p, ctypes.c_uint32, ctypes.c_uint32, ctypes.c_uint32, ctypes.POINTER(ctypes.POINTER(ctypes.c_uint32))]
xkb.xkb_keysym_get_name.argtypes = [ctypes.c_uint32, ctypes.c_char_p, ctypes.c_size_t]

context = xkb.xkb_context_new(0)
paths = [xkb.xkb_context_include_path_get(context, i).decode()
         for i in range(xkb.xkb_context_num_include_paths(context))]
print("include-paths " + " ".join(paths))
names = RuleNames(b"evdev", b"pc105", b"us", b"", sys.argv[1].encode())
keymap = xkb.xkb_keymap_new_from_names(context, ctypes.byref(names), 0)
if not keymap:
  print("keymap none")
  sys.exit(0)
caps = xkb.xkb_keymap_key_by_name(keymap, b"CAPS")
levels = []
for level in (0, 1):
  syms = ctypes.POINTER(ctypes.c_uint32)()
  count = xkb.xkb_keymap_key_get_syms_by_level(keymap, caps, 0, level, ctypes.byref(syms))
  name = ctypes.create_string_buffer(64)
  if count > 0:
    xkb.xkb_keysym_get_name(syms[0], name, 64)
  levels.append(name.value.decode() or "-")
print("caps " + " ".join(levels))
PY
}

without=$(probe 2>/dev/null)
assert_output_lacks "without /etc/xkb <CAPS> has no Multi_key (negative control)" "$without" "Multi_key"

install -Dpm644 "$REPO/etc/xkb/rules/evdev" /etc/xkb/rules/evdev
install -Dpm644 "$REPO/etc/xkb/symbols/omarchy" /etc/xkb/symbols/omarchy
with=$(probe 2>&1)
printf '%s\n' "$with"
assert_output_contains "libxkbcommon searches /etc/xkb" "$with" "include-paths /etc/xkb "
assert_output_contains "the keymap puts Caps_Lock then Multi_key on <CAPS>" "$with" "caps Caps_Lock Multi_key"
