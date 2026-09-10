# PAYDAY 3 VR (UEVR) - installer
# Downloads the exact UEVR nightly this bundle was tested with from praydog's official GitHub release,
# verifies its SHA-256, extracts it next to this bundle, installs the PAYDAY 3 UEVR profile, and puts a
# "PAYDAY 3 VR" shortcut on the desktop. Run again any time; it is safe to repeat.
#
# UEVR is (c) praydog, all rights reserved, and is NOT included in this bundle - it is fetched from
# https://github.com/praydog/UEVR-nightly/releases at install time.
param(
    [string]$ProfileDir = "",        # override the UEVR profile folder (testing); default %APPDATA%\UnrealVRMod\PAYDAY3-Win64-Shipping
    [string]$UevrZip    = "",        # use an already-downloaded UEVR.zip instead of downloading
    [switch]$SkipShortcut,
    [switch]$SkipProfile,
    [switch]$AllowUnverified,        # if the pinned UEVR build is gone, accept the latest nightly without asking
    [switch]$NoPause
)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# --- pinned UEVR build (the one this bundle was tested with) ---------------------------------------
$UevrTag     = 'nightly-01143-4ee5c6b6162dee2291fc75f9dfc57667f6d45a2d'
$UevrUrl     = "https://github.com/praydog/UEVR-nightly/releases/download/$UevrTag/UEVR.zip"
$UevrZipSha  = '4cd6932d1d01168178aef70499d40b101ea6f19868cf76099d8e0087ef8dc6d8'
$BackendSha  = '1a34cf65e4c12002ec967ed167ddda4e1cc7ae1da82157d0e279597beddeed75'   # UEVRBackend.dll
$LatestApi   = 'https://api.github.com/repos/praydog/UEVR-nightly/releases/latest'

$Root    = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)   # bundle root (parent of bin\)
$UevrDir = Join-Path $Root 'UEVR'
$SrcProf = Join-Path $Root 'profile\PAYDAY3-Win64-Shipping'
if (-not $ProfileDir) { $ProfileDir = Join-Path $env:APPDATA 'UnrealVRMod\PAYDAY3-Win64-Shipping' }

function Say($m)  { Write-Host $m }
function Ok($m)   { Write-Host "  [OK]  $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  [!!]  $m" -ForegroundColor Yellow }
function Fail($m) { Write-Host "  [XX]  $m" -ForegroundColor Red; if (-not $NoPause) { Read-Host 'Press Enter to close' }; exit 1 }
# SHA-256 via .NET (not Get-FileHash: that is a script function in Windows PowerShell 5.1 and vanishes when
# powershell.exe inherits a PowerShell 7 PSModulePath, e.g. when launched from a pwsh terminal)
function Sha($f) {
    $alg = [Security.Cryptography.SHA256]::Create(); $fs = [IO.File]::OpenRead($f)
    try { ([BitConverter]::ToString($alg.ComputeHash($fs))).Replace('-', '').ToLower() } finally { $fs.Dispose(); $alg.Dispose() }
}
# Called only when the pinned UEVR build can no longer be downloaded. Decides whether to fall back to the
# LATEST nightly, which is NOT the build this bundle was tested with and cannot be hash-verified (and whose
# injector Launch.ps1 later starts elevated). Return $true to continue with it, $false to stop the install.
# Available: $AllowUnverified (switch), $NoPause (set by scripted/unattended runs, where Read-Host would block).
function Confirm-UnverifiedUevr {
    # Explicit opt-in only: continue with the unverified latest nightly only when -AllowUnverified was passed.
    return [bool]$AllowUnverified
}

