# A plain window for the end-to-end tests to group, switch to and maximise.
param([string]$Title, [int]$X, [int]$Y)
Add-Type -AssemblyName System.Windows.Forms
$form = New-Object System.Windows.Forms.Form
$form.Text = $Title
$form.StartPosition = 'Manual'
$form.Location = New-Object System.Drawing.Point($X, $Y)
$form.Size = New-Object System.Drawing.Size(700, 420)
$form.BackColor = [System.Drawing.Color]::FromArgb(40, 42, 46)
[System.Windows.Forms.Application]::Run($form)
