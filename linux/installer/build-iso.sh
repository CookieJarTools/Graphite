#!/usr/bin/env bash
# Builds the Graphite Desk USB image: Arch's own install image (archiso's releng profile) with
# Graphite Desk's repository on it and its installer (graphite-install.sh) starting by itself.
# Run as root on Arch Linux (the test VM will do), with the repository's path:
#
#   sudo bash linux/installer/build-iso.sh /mnt/StartMenu
#
# The image lands in linux/installer/out/. Write it to a USB stick with Rufus or balenaEtcher.
set -euo pipefail
repo="$(cd "${1:?give the path of the repository}" && pwd)"
out="$repo/linux/installer/out"
work=/var/tmp/graphite-iso
[ "$(id -u)" = 0 ] || { echo "Run as root (sudo)."; exit 1; }

pacman -S --needed --noconfirm archiso git

# A build stopped halfway can leave the system's /dev and the like mounted inside its folder:
# unmount those first, and never let rm cross into a mount.
clean() {
    { findmnt -rno TARGET | grep "^$work/" || true; } | sort -r | xargs -r -n1 umount -l
    rm -rf --one-file-system "$work"
}
clean
mkdir -p "$work" "$out"
cp -r /usr/share/archiso/configs/releng "$work/profile"
profile="$work/profile"

# Its name, on the stick and in the boot menu.
sed -i \
    -e 's/^iso_name=.*/iso_name="graphite-desk"/' \
    -e 's/^iso_label=.*/iso_label="GRAPHITE_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"/' \
    -e 's/^iso_publisher=.*/iso_publisher="Graphite Desk"/' \
    -e 's/^iso_application=.*/iso_application="Graphite Desk installer"/' \
    "$profile/profiledef.sh"
grep -rl "Arch Linux install medium" "$profile" | xargs -r sed -i 's/Arch Linux install medium/Graphite Desk installer/g'

# What the installer needs on top of Arch's own image.
printf '%s\n' dialog terminus-font >> "$profile/packages.x86_64"

# Graphite Desk's repository as committed (a clean clone: Unix line endings, none of the test
# VM, nothing built), its git history with it and its origin pointing at GitHub, so the
# installed copy can pull updates and push changes. Commit before building.
git config --global --add safe.directory "$repo"
git clone --quiet --no-local "$repo" "$profile/airootfs/usr/share/graphite-desk"
origin="$(git -C "$repo" remote get-url origin 2>/dev/null || true)"
[ -n "$origin" ] && git -C "$profile/airootfs/usr/share/graphite-desk" remote set-url origin "$origin"
echo "Graphite Desk at $(git -C "$repo" log --oneline -1)"

cat > "$profile/airootfs/usr/local/bin/graphite-install" <<'START'
#!/usr/bin/env bash
# Starts the Graphite Desk installer, in a font big enough to read.
setfont ter-v24b 2>/dev/null
exec bash /usr/share/graphite-desk/linux/installer/graphite-install.sh "$@"
START

# The installer opens by itself on the first console.
cat >> "$profile/airootfs/root/.zlogin" <<'LOGIN'

# Graphite Desk: the installer, on the first console.
if [[ "$(tty)" == /dev/tty1 ]]; then
    graphite-install
    echo "The installer closed. Type graphite-install to start it again."
fi
LOGIN

sed -i 's|^file_permissions=(|file_permissions=(\n  ["/usr/local/bin/graphite-install"]="0:0:755"|' "$profile/profiledef.sh"

mkarchiso -v -w "$work/work" -o "$out" "$profile"
clean
chown -R --reference="$repo" "$out"
ls -lh "$out"
