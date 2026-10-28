<#
Creates the Graphite Desk test VM in VirtualBox, installs Arch Linux into it unattended, and
starts it into the desktop.

  powershell -ExecutionPolicy Bypass -File linux\vm\make-vm.ps1

Needs VirtualBox 7 installed and archlinux.iso in this folder (checked against Arch's
sha256sums.txt). It generates the VM user's password (credentials.txt here, kept out of git),
builds the CIDATA disc cloud-init reads (user-data, install.sh, vm.env), creates the VM (UEFI,
4 cores, 8 GB, 40 GB disk, 3D acceleration, this repo shared as "StartMenu"), and starts the
install. The install takes 10 to 20 minutes and switches the VM off; this script then takes
both discs out (so the installer can never run again over the new system) and starts it.
Run it again to replace the VM: it deletes the old one first.

  -DiscOnly <path>   only build the CIDATA disc at <path> (to check it; no VirtualBox needed)
#>
param([string]$DiscOnly)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$repo = (Resolve-Path "$here\..\..").Path

$userName = 'graphite'
$vmName = 'Graphite Desk (Arch)'
$installMinutes = 60 # how long to wait for the install before giving up

# ---------- VirtualBox ----------

if (-not $DiscOnly) {
    $vbox = "$env:ProgramFiles\Oracle\VirtualBox\VBoxManage.exe"
    if (-not (Test-Path $vbox)) { throw 'VirtualBox is not installed (no VBoxManage.exe found).' }

    $iso = "$here\archlinux.iso"
    if (-not (Test-Path $iso)) { throw "No ${iso}: download the Arch ISO first (see linux\vm\README.md)." }

    # VBoxManage reports progress and notes on stderr; only its exit code tells failure.
    function VBox {
        $ErrorActionPreference = 'Continue' # progress on stderr is not a failure
        $output = & $vbox @args 2>&1
        if ($LASTEXITCODE -ne 0) { throw "VBoxManage $($args -join ' ') failed:`n$output" }
        $output
    }

    function VmState {
        $ErrorActionPreference = 'Continue'
        $info = & $vbox showvminfo $vmName --machinereadable 2>$null
        $line = $info | Where-Object { $_ -like 'VMState=*' } | Select-Object -First 1
        if ($line) { $line.Split('=')[1].Trim('"') } else { '' }
    }

    # An old VM goes first.
    $ErrorActionPreference = 'Continue'
    & $vbox showvminfo $vmName --machinereadable 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host 'Removing the old VM...'
        & $vbox controlvm $vmName poweroff 2>$null | Out-Null
        Start-Sleep -Seconds 3
        VBox unregistervm $vmName --delete | Out-Null
    }
    $ErrorActionPreference = 'Stop'
}

# ---------- the user's password ----------

$alphabet = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'.ToCharArray()
$bytes = New-Object byte[] 20
[Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
$password = -join ($bytes | ForEach-Object { $alphabet[$_ % $alphabet.Length] })
$openssl = @("$env:ProgramFiles\Git\usr\bin\openssl.exe", "$env:ProgramFiles\Git\mingw64\bin\openssl.exe") |
    Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $openssl) { throw 'openssl (part of Git for Windows) is needed to hash the password.' }
# As an argument: piped in, Windows PowerShell adds a CR that openssl keeps in the password.
$hash = (& $openssl passwd -6 $password).Trim()

if (-not $DiscOnly) {
    Set-Content -Path "$here\credentials.txt" -Encoding ascii -Value @(
        'The Graphite Desk test VM (made by make-vm.ps1). Kept out of git.',
        "user:     $userName",
        "password: $password",
        'It signs in by itself; the password is for sudo.'
    )
}

# ---------- the CIDATA disc cloud-init reads ----------

$cidata = Join-Path $env:TEMP "graphite-cidata-$PID"
New-Item -ItemType Directory -Force $cidata | Out-Null
$utf8 = New-Object Text.UTF8Encoding $false
$lf = { param($text) $text -replace "`r`n", "`n" }
[IO.File]::WriteAllText("$cidata\user-data", (& $lf ([IO.File]::ReadAllText("$here\user-data"))), $utf8)
[IO.File]::WriteAllText("$cidata\meta-data", "instance-id: graphite-install`nlocal-hostname: archiso`n", $utf8)
[IO.File]::WriteAllText("$cidata\install.sh", (& $lf ([IO.File]::ReadAllText("$here\install.sh"))), $utf8)
[IO.File]::WriteAllText("$cidata\vm.env", (@(
    "USER_NAME='$userName'",
    "PASSWORD_HASH='$hash'",
    "HOST_NAME='graphite-vm'",
    "TIME_ZONE='Europe/London'",
    "LOCALE='en_GB.UTF-8'",
    "KEYMAP='uk'"
) -join "`n") + "`n", $utf8)

