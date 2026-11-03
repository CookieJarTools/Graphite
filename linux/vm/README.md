# The test VM

An Arch Linux VM in VirtualBox that installs itself and starts straight into the Graphite
Desk shell, running from this checkout through a shared folder.

1. Install **VirtualBox 7** from <https://www.virtualbox.org/wiki/Downloads> (no account).
2. Put the Arch ISO here as `archlinux.iso` (from <https://archlinux.org/download/>, checked
   against its `sha256sums.txt`).
3. Run:
   ```powershell
   powershell -ExecutionPolicy Bypass -File linux\vm\make-vm.ps1
   ```

`make-vm.ps1` creates the VM (UEFI, 4 cores, 8 GB, 40 GB disk, 3D acceleration, this repo
shared as `StartMenu` at `/mnt/StartMenu`), generates the VM user's password into
`credentials.txt`, and starts it. Inside, the live ISO's cloud-init finds the `CIDATA` disc
and runs `install.sh`: Arch with Hyprland, Quickshell and the shell's packages, automatic
sign-in, and the desktop on start. It takes 10 to 20 minutes; the VM switches itself off,
the script takes both discs out and starts it into the desktop. The install's log is
`/root/graphite-install.log` in the VM.

To see the VM's screen from Windows (for scripts and checks):

```powershell
& "$env:ProgramFiles\Oracle\VirtualBox\VBoxManage.exe" controlvm "Graphite (Arch)" screenshotpng shot.png
```

VirtualBox's screenshot can miss what the desktop draws with 3D; from inside, the scripts
here write into this folder through the share. Run them with guest control (the VM user's
password from `credentials.txt` in a file of its own):

```powershell
& "$env:ProgramFiles\Oracle\VirtualBox\VBoxManage.exe" guestcontrol "Graphite (Arch)" run --username graphite --passwordfile pw.txt --exe /bin/bash -- -lc "bash /mnt/StartMenu/linux/vm/look.sh"
```

| Script | |
| --- | --- |
| `look.sh [command]` | Runs a command in the desktop, lists the windows, saves `shot.png` |
| `diag.sh` | Mounts, links, processes, Hyprland's state and log, the shell's log: `diag.txt` |
| `run-shell.sh [VAR=value...]` | Restarts the shell (with extra environment) and keeps its output: `shell.txt` |
| `reload.sh` | Reloads Hyprland's config and reports errors |

In VirtualBox, Hyprland draws with the virtual GPU, but apps can't hand it GPU buffers, so
`hyprland.lua` gives apps Mesa's software GL there (`LIBGL_ALWAYS_SOFTWARE`) and turns off
blur, shadows and window animations, which cost the most drawn by the CPU.

**If the VM is slow:** with Windows' hypervisor on (WSL 2, Virtual Machine Platform, Memory
integrity), VirtualBox runs on top of it, much slower. Turning it off makes the VM far faster,
but WSL 2 and Docker stop working until it is back on:

1. Windows Security → Device security → Core isolation → Memory integrity: off.
2. In an administrator terminal: `bcdedit /set hypervisorlaunchtype off`, then restart.
   (`bcdedit /set hypervisorlaunchtype auto` and a restart bring it back.)

More cores help too, with the VM switched off:
`VBoxManage modifyvm "Graphite (Arch)" --cpus 6`.

Everything here except the scripts and this file stays out of git: the ISOs, the VM and its
disk, `credentials.txt`.
