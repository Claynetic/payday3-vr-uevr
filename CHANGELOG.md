# Changelog

## 2.0 — 2026-09-10
Changes since 1.0 (the version on Nexus and GitHub). Same requirements: PAYDAY 3 3.8 and UEVR nightly-01143, which the installer downloads and verifies.

**New**
- Adjustable weapon position: pull-back, height, pitch and yaw sliders in the UEVR menu (Insert › LuaLoader › Script UI), saved automatically. Defaults, tuned in-game: 9.8 cm back, 4.2 cm down, no pitch or yaw.
- Height, pitch and yaw ease back to zero while you aim down sights, so the sights stay centred.
- Near Clip Plane is enabled at 1 cm in the profile, so sights and arms no longer clip when aiming or reloading.
- Experimental anti wall-clip toggle (Unreal 5.5 first-person scale), off by default.

**Fixed**
- The weapon no longer sits too far ahead: PAYDAY 3 normally draws it magnified about 2× (55° viewmodel FOV), which VR shows at its true position; the default pull-back compensates.
- Tools (phone, cutting tool) appear right after spawning instead of up to ~10 s later.
- Parts that respawn after a custody trade or a weapon swap can no longer stay invisible.
- First-person detection no longer looks at map names, which on some maps could have made your own third-person body visible.

**Changed**
- Much lighter background work: the script checks only your character and its gear once a second, with a map-wide safety check every 10 s (1.0 scanned every mesh on the map every second).
- Installer: if the pinned UEVR build is ever removed from GitHub, it stops instead of silently installing an untested, unverified build. Run `Install.ps1 -AllowUnverified` to accept the latest nightly anyway.
- Releases are built, checked and uploaded by GitHub Actions. Profile script is now v12 (1.0 shipped v8).

## 1.0 — 2026-09-05
First release.
- Profile script v8: moves the first-person rig and equipped weapon/tool meshes out of Starbreeze's TopPass (`SetRenderInTopPass(false)`), so arms, weapons, tools and reload/interaction animations render under UEVR.
- Installer downloads UEVR nightly-01143 (4ee5c6b) from praydog's official GitHub release, SHA-256 verified, and installs the profile with backup of any existing one.
- Launcher starts PAYDAY 3 through Steam and injects UEVR automatically.
- Tested on PAYDAY 3 3.8 (build 24964769), Oculus Rift S, Meta OpenXR runtime, full heists.
