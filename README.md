# PAYDAY 3 VR — Real First-Person (UEVR)

PAYDAY 3 in VR through [UEVR](https://github.com/praydog/UEVR) **with your arms, weapons, tools and reload/interaction animations actually rendered**. Every previous PAYDAY 3 UEVR attempt gave you a stereo world and a crosshair — nothing else. This fixes that.

Play with keyboard + mouse or a gamepad, exactly like flat PAYDAY 3. Head looks around, mouse/stick aims. Motion controllers are not used. Works solo and online (it only changes how your own client renders). No game files are modified.

Nexus Mods: **PAYDAY 3 VR - REAL FPS (UEVR)** by [damien3mf](https://www.nexusmods.com/profile/damien3mf) (Payday 3 section). This repository is the source and a download mirror for that page.

## Why it never worked before

Starbreeze draws the first-person rig in a custom engine render pass of their own ("TopPass" — `SBZTopPassRendering`, `bRenderInTopPass`, `OnTopPassFOV`). That pass never runs while the engine is rendering stereo views, and UEVR makes every view a stereo view (`eSSP_PRIMARY`/`eSSP_SECONDARY`, never `eSSP_FULL`) in every render mode, including 2D Screen Mode. So the rig was simply never drawn while UEVR was attached.

The fix is a small UEVR Lua script (`pd3_firstperson_fix.lua`) that, once a second, looks at the local pawn and the weapons/tools/throwables it owns and calls `SetRenderInTopPass(false)` on every mesh component still in TopPass (falling back to setting the `bRenderInTopPass` property and marking the render state dirty). The rig then goes through the ordinary scene pass, which UEVR renders fine. On a typical spawn it flips 14 components; the game never re-arms them for the rest of the heist.

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

1. Download `PAYDAY3-VR-2.0.zip` from [Releases](../../releases) and extract it anywhere (it does not need to be in the game folder). The green *Code › Download ZIP* button works too: run the installer from the `PAYDAY3-VR` folder inside.
2. Run `1 - INSTALL PAYDAY 3 VR.cmd`. It downloads UEVR `nightly-01143` (commit `4ee5c6b`) from praydog's GitHub, verifies it, extracts it to `UEVR\`, installs the profile to `%APPDATA%\UnrealVRMod\PAYDAY3-Win64-Shipping` (backing up any profile already there) and puts a **PAYDAY 3 VR** shortcut on your desktop.
3. Make your headset the active OpenXR runtime — Meta: Meta Quest Link app › Settings › General › *Set Meta Quest Link as active OpenXR Runtime*; SteamVR: SteamVR › Settings › Developer › *Set SteamVR as OpenXR runtime*.
4. Headset on, Steam running, double-click **PAYDAY 3 VR**. The game starts and UEVR injects itself ~25 s later (one UAC prompt — that is UEVR).

**Already run UEVR?** Grab `PAYDAY3-UEVR-profile-only-2.0.zip` and use UEVR's *Import Config* button, or drop the `PAYDAY3-Win64-Shipping` folder into `%APPDATA%\UnrealVRMod\`. You need a UEVR **nightly** — the Lua API this relies on is not in the 1.05 stable release.

## Keys and tuning

| Key | Action |
|---|---|
| Home | Recenter view |
| PgUp | Recenter horizon |
| End | Reset standing origin |
| Insert | UEVR menu |

- Weapon position: Insert › LuaLoader › Script UI has pull-back, height, pitch and yaw sliders (saved automatically). Height, pitch and yaw return to 0 while you aim so the sights stay centred.
- Performance: Insert › OpenXR › Resolution scale (ships at 0.90). Native Stereo + Native Stereo Fix is the tested render method.
- Sights or arms clipping when you aim or reload: the profile ships with Near Clip Plane enabled at 1 cm (Insert › Near Clip Plane); try 0.5 if you still see it.

## Tested on

PAYDAY 3 3.8 (build 24964769, Aug 2026) · UEVR nightly-01143 (4ee5c6b) · Oculus Rift S, Meta OpenXR runtime · RX 7800 XT / Ryzen 9 5900X · full heists, solo with bots (1.0, 5 Sep 2026). 2.0 (profile script v12) re-tested in heists on the same setup on 10 Sep 2026.

## Known limitations

- The weapon is drawn at its true position rather than through Starbreeze's 55° viewmodel FOV, which magnifies it about 2× on a monitor, so in VR it would sit too far ahead. The script pulls the rig back toward your eyes (defaults: 9.8 cm back and 4.2 cm down, adjustable in Insert › LuaLoader › Script UI).
- No depth of field on the weapon (that effect lived in TopPass).
- A game update can rename components or the TopPass property. If arms vanish after a patch, check `%APPDATA%\UnrealVRMod\PAYDAY3-Win64-Shipping\log.txt` for the `[pd3] TopPass summary` line and open an issue with it.

## Building and publishing releases

Nothing is compiled. The release zips are the `PAYDAY3-VR/` folder as-is (`PAYDAY3-VR-<version>.zip`) and its `profile/PAYDAY3-Win64-Shipping/` subfolder (`PAYDAY3-UEVR-profile-only-<version>.zip`).

`.github/workflows/release.yml` builds both zips on every push (downloadable as the `release-zips` artifact) after syntax-checking the Lua and PowerShell, and fails if a zip ever contains a `.dll`/`.exe`. Pushing a `v<version>` tag publishes both zips as a GitHub release (with the matching `CHANGELOG.md` section as release notes), then, if the Nexus secret and variables are set, uploads them to the Nexus page as new versions of the existing files (the previous version is archived, the mod version is bumped, and the same changelog is posted). Without them the Nexus step is skipped with a warning.

One-time setup, in *Settings › Secrets and variables › Actions*: the secret `NEXUSMODS_API_KEY` and the variables `NEXUS_MOD_ID`, `NEXUS_FILE_ID_MAIN` and `NEXUS_FILE_ID_PROFILE` (the comments at the top of the workflow say where each value comes from).

To release: add a `## <version> — <date>` section to `CHANGELOG.md`, commit, then `git tag v<version>` and `git push origin v<version>`.

## Credits and disclosure

- [UEVR](https://github.com/praydog/UEVR) by praydog — © praydog, all rights reserved. Not redistributed; fetched from the official releases by the installer.
- Investigation, testing and profile: **damien3mf**. The Lua script and the installer/launcher scripts were written with Claude during that investigation. All was tested over full heists on highly optimized hardware.
- The Flat2VR community and [uevr-profiles.com](https://uevr-profiles.com) for the profile conventions.
- PAYDAY 3 is © Starbreeze Studios. All Rights Reserved.

## License

The scripts and profile in this repository are released under the [MIT License](LICENSE). UEVR and PAYDAY 3 are not covered by it and remain the property of their respective owners.
