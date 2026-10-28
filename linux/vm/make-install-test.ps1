<#
Tries the Graphite Desk USB image (linux/installer/out/*.iso, from build-iso.sh) in a fresh
VirtualBox VM with an empty disk, as a computer booting the USB stick would: UEFI, 4 cores, 4 GB
(beside the dev VM), 40 GB. The installer opens by itself; it erases only this VM's own empty disk.

  powershell -ExecutionPolicy Bypass -File linux\vm\make-install-test.ps1

Run again to start over (the old test VM is deleted). Once installed, take the image out
(Devices > Optical drives) before the restart, as with a USB stick.
#>
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$vbox = "$env:ProgramFiles\Oracle\VirtualBox\VBoxManage.exe"
$vmName = 'Graphite Install Test'
$iso = Get-ChildItem "$here\..\installer\out\*.iso" | Sort-Object LastWriteTime | Select-Object -Last 1
if (-not $iso) { throw 'No image yet: build it first (linux/installer/build-iso.sh).' }

function VBox {
    $ErrorActionPreference = 'Continue'
    $output = & $vbox @args 2>&1
    if ($LASTEXITCODE -ne 0) { throw "VBoxManage $($args -join ' ') failed:`n$output" }
    $output
}

$ErrorActionPreference = 'Continue'
& $vbox showvminfo $vmName --machinereadable 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) {
    & $vbox controlvm $vmName poweroff 2>$null | Out-Null
    Start-Sleep -Seconds 3
    VBox unregistervm $vmName --delete | Out-Null
}
$ErrorActionPreference = 'Stop'

VBox createvm --name $vmName --ostype ArchLinux_64 --basefolder $here --register | Out-Null
VBox modifyvm $vmName --firmware=efi --memory=4096 --cpus=4 --graphicscontroller=vmsvga --vram=128 --accelerate-3d=on `
    --nic1=nat --nic-type1=virtio --audio-enabled=on --audio-out=on --mouse=usbtablet --usb-xhci=on `
    --boot1=dvd --boot2=disk --boot3=none --boot4=none | Out-Null
$disk = Join-Path (Join-Path $here $vmName) 'disk.vdi'
VBox createmedium disk --filename $disk --size 40960 --format VDI | Out-Null
VBox storagectl $vmName --name SATA --add sata --controller IntelAhci --portcount 2 | Out-Null
VBox storageattach $vmName --storagectl SATA --port 0 --device 0 --type hdd --medium $disk | Out-Null
VBox storageattach $vmName --storagectl SATA --port 1 --device 0 --type dvddrive --medium $iso.FullName | Out-Null
VBox startvm $vmName --type gui | Out-Null
"Started '$vmName' from $($iso.Name)."
