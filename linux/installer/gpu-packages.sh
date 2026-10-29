#!/usr/bin/env bash
# Prints the packages this machine's graphics need, one per line, with their 32-bit parts
# (Steam, Proton and Wine need those; it needs multilib turned on). Used by the installer and
# gaming.sh. "nvidia" on the last line's own when an NVIDIA card is there (callers then set up
# its kernel options and early start).
gpus="$(lspci -nn 2>/dev/null | grep -E 'VGA|3D|Display' || true)"
echo mesa
echo lib32-mesa
echo vulkan-icd-loader
echo lib32-vulkan-icd-loader
if grep -qi nvidia <<<"$gpus"; then
    # The open kernel driver, built for Arch's kernel (RTX 20 series and newer): nothing to
    # compile while installing.
    printf '%s\n' nvidia-open nvidia-utils lib32-nvidia-utils nvidia-settings libva-nvidia-driver egl-wayland
fi
# Whole words: "ATI" is also inside "VGA compatible controller", on every card.
if grep -qiwE 'AMD|ATI|Radeon' <<<"$gpus"; then
    printf '%s\n' vulkan-radeon lib32-vulkan-radeon libva-mesa-driver
fi
if grep -qiw intel <<<"$gpus"; then
    printf '%s\n' vulkan-intel lib32-vulkan-intel intel-media-driver
fi
if grep -qi nvidia <<<"$gpus"; then
    echo "#nvidia"
fi
