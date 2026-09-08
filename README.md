# PAYDAY 3 VR — Real First-Person (UEVR)

PAYDAY 3 in VR through [UEVR](https://github.com/praydog/UEVR) **with your arms, weapons, tools and reload/interaction animations actually rendered**. Every previous PAYDAY 3 UEVR attempt gave you a stereo world and a crosshair — nothing else. This fixes that.

Play with keyboard + mouse or a gamepad, exactly like flat PAYDAY 3. Head looks around, mouse/stick aims. Motion controllers are not used. Works solo and online (it only changes how your own client renders). No game files are modified.

Nexus Mods: **PAYDAY 3 VR - REAL FPS (UEVR)** by [damien3mf](https://www.nexusmods.com/profile/damien3mf) (Payday 3 section). This repository is the source and a download mirror for that page.

## Why it never worked before

Starbreeze draws the first-person rig in a custom engine render pass of their own ("TopPass" — `SBZTopPassRendering`, `bRenderInTopPass`, `OnTopPassFOV`). That pass never runs while the engine is rendering stereo views, and UEVR makes every view a stereo view (`eSSP_PRIMARY`/`eSSP_SECONDARY`, never `eSSP_FULL`) in every render mode, including 2D Screen Mode. So the rig was simply never drawn while UEVR was attached.

The fix is a small UEVR Lua script (`pd3_firstperson_fix.lua`) that, once a second, finds every skeletal/static mesh component owned by the local pawn that belongs to the first-person rig or the equipped weapon/tool and calls `SetRenderInTopPass(false)` on it (falling back to setting the `bRenderInTopPass` property and marking the render state dirty). The rig then goes through the ordinary scene pass, which UEVR renders fine. On a typical spawn it flips 14 components; the game never re-arms them for the rest of the heist.

## What is in this repository

```
PAYDAY3-VR/
  1 - INSTALL PAYDAY 3 VR.cmd            one-time setup
  2 - LAUNCH PAYDAY 3 VR.cmd             start the game in VR (the desktop shortcut runs this)
  3 - UNINSTALL (remove profile and shortcut).cmd
  README.txt                             end-user readme shipped in the release zip
  bin/Install.ps1                        downloads the pinned UEVR nightly (SHA-256 verified), installs the profile, makes the shortcut
  bin/Launch.ps1                         starts PAYDAY 3 via Steam, waits for the process, injects UEVR
  bin/Uninstall.ps1                      removes profile (after backup) and shortcut
  profile/PAYDAY3-Win64-Shipping/        the UEVR profile: config.txt, cameras.txt, scripts/pd3_firstperson_fix.lua
```

Everything is plain text. There is no compiled code in this repository or in the release zips. UEVR itself is **not** redistributed here (praydog's license is all-rights-reserved); `Install.ps1` downloads it from praydog's official GitHub release at install time and verifies the SHA-256 of both the zip and `UEVRBackend.dll` against hashes embedded in the script.

## Install

1. Download `PAYDAY3-VR-1.0.zip` from [Releases](../../releases) and extract it anywhere (it does not need to be in the game folder).
2. Run `1 - INSTALL PAYDAY 3 VR.cmd`. It downloads UEVR `nightly-01143` (commit `4ee5c6b`) from praydog's GitHub, verifies it, extracts it to `UEVR\`, installs the profile to `%APPDATA%\UnrealVRMod\PAYDAY3-Win64-Shipping` (backing up any profile already there) and puts a **PAYDAY 3 VR** shortcut on your desktop.
3. Make your headset the active OpenXR runtime — Meta: Meta Quest Link app › Settings › General › *Set Meta Quest Link as active OpenXR Runtime*; SteamVR: SteamVR › Settings › Developer › *Set SteamVR as OpenXR runtime*.
4. Headset on, Steam running, double-click **PAYDAY 3 VR**. The game starts and UEVR injects itself ~25 s later (one UAC prompt — that is UEVR).

**Already run UEVR?** Grab `PAYDAY3-UEVR-profile-only-1.0.zip` and use UEVR's *Import Config* button, or drop the `PAYDAY3-Win64-Shipping` folder into `%APPDATA%\UnrealVRMod\`. You need a UEVR **nightly** — the Lua API this relies on is not in the 1.05 stable release.

## Keys and tuning

| Key | Action |
|---|---|
| Home | Recenter view |
| PgUp | Recenter horizon |
| End | Reset standing origin |
| Insert | UEVR menu |

- Weapon too big / too close: Insert › Camera › Forward offset −10 to −20, Up +2 to +5 (UEVR saves it to `cameras.txt`).
- Performance: Insert › OpenXR › Resolution scale (ships at 0.90). Native Stereo + Native Stereo Fix is the tested render method.
- Arms clipping into the camera on reloads: Insert › Near Clip Plane › Enable.

## Tested on

PAYDAY 3 3.8 (build 24964769, Aug 2026) · UEVR nightly-01143 (4ee5c6b) · Oculus Rift S, Meta OpenXR runtime · RX 7800 XT / Ryzen 9 5900X · full heists, solo with bots.

## Known limitations

- The weapon is drawn at true world scale rather than Starbreeze's 55° viewmodel FOV, so it reads bigger and closer than on a monitor. Use the camera offsets.
- No depth of field on the weapon (that effect lived in TopPass).
- A game update can rename components or the TopPass property. If arms vanish after a patch, check `%APPDATA%\UnrealVRMod\PAYDAY3-Win64-Shipping\log.txt` for the `[pd3] TopPass summary` line and open an issue with it.

## Building the release zips

No build step. The release zips are the `PAYDAY3-VR/` folder as-is (`PAYDAY3-VR-1.0.zip`) and its `profile/PAYDAY3-Win64-Shipping/` subfolder (`PAYDAY3-UEVR-profile-only-1.0.zip`). Nothing is compiled.

## Credits and disclosure

- [UEVR](https://github.com/praydog/UEVR) by praydog — © praydog, all rights reserved. Not redistributed; fetched from the official releases by the installer.
- Investigation, testing and profile: **damien3mf**. The Lua script and the installer/launcher scripts were written with Claude during that investigation. All was tested over full heists on highly optimized hardware.
- The Flat2VR community and [uevr-profiles.com](https://uevr-profiles.com) for the profile conventions.
- PAYDAY 3 is © Starbreeze Studios. All Rights Reserved.

## License

The scripts and profile in this repository are released under the [MIT License](LICENSE). UEVR and PAYDAY 3 are not covered by it and remain the property of their respective owners.