# An ISO 9660 + Joliet image labelled CIDATA, with Windows' own IMAPI2.
if (-not ('IsoWriter' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices.ComTypes;
public static class IsoWriter {
    public static void Save(object stream, string path) {
        var source = (IStream)stream;
        using (var target = File.Create(path)) {
            var buffer = new byte[65536];
            var readPointer = System.Runtime.InteropServices.Marshal.AllocHGlobal(4);
            try {
                while (true) {
                    source.Read(buffer, buffer.Length, readPointer);
                    int read = System.Runtime.InteropServices.Marshal.ReadInt32(readPointer);
                    if (read <= 0) break;
                    target.Write(buffer, 0, read);
                }
            } finally { System.Runtime.InteropServices.Marshal.FreeHGlobal(readPointer); }
        }
    }
}
'@
}
$image = New-Object -ComObject IMAPI2FS.MsftFileSystemImage
$image.FileSystemsToCreate = 3 # ISO 9660 and Joliet
$image.VolumeName = 'CIDATA'
$image.Root.AddTree($cidata, $false)
$result = $image.CreateResultImage()
$discPath = if ($DiscOnly) { $DiscOnly } else { "$here\cidata.iso" }
[IsoWriter]::Save($result.ImageStream, $discPath)
Remove-Item -Recurse -Force $cidata
Write-Host "Built $discPath"
if ($DiscOnly) { return }

# ---------- the VM ----------

Write-Host "Creating $vmName..."
VBox createvm --name $vmName --ostype ArchLinux_64 --basefolder $here --register | Out-Null
VBox modifyvm $vmName --firmware=efi --memory=8192 --cpus=4 `
    --graphicscontroller=vmsvga --vram=128 --accelerate-3d=on `
    --nic1=nat --nic-type1=virtio `
    --audio-enabled=on --audio-out=on `
    --clipboard-mode=bidirectional --mouse=usbtablet --usb-xhci=on `
    --boot1=disk --boot2=dvd --boot3=none --boot4=none | Out-Null

$vmFolder = Join-Path $here $vmName
$disk = Join-Path $vmFolder 'graphite.vdi'
VBox createmedium disk --filename $disk --size 40960 --format VDI | Out-Null
VBox storagectl $vmName --name SATA --add sata --controller IntelAhci --portcount 3 | Out-Null
VBox storageattach $vmName --storagectl SATA --port 0 --device 0 --type hdd --medium $disk | Out-Null
VBox storageattach $vmName --storagectl SATA --port 1 --device 0 --type dvddrive --medium "$here\archlinux.iso" | Out-Null
VBox storageattach $vmName --storagectl SATA --port 2 --device 0 --type dvddrive --medium "$here\cidata.iso" | Out-Null
VBox sharedfolder add $vmName --name StartMenu --hostpath $repo --automount --auto-mount-point /mnt/StartMenu | Out-Null

# ---------- the install ----------

Write-Host 'Installing Arch Linux; the VM switches itself off when done (10 to 20 minutes)...'
VBox startvm $vmName --type gui | Out-Null
$deadline = (Get-Date).AddMinutes($installMinutes)
# Seen running first: just after starting it still reads as off.
while ((VmState) -ne 'running') {
    if ((Get-Date) -gt $deadline) { throw 'The VM did not start; look at the VirtualBox window.' }
    Start-Sleep -Seconds 2
}
while ((VmState) -ne 'poweroff') {
    if ((Get-Date) -gt $deadline) { throw "The install has not finished after $installMinutes minutes; look at the VM's window." }
    Start-Sleep -Seconds 15
}

Write-Host 'Installed. Taking out the discs and starting the desktop...'
VBox storageattach $vmName --storagectl SATA --port 1 --device 0 --type dvddrive --medium none | Out-Null
VBox storageattach $vmName --storagectl SATA --port 2 --device 0 --type dvddrive --medium none | Out-Null
VBox startvm $vmName --type gui | Out-Null
Write-Host 'Done. The password (for sudo) is in linux\vm\credentials.txt.'
