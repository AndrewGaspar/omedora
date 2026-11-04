echo "Install Intel hardware video decoding on GPUs named only \"[Intel Graphics]\", such as Wildcat Lake"

# omedora: Arch-only on Fedora — hardware video acceleration is Fedora/RPM
# Fusion territory (install/hardware/all-fedora.sh skips
# intel/video-acceleration.sh), and vpl-gpu-rt is intel-vpl-gpu-rt there.
[[ "$(omarchy-distro)" == "fedora" ]] && exit 0

# Hardware setup missed these GPUs, so video was decoded on the CPU.
# See install/hardware/intel/video-acceleration.sh.
if lspci | grep -iE 'vga|3d|display' | grep -qi '\[intel graphics'; then
  omarchy-pkg-add intel-media-driver libvpl vpl-gpu-rt
fi
