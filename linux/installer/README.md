# The Graphite Desk installer

A USB stick that installs Arch Linux with Graphite Desk on a computer, in a few friendly
screens (Region, Keyboard, Network, Disk, Account, Privacy, Look and feel, Apps), then sets
it all up while you watch. Without working graphics it falls back to plain text screens.
**It erases the whole disk you choose** (Windows included), so copy anything you want to keep
first.

## Making the USB stick

1. Build the image (on Arch, or in the test VM): `sudo bash linux/installer/build-iso.sh <repo>`.
   It lands in `linux/installer/out/graphite-desk-<date>-x86_64.iso` (about 1.6 GB). It holds
   the repository as committed, so commit first (`GRAPHITE_FROM_WORKTREE=1` puts the working
   folder's changes on it too, for trying them before committing).
2. Write it to a USB stick of 4 GB or more with [Rufus](https://rufus.ie) (choose the image,
   then Start; say yes to "ISO image mode" or "DD image mode", either works) or
   [balenaEtcher](https://etcher.balena.io). The stick is erased.

## Installing

1. If Windows uses **BitLocker**, save its recovery key first (Settings, Privacy and security,
   Device encryption), or the disk may be locked when you want it back.
2. Put the stick in and start the computer from it: press the boot menu key as it starts
   (often F12, F11, F8 or Esc) and choose the USB entry that says **UEFI**. If it refuses to
   start, turn off Secure Boot in the firmware settings (often Del or F2).
3. The installer opens by itself. Pick your country and keyboard, join your Wi-Fi (it is
   remembered in the new system, so it is online from the first start), choose the disk and
   switch on "Erase ... and install", then your name and password (and an optional hint),
   disk encryption and automatic updates, the look, and any apps to install from Flathub
   (and gaming). It takes 10 to 30 minutes.
4. Press Restart at the end; once the screen goes dark, take out the stick. The computer starts
   at Graphite's login screen.

Graphite Desk lives in `/opt/graphite-desk` (the repository, owned by you): change it there,
`git pull` and `git push` as usual (sign in to GitHub first, as the repository is private), or
use Settings, **Update everything**.

## Trying it in a VM first

`linux/vm/make-install-test.ps1` boots the image in a fresh VirtualBox VM with an empty disk.
