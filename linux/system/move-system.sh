#!/usr/bin/env bash
# Moves Graphite Desk onto another drive, as it is: from a hard drive to a solid-state one, for
# a quicker start and apps that open as quickly as on Windows. The drive named is erased (after
# asking) and laid out as the installer lays one out (a boot partition, then the system), the
# running system is copied onto it, and the computer starts from it from then on. The drive it
# was on is left as it was, and its entry in the computer's boot menu still starts it, until the
# new one has proved itself.
#
#   sudo move-system.sh DISK          erase DISK, copy the system onto it, start from it next time
#   sudo move-system.sh DISK again    copy what has changed since, then restart onto it (with the
#                                     apps closed, so their files are copied as they're left)
set -euo pipefail
disk="${1:-}"
again="${2:-}"
new=/mnt/graphite-move

[ "$(id -u)" = 0 ] || { echo "Run it with sudo." >&2; exit 1; }
[ -d /sys/firmware/efi ] || { echo "This computer doesn't start the UEFI way, which this needs." >&2; exit 1; }
[ -b "$disk" ] && [ "$(lsblk -ndo TYPE "$disk")" = disk ] || { echo "Name a whole drive, as /dev/sdb." >&2; exit 1; }
for point in / /boot; do
    [ "/dev/$(lsblk -ndo PKNAME "$(findmnt -no SOURCE "$point")")" != "$disk" ] ||
        { echo "$disk is the drive the system starts from now." >&2; exit 1; }
done
part() { if [[ "$disk" =~ [0-9]$ ]]; then echo "${disk}p$1"; else echo "${disk}$1"; fi; }

command -v rsync >/dev/null && command -v efibootmgr >/dev/null || pacman -S --needed --noconfirm rsync efibootmgr

if [ "$again" = again ]; then
    [ "$(blkid -s LABEL -o value "$(part 2)" 2>/dev/null)" = graphite ] ||
        { echo "$disk hasn't had the system copied onto it yet: run this without \"again\" first." >&2; exit 1; }
else
    # Copied once already: what's left is "again" (erasing it would only start the copy over).
    [ "$(blkid -s LABEL -o value "$(part 2)" 2>/dev/null)" != graphite ] ||
        { echo "The system is on $disk already. To copy what has changed and restart onto it: sudo $0 $disk again" >&2; exit 1; }
    used=$(df -B1 --output=used / | tail -1)
    [ "$(lsblk -bndo SIZE "$disk")" -gt $(( used + used / 5 + 2 * 1024 ** 3 )) ] ||
        { echo "$disk is too small: the system takes $(( used / 1024 ** 3 )) GB." >&2; exit 1; }
    echo "This erases everything on $disk ($(lsblk -ndo MODEL,SIZE "$disk" | xargs)):"
    lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS "$disk"
    read -rp "Type ERASE to go on: " answer
    [ "$answer" = ERASE ] || { echo "Nothing was changed."; exit 1; }

    { lsblk -lno MOUNTPOINTS "$disk" | grep '^/' || true; } | while IFS= read -r point; do umount "$point"; done
    sgdisk --zap-all "$disk" >/dev/null
    sgdisk -n 1:0:+1G -t 1:ef00 -c 1:boot -n 2:0:0 -t 2:8300 -c 2:graphite "$disk" >/dev/null
    partprobe "$disk"
    udevadm settle
    wipefs -aq "$(part 1)" "$(part 2)"
    mkfs.fat -F 32 -n BOOT "$(part 1)" >/dev/null
    mkfs.ext4 -qF -L graphite "$(part 2)"
fi

mkdir -p "$new"
mountpoint -q "$new" || mount "$(part 2)" "$new"
mkdir -p "$new/boot"
mountpoint -q "$new/boot" || mount "$(part 1)" "$new/boot"
trap 'umount -R "$new" 2>/dev/null || true' EXIT

# Files that vanish while it copies (24) are fine; others not copied (23) are tried again by
# "again".
copied() { [ "$1" = 0 ] || [ "$1" = 24 ] || { [ "$1" = 23 ] && echo "Some files above couldn't be copied; \"again\" tries them again."; }; }
echo "Copying the system. From a hard drive this takes a while; the computer can be used meanwhile."
code=0; rsync -aAXHS --numeric-ids -x --delete --exclude=/lost+found --exclude='/boot/*' --info=progress2 --no-inc-recursive / "$new/" || code=$?
copied "$code"
code=0; rsync -rt --modify-window=2 --delete --info=progress2 /boot/ "$new/boot/" || code=$?
copied "$code"

# The copy finds itself, not the drive it came from: its file systems in fstab, its partition in
# the boot entry.
old_root=$(findmnt -no UUID /); new_root=$(blkid -s UUID -o value "$(part 2)")
old_boot=$(findmnt -no UUID /boot); new_boot=$(blkid -s UUID -o value "$(part 1)")
old_part=$(findmnt -no PARTUUID /); new_part=$(blkid -s PARTUUID -o value "$(part 2)")
sed -i "s/$old_root/$new_root/; s/$old_boot/$new_boot/" "$new/etc/fstab"
sed -i "s/$old_part/$new_part/g" "$new"/boot/loader/entries/*.conf
rm -f "$new/boot/loader/random-seed"
grep -q "$new_root" "$new/etc/fstab" && grep -q "$new_boot" "$new/etc/fstab" &&
    grep -q "$new_part" "$new"/boot/loader/entries/*.conf ||
    { echo "The copy's fstab or boot entry couldn't be pointed at $disk." >&2; exit 1; }

# First in the computer's start-up order (the old drive's entry stays, for its boot menu).
esp_part=$(blkid -s PARTUUID -o value "$(part 1)")
if ! efibootmgr -v | grep -qi "$esp_part"; then
    efibootmgr -q --create --disk "$disk" --part 1 --loader '\EFI\systemd\systemd-bootx64.efi' \
        --label "Graphite Desk ($(lsblk -ndo MODEL "$disk" | xargs))"
fi
entry=$(efibootmgr -v | grep -i "$esp_part" | head -1 | grep -o '^Boot[0-9A-Fa-f]\{4\}' | cut -c5-)
order=$(efibootmgr | sed -n 's/^BootOrder: //p')
efibootmgr -q --bootorder "$(echo "$entry,$order" | tr ',' '\n' | awk '!seen[$0]++' | paste -sd,)"
# An earlier copy's entry whose partition is gone (the drive erased since).
efibootmgr -v | sed -n 's/^Boot\([0-9A-Fa-f]\{4\}\)\*\{0,1\} Graphite Desk .*HD([0-9]*,GPT,\([0-9A-Fa-f-]*\),.*/\1 \2/p' |
    while read -r number partuuid; do
        lsblk -no PARTUUID | grep -qix "$partuuid" || efibootmgr -q -b "$number" -B
    done
# The entry the computer started from today: the way back to the drive it was on.
current=$(efibootmgr | sed -n 's/^BootCurrent: //p')
old_entry=$(efibootmgr | sed -n "s/^Boot$current\*\{0,1\} //p" | cut -f1)

sync
umount -R "$new"
if [ "$again" = again ]; then
    echo "Copied. Restarting onto $disk (the drive it was on is \"$old_entry\" in the boot menu)..."
    sleep 3
    systemctl reboot
else
    echo
    echo "The system is on $disk and starts from it next time. The drive it was on still starts"
    echo "from the computer's boot menu, as \"$old_entry\"."
    echo "Before restarting, close your apps and run: sudo $0 $disk again"
    echo "(it copies what has changed since, then restarts)."
fi
