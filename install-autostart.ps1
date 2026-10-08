# Creates (or with -Remove, deletes) a Startup-folder shortcut that runs pump-loop.ps1 hidden at logon.
# usage: install-autostart.ps1 -Image <path> [-Rotate 90 -Brightness 100]
#        install-autostart.ps1 -Remove
param([string]$Image = '', [ValidateSet(0, 90, 180, 270)][int]$Rotate = 0, [int]$Brightness = 100, [switch]$Remove)

$lnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'Pump Screen.lnk'
if ($Remove) {
    if (Test-Path $lnk) { Remove-Item $lnk; "removed $lnk" } else { 'no autostart shortcut found' }
    return
}
if (-not $Image) { 'usage: install-autostart.ps1 -Image <path> [-Rotate 90 -Brightness 100]'; return }

$Image = (Resolve-Path -LiteralPath $Image).Path
$loop = Join-Path $PSScriptRoot 'pump-loop.ps1'
$s = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk)
$s.TargetPath = Join-Path $env:SystemRoot 'System32\conhost.exe'   # --headless keeps the console window from flashing up
$s.Arguments = "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$loop`" -Image `"$Image`" -Rotate $Rotate -Brightness $Brightness"
$s.WorkingDirectory = $PSScriptRoot
$s.WindowStyle = 7
$s.Save()
"created $lnk"
'it starts at next logon; double-click the shortcut to start it now'
