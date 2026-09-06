# PAYDAY 3 VR (UEVR) - launcher
# Starts PAYDAY 3 through Steam, waits for the game process, then injects UEVR (with the installed profile).
# Nothing here modifies the game. Close the game normally to end the session.
param(
    [int]$AttachDelay = 25,                 # seconds to wait after the game process appears before injecting
    [string]$Proc = 'PAYDAY3-Win64-Shipping',
    [int]$AppId = 1272080
)
$ErrorActionPreference = 'Stop'
$Root    = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$UevrDir = Join-Path $Root 'UEVR'
$Injector = Join-Path $UevrDir 'UEVRInjector.exe'
$ProfileDir = Join-Path $env:APPDATA 'UnrealVRMod\PAYDAY3-Win64-Shipping'

function Say($m) { Write-Host $m }

try {
Say '=== PAYDAY 3 VR (UEVR) ==='
if (-not (Test-Path $Injector)) {
    Say 'UEVR is not installed yet. Run "1 - INSTALL PAYDAY 3 VR.cmd" first.'
    Read-Host 'Press Enter to close'; exit 1
}
# self-heal: if the profile went missing (fresh Windows user, deleted AppData), reinstall it silently
if (-not (Test-Path (Join-Path $ProfileDir 'scripts\pd3_firstperson_fix.lua'))) {
    Say 'Profile missing - reinstalling it from the bundle...'
    New-Item -ItemType Directory -Force -Path (Join-Path $ProfileDir 'scripts') | Out-Null
    Copy-Item (Join-Path $Root 'profile\PAYDAY3-Win64-Shipping\config.txt')  $ProfileDir -Force
    Copy-Item (Join-Path $Root 'profile\PAYDAY3-Win64-Shipping\cameras.txt') $ProfileDir -Force
    Copy-Item (Join-Path $Root 'profile\PAYDAY3-Win64-Shipping\scripts\pd3_firstperson_fix.lua') (Join-Path $ProfileDir 'scripts') -Force
}
# keep the last few UEVR logs (UEVR overwrites log.txt on every launch)
$log = Join-Path $ProfileDir 'log.txt'
if (Test-Path $log) {
    Copy-Item $log (Join-Path $ProfileDir ("log-prev-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt")) -Force
    Get-ChildItem $ProfileDir -Filter 'log-prev-*.txt' | Sort-Object LastWriteTime -Descending | Select-Object -Skip 3 | Remove-Item -Force -ErrorAction SilentlyContinue
}

$running = Get-Process -Name $Proc -ErrorAction SilentlyContinue
if (-not $running) {
    Say "Starting PAYDAY 3 via Steam (app $AppId)..."
    Start-Process "steam://rungameid/$AppId"
    Say "Waiting for $Proc.exe ..."
    $deadline = (Get-Date).AddMinutes(4)
    do { Start-Sleep 1; $running = Get-Process -Name $Proc -ErrorAction SilentlyContinue } until ($running -or (Get-Date) -gt $deadline)
    if (-not $running) { Say 'The game did not start within 4 minutes. Is Steam running and PAYDAY 3 installed?'; Read-Host 'Press Enter to close'; exit 1 }
    Say "Game process is up. Injecting UEVR in $AttachDelay s (let the game reach its menu)..."
    for ($i = $AttachDelay; $i -gt 0; $i--) { Write-Host -NoNewline "`r  $i s "; Start-Sleep 1 }
    Write-Host ''
} else {
    Say 'PAYDAY 3 is already running - injecting now.'
}

Say 'Launching UEVR injector (Windows will ask for permission)...'
Start-Process -FilePath $Injector -Verb RunAs -ArgumentList "--attach=$Proc.exe"
Say 'UEVR attached. Put the headset on. Home = recenter, Insert = UEVR menu. This window closes in 5 s.'
Start-Sleep 5
} catch {
    Write-Host "Launcher error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  at $($_.InvocationInfo.ScriptLineNumber): $($_.InvocationInfo.Line.Trim())" -ForegroundColor DarkGray
    Read-Host 'Press Enter to close'; exit 1
}