try {
Say ''
Say '=== PAYDAY 3 VR (UEVR) installer ==='
Say "Bundle folder : $Root"
Say "Profile target: $ProfileDir"
Say ''

# --- sanity -------------------------------------------------------------------------------------
if (-not [Environment]::Is64BitOperatingSystem) { Fail 'This needs 64-bit Windows.' }
if (-not (Test-Path (Join-Path $SrcProf 'scripts\pd3_firstperson_fix.lua'))) { Fail "Bundle is incomplete: profile\PAYDAY3-Win64-Shipping\scripts\pd3_firstperson_fix.lua is missing. Re-extract the zip." }

# --- 1. UEVR ------------------------------------------------------------------------------------
Say '[1/3] UEVR'
New-Item -ItemType Directory -Force -Path $UevrDir | Out-Null
$zip = Join-Path $UevrDir 'UEVR.zip'
$backend = Join-Path $UevrDir 'UEVRBackend.dll'

if ((Test-Path $backend) -and ((Sha $backend) -eq $BackendSha)) {
    Ok "UEVR $UevrTag already present and verified."
} else {
    if ($UevrZip) {
        if (-not (Test-Path $UevrZip)) { Fail "-UevrZip '$UevrZip' not found." }
        Copy-Item $UevrZip $zip -Force
        Say "  using local zip $UevrZip"
    } elseif (-not ((Test-Path $zip) -and ((Sha $zip) -eq $UevrZipSha))) {
        Say "  downloading $UevrUrl"
        try {
            Invoke-WebRequest -Uri $UevrUrl -OutFile $zip -UseBasicParsing
        } catch {
            Warn "Pinned build could not be downloaded ($($_.Exception.Message))."
            Warn 'Nightly builds are sometimes pruned. The LATEST nightly could be used instead, but it is NOT the build this bundle was tested with and cannot be hash-verified.'
            if (-not (Confirm-UnverifiedUevr)) {
                Fail "Stopped without installing an unverified UEVR. Download UEVR.zip for $UevrTag from https://github.com/praydog/UEVR-nightly/releases and run:  Install.ps1 -UevrZip <path to UEVR.zip>   (or re-run with -AllowUnverified to accept the latest nightly)"
            }
            try {
                $rel = Invoke-RestMethod -Uri $LatestApi -UseBasicParsing -Headers @{ 'User-Agent' = 'PAYDAY3-VR-installer' }
                $asset = $rel.assets | Where-Object { $_.name -eq 'UEVR.zip' } | Select-Object -First 1
                if (-not $asset) { throw 'no UEVR.zip asset in latest release' }
                Say "  latest release: $($rel.tag_name)"
                Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip -UseBasicParsing
                $UevrZipSha = ''; $BackendSha = ''   # unknown build: cannot verify against pinned hashes
            } catch {
                Fail "Could not download UEVR at all ($($_.Exception.Message)). Download UEVR.zip manually from https://github.com/praydog/UEVR-nightly/releases and run:  Install.ps1 -UevrZip <path to UEVR.zip>"
            }
        }
    }
    if ($UevrZipSha) {
        $h = Sha $zip
        if ($h -ne $UevrZipSha) { Remove-Item $zip -Force; Fail "UEVR.zip hash mismatch (got $h). Download corrupted or the release changed. Re-run the installer." }
        Ok 'UEVR.zip hash verified.'
    }
    Say '  extracting...'
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $a = [IO.Compression.ZipFile]::OpenRead($zip)
    try {
        foreach ($e in $a.Entries) {
            if ($e.Name -eq '' ) { continue }
            if ($e.Name -like '*.pdb') { continue }      # 150 MB of debug symbols nobody needs
            [IO.Compression.ZipFileExtensions]::ExtractToFile($e, (Join-Path $UevrDir $e.Name), $true)
        }
    } finally { $a.Dispose() }
    if ($BackendSha -and ((Sha $backend) -ne $BackendSha)) { Fail 'Extracted UEVRBackend.dll does not match the tested build.' }
    Remove-Item $zip -Force -ErrorAction SilentlyContinue
    Ok "UEVR extracted to $UevrDir (revision $(Get-Content (Join-Path $UevrDir 'revision.txt') -ErrorAction SilentlyContinue))"
}
foreach ($f in 'UEVRInjector.exe','UEVRBackend.dll','LuaVR.dll','openxr_loader.dll') {
    if (-not (Test-Path (Join-Path $UevrDir $f))) { Fail "UEVR is missing $f after extraction." }
}

# --- 2. profile ---------------------------------------------------------------------------------
Say '[2/3] PAYDAY 3 UEVR profile'
if ($SkipProfile) {
    Warn 'skipped (-SkipProfile)'
} else {
    if (Test-Path $ProfileDir) {
        $bak = "$ProfileDir.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item $ProfileDir $bak -Recurse -Force
        Warn "An existing profile was found; a copy was saved to $bak"
    }
    New-Item -ItemType Directory -Force -Path (Join-Path $ProfileDir 'scripts') | Out-Null
    Copy-Item (Join-Path $SrcProf 'config.txt')  $ProfileDir -Force
    Copy-Item (Join-Path $SrcProf 'cameras.txt') $ProfileDir -Force
    Copy-Item (Join-Path $SrcProf 'scripts\pd3_firstperson_fix.lua') (Join-Path $ProfileDir 'scripts') -Force
    Ok "profile installed to $ProfileDir"
}

# --- 3. shortcut --------------------------------------------------------------------------------
Say '[3/3] Desktop shortcut'
if ($SkipShortcut) {
    Warn 'skipped (-SkipShortcut)'
} else {
    $desktop = [Environment]::GetFolderPath('Desktop')
    $lnk = Join-Path $desktop 'PAYDAY 3 VR.lnk'
    $ws = New-Object -ComObject WScript.Shell
    $s = $ws.CreateShortcut($lnk)
    $s.TargetPath = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
    $s.Arguments  = "-NoProfile -ExecutionPolicy Bypass -File `"$Root\bin\Launch.ps1`""
    $s.WorkingDirectory = $Root
    $s.IconLocation = "$UevrDir\UEVRInjector.exe,0"
    $s.Description = 'Launch PAYDAY 3 in VR with UEVR (first-person arms fix)'
    $s.Save()
    Ok "shortcut created: $lnk"
}

Say ''
Say '=== Done. Before you launch: ==='
Say '  * Put your headset on and make sure its OpenXR runtime is active'
Say '      Meta Rift / Quest (Link/Air Link): Meta Quest Link app > Settings > General > "Set Meta Quest Link as active OpenXR Runtime"'
Say '      SteamVR headsets (Index/Vive/etc.): SteamVR > Settings > Developer > "Set SteamVR as OpenXR runtime"'
Say '  * Steam must be running and PAYDAY 3 installed'
Say '  * Double-click "PAYDAY 3 VR" on the desktop (or "2 - LAUNCH PAYDAY 3 VR.cmd" in this folder).'
Say '    The game starts, and UEVR injects itself about 25 s after the process appears. Windows will ask for admin once (UEVR).'
Say '  * In game: Home = recenter view, Insert = UEVR menu. Play with keyboard/mouse or a gamepad as usual.'
Say ''
if (-not $NoPause) { Read-Host 'Press Enter to close' }
} catch {
    Write-Host ''
    Write-Host "  [XX]  Installer error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "        at $($_.InvocationInfo.ScriptLineNumber): $($_.InvocationInfo.Line.Trim())" -ForegroundColor DarkGray
    Write-Host '        Re-run the installer. If it keeps failing, report the text above.'
    if (-not $NoPause) { Read-Host 'Press Enter to close' }
    exit 1
}
