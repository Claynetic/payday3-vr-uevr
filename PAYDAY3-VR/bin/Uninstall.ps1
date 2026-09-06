# Removes the PAYDAY 3 UEVR profile (after backing it up) and the desktop shortcut.
# Does NOT touch the game. Delete this bundle folder yourself afterwards if you want UEVR gone too.
$ErrorActionPreference = 'SilentlyContinue'
$ProfileDir = Join-Path $env:APPDATA 'UnrealVRMod\PAYDAY3-Win64-Shipping'
if (Test-Path $ProfileDir) {
    $bak = "$ProfileDir.removed-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Move-Item $ProfileDir $bak -Force
    Write-Host "Profile moved to $bak (delete it if you do not want it)"
} else { Write-Host 'No profile found.' }
$lnk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'PAYDAY 3 VR.lnk'
if (Test-Path $lnk) { Remove-Item $lnk -Force; Write-Host 'Desktop shortcut removed.' }
Write-Host 'Done. You can delete this folder to remove UEVR as well.'
Read-Host 'Press Enter to close'
