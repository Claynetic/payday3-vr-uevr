PAYDAY 3 VR (UEVR) - full first-person arms, weapons and gestures in VR
=======================================================================

What this is
------------
PAYDAY 3 running in VR through UEVR (praydog's Unreal Engine VR injector), WITH your first-person
arms, gloves, weapons, tools and reload/interaction animations rendered - the thing every previous
PAYDAY 3 UEVR attempt was missing (you only ever got a crosshair).

Why they were missing: Starbreeze draws the first-person rig in a custom render pass of their own
("TopPass") that never runs while the engine is in stereo. The Lua script in this profile finds every
first-person mesh on your heister and equipped weapon and calls SetRenderInTopPass(false) on it, so the
rig is drawn in the normal scene pass, which UEVR renders fine. No game files are modified.

Play with keyboard + mouse or a gamepad, exactly like flat PAYDAY 3. Head movement looks around;
mouse/stick aims. Motion controllers are not used.

Requirements
------------
 * Windows 10/11, 64-bit. PAYDAY 3 on Steam (tested on game version 3.8, build 24964769, Aug 2026).
 * A PC VR headset with an OpenXR runtime: Meta Rift / Rift S / Quest via Link or Air Link (Meta Quest
   Link app), or any SteamVR headset. Tested on an Oculus Rift S with the Meta OpenXR runtime.
 * GPU roughly RX 7800 XT / RTX 4070 class or better for a comfortable 80-90 Hz. Tested: RX 7800 XT.
 * Internet access during install (the installer downloads UEVR, ~39 MB, from praydog's GitHub).

Install (once)
--------------
 1. Extract this folder anywhere you like (your game folder, Documents, a Tools folder - it does not
    matter; nothing needs to be inside the PAYDAY 3 install).
 2. Run  "1 - INSTALL PAYDAY 3 VR.cmd".
    It downloads the exact UEVR nightly this bundle was tested with (build nightly-01143, commit
    4ee5c6b), checks its SHA-256, extracts it into the UEVR\ subfolder, installs the PAYDAY 3 profile
    into %APPDATA%\UnrealVRMod\PAYDAY3-Win64-Shipping (backing up any profile already there) and puts a
    "PAYDAY 3 VR" shortcut on your desktop.
 3. Make your headset's runtime the active OpenXR runtime:
      Meta:    Meta Quest Link app > Settings > General > "Set Meta Quest Link as active OpenXR Runtime"
      SteamVR: SteamVR > Settings > Developer > "Set SteamVR as OpenXR runtime"

Play
----
 * Headset on, Steam running. Double-click "PAYDAY 3 VR" on the desktop (or "2 - LAUNCH PAYDAY 3 VR.cmd").
 * The game starts. About 25 seconds after the process appears UEVR injects itself; Windows asks for
   administrator permission once (that is UEVR). The game switches to the headset.
 * Keys:  Home = recenter view   PgUp = recenter horizon   End = reset standing origin
          Insert = UEVR menu (settings, camera offsets, etc.)
 * Your arms and weapon appear about one second after you spawn into a heist (the script runs once
   per second and moves any new first-person meshes out of TopPass as they appear).

Tuning
------
 * Weapon looks too big / too close: Insert > Camera tab > Forward offset -10 to -20, Up offset +2 to +5.
   UEVR saves this to cameras.txt automatically.
 * Performance: Insert > OpenXR > Resolution scale (profile ships at 0.90). Native Stereo + Native Stereo
   Fix is the tested render method; leave it unless you have a reason.
 * Arms or gun clipping into the camera during reloads: Insert > Near Clip Plane > Enable (value 0.01).

Known limitations
-----------------
 * The weapon is drawn at true scale in the world instead of Starbreeze's narrow 55 degree "viewmodel"
   FOV, so it sits bigger and closer than on a flat screen. Use the camera offsets above to taste.
 * No depth-of-field on the weapon (that effect lived in TopPass).
 * Tested on the PAYDAY 3 build above with UEVR nightly-01143. A game update can change component
   names or the TopPass property; if arms disappear after a patch, check the UEVR log
   (%APPDATA%\UnrealVRMod\PAYDAY3-Win64-Shipping\log.txt) for the "[pd3] TopPass summary" line.
 * Solo and online play work the same as flat PAYDAY 3; this changes only how your own client renders.

Files
-----
 1 - INSTALL PAYDAY 3 VR.cmd          one-time setup (downloads UEVR, installs profile, makes shortcut)
 2 - LAUNCH PAYDAY 3 VR.cmd           start the game in VR (the desktop shortcut runs this)
 3 - UNINSTALL ... .cmd               removes the profile (backed up) and the shortcut
 bin\Install.ps1 / Launch.ps1 / Uninstall.ps1     the scripts behind the .cmd files (readable, plain PowerShell)
 profile\PAYDAY3-Win64-Shipping\      the UEVR profile: config.txt, cameras.txt, scripts\pd3_firstperson_fix.lua
 UEVR\                                created by the installer; UEVR itself lives here

Already have UEVR? You do not need the installer: import profile\PAYDAY3-Win64-Shipping with UEVR's
"Import Config" button (zip that folder first) or copy it into %APPDATA%\UnrealVRMod\, then inject
as usual. You need a UEVR NIGHTLY build - the Lua scripting API this relies on is not in the 1.05 stable
release.

Credits and disclosure
----------------------
 * UEVR by praydog - https://github.com/praydog/UEVR - (c) praydog, all rights reserved. UEVR is not
   redistributed in this bundle; the installer downloads it from praydog's official releases.
 * Investigation, testing and profile by damien3mf (nexusmods.com/profile/damien3mf). The Lua script and installer scripts were
   written with Claude (Anthropic) as part of that investigation - this mod is tagged "AI-Generated
   Content" on Nexus as required. Every line was tested on real hardware over full heists before release.
 * PAYDAY 3 is (c) Starbreeze Studios. This mod contains no game assets and modifies no game files.

Version
-------
 1.0  -  first release. Profile script v8 (SetRenderInTopPass fix), UEVR nightly-01143, PAYDAY 3 3.8.
