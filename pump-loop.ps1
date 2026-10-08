# Keeps the pump screen showing an image/GIF forever, reconnecting after unplug or sleep.
# usage: pump-loop.ps1 -Image <path> [-Rotate 90 -Brightness 100]
# install-autostart.ps1 runs this hidden at logon. Stop it with stop-pump.ps1.
param([Parameter(Mandatory)][string]$Image, [ValidateSet(0, 90, 180, 270)][int]$Rotate = 0, [int]$Brightness = 100)

$created = $false
$mutex = New-Object System.Threading.Mutex($true, 'Local\PumpScreenLoop', [ref]$created)
if (-not $created) { return }   # already running

while ($true) {
    # pumpimg.ps1 returns when the pump is missing or a write fails (unplug, sleep); wait and reconnect.
    try { & (Join-Path $PSScriptRoot 'pumpimg.ps1') -Image $Image -Rotate $Rotate -Brightness $Brightness -Seconds 0 | Out-Null } catch { }
    Start-Sleep -Seconds 5
}
