# Stops the background pump-screen loop (it starts again at next logon, or run the "Pump Screen" Startup shortcut).
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -match 'pump-loop\.ps1|pumpimg\.ps1' -and $_.ProcessId -ne $PID } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
